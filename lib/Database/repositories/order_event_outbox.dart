import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../Core/connectivity/connectivity_service.dart';
import '../device_identity_service.dart';

/// Durable retry queue for order-lifecycle calls (`posPayments:reportEvent`, and any legacy
/// `orders:recordX` mutation) whose outcome must never be silently lost — these report the
/// real-world result of money already having moved (or not). A plain fire-and-forget call would
/// lose that report forever if the app is killed, or the network drops, between the SoftPay SDK
/// resolving and the call reaching Convex — leaving an order stuck at `paymentStatus: "pending"`
/// while a card was actually charged, with nothing left to reconcile it against.
///
/// Each entry is persisted to disk BEFORE the first send attempt, and removed only once Convex
/// has actually accepted it — a kill/crash/restart mid-flight just means the entry is retried
/// again on the next flush, never lost. `deviceToken` is deliberately NOT part of the persisted
/// args (it rotates every session) — [flush]/[_send] inject whichever token is current at send
/// time.
///
/// Every entry also carries a stable `idempotencyKey` (generated once, at enqueue time) that
/// `posPayments:reportEvent`/`recordRefund`/`recordCancellation` dedupe against — a retry of an
/// entry that actually succeeded server-side but never got its ack back to this device (killed or
/// lost connectivity right after) is recognized as already-applied instead of inserting a second
/// event or re-running a state transition a second time (double-refunding, in the worst case).
///
/// Whether a queued entry is a Convex mutation or action — `posPayments:
/// reportEvent` is an action (it calls the TCS-D HTTP client), everything
/// else queued here is a plain mutation. Stored per-entry so `flush()` can
/// dispatch each one through the right ConvexClient method.
enum OutboxCallType { mutation, action }

class OrderEventOutbox {
  OrderEventOutbox._();

  static final OrderEventOutbox instance = OrderEventOutbox._();

  static const _storageKey = 'order_event_outbox';

  // A permanently-failing entry (e.g. a genuine application-level rejection, not a network
  // hiccup) must never block every OTHER queued report behind it forever. Once an entry has
  // failed this many times WHILE this device was actually online (see [flush]'s online check -
  // that condition is what tells "the server said no" apart from "we couldn't reach it at all"),
  // it's dropped rather than retried again. Kept deliberately low: an online failure is either a
  // genuine business-rule rejection (won't fix itself by retrying) or an extremely transient
  // server hiccup (a couple of retries covers that).
  static const _maxOnlineAttempts = 3;

  bool _flushing = false;
  bool _wired = false;

  // Every read-modify-write of the persisted queue (enqueue's append, and each step of flush's
  // processing) goes through this chain so they can never interleave - without it, enqueue()
  // appending a fresh entry while flush() is mid-loop (each holding its own stale in-memory
  // snapshot) could have one overwrite the other's write, silently dropping whichever entry
  // wasn't included in the write that "won".
  Future<void> _chain = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _chain;
    final completer = Completer<void>();
    _chain = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// Call once at startup (see main.dart) — wires this outbox to retry automatically the moment
  /// connectivity comes back, on top of the explicit flush a fresh [enqueue] already triggers.
  void start() {
    if (_wired) return;
    _wired = true;
    ConnectivityService.instance.isOnline.addListener(() {
      if (ConnectivityService.instance.isOnline.value) unawaited(flush());
    });
    unawaited(flush());
  }

  /// Persists [name]/[args] (a Convex mutation/action name and its args, minus `deviceToken`) to
  /// disk — awaiting this is the durability point: once it returns, the report survives an app
  /// kill — then makes a best-effort immediate send attempt in the background. Fire-and-forget;
  /// use [enqueueAndTryNow] instead when the caller needs the live result (e.g. to decide whether
  /// to print a receipt or trigger a refund) rather than just a durable background report.
  Future<void> enqueue(
    String name,
    Map<String, dynamic> args, {
    OutboxCallType callType = OutboxCallType.mutation,
    String? idempotencyKey,
  }) async {
    await _synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final entries = _load(prefs);
      entries.add({
        'name': name,
        'args': args,
        'idempotencyKey': idempotencyKey ?? const Uuid().v4(),
        'attempts': 0,
        'callType': callType.name,
      });
      await prefs.setString(_storageKey, jsonEncode(entries));
    });
    unawaited(flush());
  }

  /// Same durability guarantee as [enqueue] (persisted to disk before anything is sent, so an app
  /// kill mid-flight never loses the report), but additionally makes an immediate, awaited send
  /// attempt and returns its raw result to the caller — for callers that need to act on the live
  /// outcome right now (e.g. `posPayments:reportEvent`'s fiscal result decides whether to print a
  /// receipt or trigger an automatic refund), not just fire-and-forget background reporting.
  ///
  /// Returns null if the immediate attempt failed for a TRANSIENT reason (offline, timeout, an
  /// unexpected server-side error) — the entry stays durably queued and is retried by the normal
  /// [flush] loop like any other entry; the caller should treat null as "recorded, outcome
  /// pending" rather than an error, since the report itself is never lost even when this returns
  /// null.
  ///
  /// Throws [ClientError_ConvexError] if the backend function itself explicitly rejected the
  /// request (e.g. `posPaymentsInternal.recordEvent`'s `ORDER_NOT_REFUNDABLE`) — a deterministic
  /// application-level "no" that will never succeed by retrying, so the entry is dropped from the
  /// queue rather than left to retry forever, and the caller MUST catch this and show a real
  /// error rather than silently treating it like a queued-for-retry null.
  Future<String?> enqueueAndTryNow(
    String name,
    Map<String, dynamic> args, {
    required OutboxCallType callType,
    required String idempotencyKey,
  }) async {
    await _synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final entries = _load(prefs);
      entries.add({
        'name': name,
        'args': args,
        'idempotencyKey': idempotencyKey,
        'attempts': 0,
        'callType': callType.name,
      });
      await prefs.setString(_storageKey, jsonEncode(entries));
    });

    final token = DeviceIdentityService.instance.token;
    if (token == null) return null;
    try {
      final raw = await _send(
        name: name,
        args: args,
        token: token,
        idempotencyKey: idempotencyKey,
        callType: callType,
      );
      await _removeEntry(idempotencyKey);
      return raw;
    } on ClientError_ConvexError {
      // A genuine application-level rejection — the server has definitively said no (e.g.
      // ORDER_NOT_REFUNDABLE), and retrying the exact same request will only fail again forever.
      // Drop it so it doesn't sit in the queue being retried pointlessly, and rethrow so the
      // caller can surface a real error instead of mistaking this for "queued, pending".
      await _removeEntry(idempotencyKey);
      rethrow;
    } catch (_) {
      // Transient failure (offline, timeout, unexpected server error) — left queued, the
      // background flush loop (triggered below) or the next connectivity restore will retry it.
      // Same idempotencyKey either way, so a later successful retry can never double-report this
      // same event.
      unawaited(flush());
      return null;
    }
  }

  Future<String> _send({
    required String name,
    required Map<String, dynamic> args,
    required String token,
    required String idempotencyKey,
    required OutboxCallType callType,
  }) {
    final fullArgs = {
      'deviceToken': token,
      'idempotencyKey': idempotencyKey,
      ...args,
    };
    return callType == OutboxCallType.action
        ? ConvexClient.instance.action(name: name, args: fullArgs)
        : ConvexClient.instance.mutation(name: name, args: fullArgs);
  }

  /// Attempts to send every queued entry, in order, stopping once the head of the queue fails
  /// while genuinely offline (retried on the next flush) or once the queue is empty. An entry
  /// that fails while actually online is retried up to [_maxOnlineAttempts] times before being
  /// dropped, so one bad entry can't wedge every legitimately-queued report behind it forever.
  /// Safe to call repeatedly/concurrently — re-entrant calls are no-ops while a flush is already
  /// in flight.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (true) {
        final token = DeviceIdentityService.instance.token;
        if (token == null) return; // Nothing to send to without a live pairing.

        final entry = await _synchronized(() async {
          final prefs = await SharedPreferences.getInstance();
          final entries = _load(prefs);
          return entries.isEmpty ? null : entries.first;
        });
        if (entry == null) return;

        // Checked with `is! String` (never throws), not `as String` (would throw and escape
        // this loop entirely before the try/catch below ever runs) - a single malformed entry
        // must never be able to jam every legitimately-queued report behind it forever. Every
        // entry is only ever constructed by `enqueue` below with a valid idempotencyKey, so this
        // should never actually trigger - it's a backstop, not an expected path.
        final rawIdempotencyKey = entry['idempotencyKey'];
        if (rawIdempotencyKey is! String) {
          await _removeFirstEntry();
          continue;
        }
        final idempotencyKey = rawIdempotencyKey;

        final callType = entry['callType'] == 'action'
            ? OutboxCallType.action
            : OutboxCallType.mutation;

        try {
          await _send(
            name: entry['name'] as String,
            args: entry['args'] as Map<String, dynamic>,
            token: token,
            idempotencyKey: idempotencyKey,
            callType: callType,
          );
        } on ClientError_ConvexError {
          // Same reasoning as enqueueAndTryNow's ClientError_ConvexError branch: a deterministic
          // application-level rejection doesn't fix itself by retrying, so drop it immediately
          // rather than burning _maxOnlineAttempts retries on a request that can never succeed.
          await _removeEntry(idempotencyKey);
          continue;
        } catch (_) {
          final online = ConnectivityService.instance.isOnline.value;
          final rawAttempts = entry['attempts'];
          final attempts = (rawAttempts is int ? rawAttempts : 0) + 1;
          if (online && attempts >= _maxOnlineAttempts) {
            // A genuine application-level rejection (we reached the server and it still said
            // no) doesn't fix itself by retrying forever - drop it and keep the rest of the
            // queue moving.
            await _removeEntry(idempotencyKey);
            continue;
          }
          await _synchronized(() async {
            final prefs = await SharedPreferences.getInstance();
            final entries = _load(prefs);
            final index = entries.indexWhere(
              (e) => e['idempotencyKey'] == idempotencyKey,
            );
            if (index != -1) entries[index]['attempts'] = attempts;
            await prefs.setString(_storageKey, jsonEncode(entries));
          });
          return; // Stop this pass - retried on the next flush (connectivity restore or enqueue).
        }
        await _removeEntry(idempotencyKey);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _removeEntry(String idempotencyKey) {
    return _synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final entries = _load(prefs);
      entries.removeWhere((e) => e['idempotencyKey'] == idempotencyKey);
      await prefs.setString(_storageKey, jsonEncode(entries));
    });
  }

  /// Drops whatever is currently at the head of the queue by position, not by idempotencyKey -
  /// used only when an entry is malformed enough that we can't even trust its key to identify
  /// it safely (see the `is! String` check above).
  Future<void> _removeFirstEntry() {
    return _synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final entries = _load(prefs);
      if (entries.isNotEmpty) entries.removeAt(0);
      await prefs.setString(_storageKey, jsonEncode(entries));
    });
  }

  List<Map<String, dynamic>> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } catch (_) {
      // A corrupt queue must never block future reports - drop it and start fresh.
      return [];
    }
  }
}

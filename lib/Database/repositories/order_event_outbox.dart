import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../Core/connectivity/connectivity_service.dart';
import '../device_identity_service.dart';

/// Durable retry queue for order-lifecycle mutations (`recordPaymentResult`, `recordRefund`,
/// `recordCancellation`) whose outcome must never be silently lost — these report the real-world
/// result of money already having moved (or not). A plain fire-and-forget mutation call would
/// lose that report forever if the app is killed, or the network drops, between the SoftPay SDK
/// resolving and the mutation reaching Convex — leaving an order stuck at `paymentStatus:
/// "pending"` while a card was actually charged, with nothing left to reconcile it against.
///
/// Each entry is persisted to disk BEFORE the first send attempt, and removed only once Convex
/// has actually accepted it — a kill/crash/restart mid-flight just means the entry is retried
/// again on the next flush, never lost. `deviceToken` is deliberately NOT part of the persisted
/// args (it rotates every session) — [flush] injects whichever token is current at send time.
///
/// Every entry also carries a stable `idempotencyKey` (generated once, at enqueue time) that
/// Convex's `recordPaymentResult`/`recordRefund`/`recordCancellation` dedupe against — a retry of
/// an entry that actually succeeded server-side but never got its ack back to this device (killed
/// or lost connectivity right after) is recognized as already-applied instead of inserting a
/// second event or re-running a state transition a second time (double-refunding, in the worst
/// case for `recordRefund`).
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

  /// Persists [name]/[args] (a Convex mutation name and its args, minus `deviceToken`) to disk —
  /// awaiting this is the durability point: once it returns, the report survives an app kill —
  /// then makes a best-effort immediate send attempt in the background.
  Future<void> enqueue(String name, Map<String, dynamic> args) async {
    await _synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final entries = _load(prefs);
      entries.add({
        'name': name,
        'args': args,
        'idempotencyKey': const Uuid().v4(),
        'attempts': 0,
      });
      await prefs.setString(_storageKey, jsonEncode(entries));
    });
    unawaited(flush());
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

        final idempotencyKey = entry['idempotencyKey'] as String;
        try {
          await ConvexClient.instance.mutation(
            name: entry['name'] as String,
            args: {
              'deviceToken': token,
              'idempotencyKey': idempotencyKey,
              ...(entry['args'] as Map<String, dynamic>),
            },
          );
        } catch (_) {
          final online = ConnectivityService.instance.isOnline.value;
          final attempts = (entry['attempts'] as int? ?? 0) + 1;
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

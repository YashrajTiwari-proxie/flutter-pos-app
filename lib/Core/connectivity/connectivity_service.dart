import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Process-wide, continuously-running internet reachability monitor - shared by every screen
/// (POS, Kiosk, ...) rather than each one running its own one-off check. Deliberately not just
/// "check once when a button is pressed": combines connectivity_plus's OS-level network-interface
/// change events (near-instant reaction when Wi-Fi/cellular actually drops) with a periodic
/// actual-reachability probe, since an interface can report "connected" to a router/AP without
/// there being a working path to the internet.
///
/// [isOnline] stays live for the whole app session - including while a payment is in progress,
/// not just at the moment the Charge button was tapped - so [ConnectivityBanner] reflects
/// connectivity loss the instant it happens, mid-charge or not.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  // Short enough that losing internet reads as "the banner just appeared" rather than "it took
  // a while to notice" - this is what actually makes the check feel continuous, since
  // connectivity_plus's own change events only fire when a network interface fully drops, not
  // when it's still "connected" to a router/AP with no real internet behind it (the far more
  // common failure mode) - that case is only ever caught by this periodic probe.
  static const _probeInterval = Duration(seconds: 3);
  static const _probeTimeout = Duration(seconds: 2);
  // connectivity_plus only reports whether a radio (Wi-Fi/cellular) is switched on and
  // associated with a network - it says nothing about whether that network can actually reach
  // the internet (e.g. a router with no working WAN uplink still reports "connected"). An actual
  // HTTP request to a real page is what proves there's a working path out, not just a DNS
  // answer - some captive portals/firewalls resolve DNS just fine while blocking real traffic.
  // gstatic's generate_204 endpoint is the same one Android's own OS uses for this exact
  // purpose: a real, always-up, effectively-empty page so the probe is cheap.
  static final _probeUri = Uri.parse('https://www.gstatic.com/generate_204');

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _probeTimer;
  bool _started = false;

  /// Starts continuous monitoring. Safe to call from every screen that wants it (main.dart calls
  /// it once at startup) - only the first call actually wires anything up.
  void start() {
    if (_started) return;
    _started = true;

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.every((result) => result == ConnectivityResult.none)) {
        isOnline.value = false;
      } else {
        // The interface coming up doesn't guarantee real internet - confirm with a probe rather
        // than immediately reporting online.
        unawaited(checkNow());
      }
    });

    _probeTimer = Timer.periodic(_probeInterval, (_) => checkNow());
    unawaited(checkNow());
  }

  /// Stops the background listener/timer. Not called anywhere today - this is a process-wide
  /// singleton meant to run for the app's whole lifetime - but kept for symmetry/tests.
  void stop() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _probeTimer?.cancel();
    _probeTimer = null;
    _started = false;
  }

  /// Runs an immediate reachability probe and updates [isOnline]. Also invoked by the periodic
  /// timer above; exposed publicly so the payment flow can force one more fresh check right
  /// before charging, layered on top of (not instead of) the continuous background monitoring.
  Future<bool> checkNow() async {
    final client = HttpClient()..connectionTimeout = _probeTimeout;
    try {
      final request = await client.headUrl(_probeUri).timeout(_probeTimeout);
      final response = await request.close().timeout(_probeTimeout);
      await response.drain<void>();
      // Any completed response - even a non-2xx one - proves the request actually reached a
      // server and got an answer back, which is the real signal; the status code doesn't matter.
      isOnline.value = true;
      return true;
    } on Object {
      isOnline.value = false;
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

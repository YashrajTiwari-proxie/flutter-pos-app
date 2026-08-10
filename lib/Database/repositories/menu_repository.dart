import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device_identity_service.dart';
import '../models/menu_category.dart';

/// Menu browsing for paired devices — always the full (unfiltered) shape
/// from `menu:listForDevice`, since both POS and Kiosk need to show
/// unavailable/sold-out items grayed-out rather than hidden.
/// `menu:listPublic` (guest-safe, no device token) is kept available via
/// [fetchPublicMenu] for a future unauthenticated storefront, but neither
/// in-app flavour uses it today.
class MenuRepository {
  MenuRepository._();

  static final MenuRepository instance = MenuRepository._();

  static const _cacheKeyPrefix = 'menu_cache_';

  String get _deviceToken {
    final token = DeviceIdentityService.instance.token;
    if (token == null) {
      throw StateError(
        'Device is not paired — call DeviceIdentityService.pair() first',
      );
    }
    return token;
  }

  Future<List<MenuCategory>> fetchMenu() async {
    final raw = await ConvexClient.instance.query('menu:listForDevice', {
      'deviceToken': _deviceToken,
    });
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => MenuCategory.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  /// Live version of [fetchMenu] — a stock/price/availability change staff
  /// makes on the dashboard reaches an already-open POS/kiosk screen
  /// immediately, instead of only on the next manual refresh. This is what
  /// both `EmployeeTerminalScreen` and `KioskMenuScreen` actually use;
  /// [fetchMenu] stays available for one-shot call sites.
  ///
  /// The device must already be paired and online to reach this call at all (see
  /// `DeviceIdentityService.bootstrap`'s "no offline fallback" doc comment) — the disk cache
  /// here (keyed by this device's own install id, stable across restarts/re-pairing) exists
  /// purely to paint a menu instantly on cold start instead of a blank screen while the first
  /// live update is still in flight. It is never treated as a substitute for live data: if the
  /// subscription itself fails, that failure is reported via [onError] as-is, not masked by
  /// quietly falling back to the stale cache. Price/availability actually used to place or charge
  /// an order always comes from the live `menu:listForDevice` payload, never this cache.
  Future<SubscriptionHandle> subscribeToMenu({
    required void Function(List<MenuCategory> categories) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) async {
    final installId = DeviceIdentityService.instance.installId;
    if (installId != null) {
      final cached = await _loadCache(installId);
      if (cached != null) onUpdate(cached);
    }

    return await ConvexClient.instance.subscribe(
      name: 'menu:listForDevice',
      args: {'deviceToken': _deviceToken},
      onUpdate: (raw) {
        if (installId != null) unawaited(_persistCache(installId, raw));
        final decoded = jsonDecode(raw) as List<dynamic>;
        onUpdate(
          decoded
              .map(
                (entry) => MenuCategory.fromJson(entry as Map<String, dynamic>),
              )
              .toList(),
        );
      },
      onError: onError,
    );
  }

  Future<void> _persistCache(String installId, String raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cacheKeyPrefix$installId', raw);
  }

  Future<List<MenuCategory>?> _loadCache(String installId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cacheKeyPrefix$installId');
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((entry) => MenuCategory.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A corrupt/incompatible cache entry should never block startup - just behave as if there
      // were no cache at all.
      return null;
    }
  }

  /// Guest-safe menu for a given restaurant slug — deliberately takes no
  /// device token, mirroring `menu:listPublic`'s own "as public as a
  /// printed menu" design on the backend.
  Future<List<MenuCategory>> fetchPublicMenu(String restaurantSlug) async {
    final raw = await ConvexClient.instance.query('menu:listPublic', {
      'restaurantSlug': restaurantSlug,
    });
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => MenuCategory.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}

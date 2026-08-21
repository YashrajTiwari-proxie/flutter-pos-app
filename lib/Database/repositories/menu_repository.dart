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

  // Applied to the one-shot queries below (never to subscribeToMenu, which is long-lived by
  // design) - without this, a Convex call that never responds would leave the awaiting caller
  // stuck indefinitely. See order_repository.dart's identical constant/reasoning.
  static const _timeout = Duration(seconds: 20);

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
    final raw = await ConvexClient.instance
        .query('menu:listForDevice', {'deviceToken': _deviceToken})
        .timeout(_timeout);
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
  /// here exists purely to paint a menu instantly on cold start instead of a blank screen while
  /// the first live update is still in flight. It is never treated as a substitute for live
  /// data: if the subscription itself fails, that failure is reported via [onError] as-is, not
  /// masked by quietly falling back to the stale cache. Price/availability actually used to
  /// place or charge an order always comes from the live `menu:listForDevice` payload, never
  /// this cache.
  ///
  /// Keyed by **restaurantId**, not the device's install id — a device physically stays the
  /// same install id across a revoke + re-pair into a *different* restaurant (including into a
  /// different organization entirely; org plays no role in device pairing at all), but its
  /// cached menu must not follow it there. Keying by install id was a real bug: a kiosk
  /// redeployed from Restaurant A to Restaurant B would briefly flash Restaurant A's stale menu
  /// (names, prices, images) on cold start, before the live subscription for Restaurant B
  /// overwrote it - not a security hole (`createDeviceOrder` re-validates every item's
  /// restaurantId server-side), but a real cross-tenant data leak in the UI. Keying by
  /// restaurantId fixes this with no explicit "clear the cache on revoke/re-pair" step needed
  /// anywhere: the same restaurant across launches/re-pairings still hits the same key (no
  /// regression to the fast-paint behavior), while a genuinely different restaurant simply has
  /// nothing cached yet under its own key.
  Future<SubscriptionHandle> subscribeToMenu({
    required void Function(List<MenuCategory> categories) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) async {
    final restaurantId = DeviceIdentityService.instance.identity?.restaurantId;
    if (restaurantId != null) {
      final cached = await _loadCache(restaurantId);
      if (cached != null) onUpdate(cached);
    }

    return await ConvexClient.instance.subscribe(
      name: 'menu:listForDevice',
      args: {'deviceToken': _deviceToken},
      onUpdate: (raw) {
        if (restaurantId != null) unawaited(_persistCache(restaurantId, raw));
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

  Future<void> _persistCache(String restaurantId, String raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cacheKeyPrefix$restaurantId', raw);
  }

  Future<List<MenuCategory>?> _loadCache(String restaurantId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cacheKeyPrefix$restaurantId');
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
    final raw = await ConvexClient.instance
        .query('menu:listPublic', {'restaurantSlug': restaurantSlug})
        .timeout(_timeout);
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => MenuCategory.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}

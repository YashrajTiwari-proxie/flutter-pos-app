import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import '../models/device_info.dart';

/// One config applied to every device of every flavour paired to a
/// restaurant — set on the admin dashboard, read live via `whoAmI`.
class RestaurantAppearance {
  const RestaurantAppearance({
    required this.themeMode,
    required this.accentColorHex,
  });

  factory RestaurantAppearance.fromJson(Map<String, dynamic> json) =>
      RestaurantAppearance(
        themeMode: json['themeMode'] as String,
        accentColorHex: json['accentColorHex'] as String,
      );

  /// `"light"` or `"dark"`.
  final String themeMode;

  /// Includes the leading `#`, e.g. `"#F3775C"`.
  final String accentColorHex;
}

/// Printed-receipt customization for a restaurant — see
/// `printer_service.dart`'s `printReceipt`.
class RestaurantReceiptConfig {
  const RestaurantReceiptConfig({
    this.logoUrl,
    this.headerText,
    this.footerText,
  });

  factory RestaurantReceiptConfig.fromJson(Map<String, dynamic> json) =>
      RestaurantReceiptConfig(
        logoUrl: json['logoUrl'] as String?,
        headerText: json['headerText'] as String?,
        footerText: json['footerText'] as String?,
      );

  final String? logoUrl;
  final String? headerText;
  final String? footerText;
}

/// Result of `devices:whoAmI` — lets a freshly-paired device self-configure
/// (which restaurant, which device type) without a second staff-driven
/// lookup.
class DeviceWhoAmI {
  const DeviceWhoAmI({
    required this.restaurantId,
    required this.deviceType,
    required this.restaurantSlug,
    required this.restaurantName,
    this.settingsRecoveryCodeHash,
    this.appearance,
    this.receipt,
    this.kioskVideoUrl,
    this.kioskHeaderLogoUrl,
  });

  factory DeviceWhoAmI.fromJson(Map<String, dynamic> json) => DeviceWhoAmI(
    restaurantId: json['restaurantId'] as String,
    deviceType: json['deviceType'] as String,
    restaurantSlug: json['restaurantSlug'] as String,
    restaurantName: json['restaurantName'] as String,
    settingsRecoveryCodeHash: json['settingsRecoveryCodeHash'] as String?,
    appearance: json['appearance'] != null
        ? RestaurantAppearance.fromJson(
            json['appearance'] as Map<String, dynamic>,
          )
        : null,
    receipt: json['receipt'] != null
        ? RestaurantReceiptConfig.fromJson(
            json['receipt'] as Map<String, dynamic>,
          )
        : null,
    kioskVideoUrl: json['kioskVideoUrl'] as String?,
    kioskHeaderLogoUrl: json['kioskHeaderLogoUrl'] as String?,
  );

  final String restaurantId;
  final String deviceType;
  final String restaurantSlug;
  final String restaurantName;

  /// Hash (never the raw code) of this device's offline Settings recovery
  /// code — cache this locally (see `DeviceIdentityService`) so a
  /// recovery code can be validated with zero network calls.
  final String? settingsRecoveryCodeHash;

  /// Null until a manager configures one on the admin dashboard — callers
  /// should keep whatever local default they already have in that case.
  final RestaurantAppearance? appearance;
  final RestaurantReceiptConfig? receipt;

  /// Looping background video for the kiosk's idle/start screen - see
  /// `kiosk_background_video.dart`. Null when unset (falls back to the bundled local asset).
  final String? kioskVideoUrl;

  /// The kiosk ordering screen's own top-bar logo - deliberately separate from
  /// `receipt.logoStorageId`. Null when unset (falls back to a plain storefront icon).
  final String? kioskHeaderLogoUrl;
}

/// Result of `devices:startPairing` — either this hardware was already an
/// active, recognized device (immediate fresh [token], no code involved),
/// or it's unrecognized/revoked and needs the human-in-the-loop code flow
/// ([requestId]/[code]/[pollToken]/[expiresAt] all set instead).
class PairingOutcome {
  const PairingOutcome._({
    required this.isActive,
    this.token,
    this.requestId,
    this.code,
    this.pollToken,
    this.expiresAt,
  });

  factory PairingOutcome.fromJson(Map<String, dynamic> json) {
    if (json['status'] == 'active') {
      return PairingOutcome._(isActive: true, token: json['token'] as String);
    }
    return PairingOutcome._(
      isActive: false,
      requestId: json['requestId'] as String,
      code: json['code'] as String,
      pollToken: json['pollToken'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (json['expiresAt'] as num).toInt(),
      ),
    );
  }

  /// True when this hardware was already paired — [token] is set and no
  /// further action is needed. False means show [code] and start polling.
  final bool isActive;
  final String? token;
  final String? requestId;
  final String? code;
  final String? pollToken;
  final DateTime? expiresAt;
}

/// Result of one `devices:pollPairingRequest` call.
enum PairingPollStatus { pending, claimed, expired }

class PairingPollResult {
  const PairingPollResult({required this.status, this.token});

  factory PairingPollResult.fromJson(Map<String, dynamic> json) {
    switch (json['status'] as String) {
      case 'pending':
        return const PairingPollResult(status: PairingPollStatus.pending);
      case 'claimed':
        return PairingPollResult(
          status: PairingPollStatus.claimed,
          token: json['token'] as String,
        );
      default:
        return const PairingPollResult(status: PairingPollStatus.expired);
    }
  }

  final PairingPollStatus status;
  final String? token;
}

/// Device pairing/identity calls. [startPairing]/[pollPairingRequest] take
/// no persisted device token — that's the whole point, none exists yet.
/// [whoAmI]/[heartbeat] take a `deviceToken` explicitly (rather than
/// reading it off `DeviceIdentityService`) since they're also used during
/// the pairing handshake itself, before any token is stored.
class DeviceRepository {
  DeviceRepository._();

  static final DeviceRepository instance = DeviceRepository._();

  // Applied to every one-shot query/mutation below (never to `subscribeToStatus`, which is
  // long-lived by design and never expected to "complete"). Without this, a hung underlying
  // Convex client call - not something this repo has ever independently verified can't happen -
  // would leave `PairingScreen` frozen on "Setting up this device…" forever, with no retry loop
  // ever getting a chance to run again. 20s is generous for a real round-trip (including a slow
  // mobile/kiosk network) but still bounded. A `TimeoutException` here needs no special
  // handling of its own - every caller already catches exceptions generically and retries
  // (`PairingScreen._runPairingLoop`) or falls back (`DeviceIdentityService.verifyRecoveryCodeOffline`,
  // which already uses this same pattern with a shorter timeout for its own reasons).
  static const _timeout = Duration(seconds: 20);

  Future<PairingOutcome> startPairing({
    required String installId,
    required String deviceType,
    required DeviceInfo deviceInfo,
  }) async {
    final raw = await ConvexClient.instance
        .mutation(
          name: 'devices:startPairing',
          args: {
            'installId': installId,
            'deviceType': deviceType,
            'deviceInfo': deviceInfo.toJson(),
          },
        )
        .timeout(_timeout);
    return PairingOutcome.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PairingPollResult> pollPairingRequest({
    required String requestId,
    required String pollToken,
  }) async {
    final raw = await ConvexClient.instance
        .mutation(
          name: 'devices:pollPairingRequest',
          args: {'requestId': requestId, 'pollToken': pollToken},
        )
        .timeout(_timeout);
    return PairingPollResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<DeviceWhoAmI> whoAmI(String deviceToken) async {
    final raw = await ConvexClient.instance
        .query('devices:whoAmI', {'deviceToken': deviceToken})
        .timeout(_timeout);
    return DeviceWhoAmI.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> heartbeat(String deviceToken) {
    return ConvexClient.instance
        .mutation(name: 'devices:heartbeat', args: {'deviceToken': deviceToken})
        .timeout(_timeout);
  }

  /// Redeems a short-lived, single-use code staff generated on the admin
  /// dashboard for this specific device — the ONLINE settings-unlock
  /// path. Throws if the code is wrong, already used, expired, or was
  /// generated for a different device. See `DeviceIdentityService`'s
  /// cached `settingsRecoveryCodeHash` for the offline fallback.
  Future<void> redeemSettingsUnlockCode({
    required String deviceToken,
    required String code,
  }) {
    return ConvexClient.instance
        .mutation(
          name: 'devices:redeemSettingsUnlockCode',
          args: {'deviceToken': deviceToken, 'code': code},
        )
        .timeout(_timeout);
  }

  /// Live-watches this device's own status via `devices:whoAmI` — since
  /// that query's authorization check re-reads the `devices` row on every
  /// call, Convex's reactivity re-runs it (and [onError] fires) the moment
  /// staff revokes the device, instead of only finding out on the next
  /// unrelated action that happens to fail. [DeviceIdentityService] uses
  /// this to unpair itself in near real time on revocation.
  Future<SubscriptionHandle> subscribeToStatus({
    required String deviceToken,
    required void Function(DeviceWhoAmI info) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) {
    return ConvexClient.instance.subscribe(
      name: 'devices:whoAmI',
      args: {'deviceToken': deviceToken},
      onUpdate: (raw) => onUpdate(
        DeviceWhoAmI.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      ),
      onError: onError,
    );
  }
}

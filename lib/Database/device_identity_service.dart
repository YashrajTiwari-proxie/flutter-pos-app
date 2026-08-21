import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../Core/app_mode.dart';
import '../Core/theme/theme_controller.dart';
import '../Services/tcs/pos_payments_service.dart';
import 'device_hardware.dart';
import 'remote_asset_cache.dart';
import 'repositories/device_repository.dart';

/// This physical device's pairing with a restaurant — resolved fresh from
/// `devices:whoAmI` every time pairing succeeds, never cached across app
/// restarts (see [DeviceIdentityService.bootstrap]'s doc comment for why).
class DeviceIdentity {
  const DeviceIdentity({
    required this.restaurantId,
    required this.restaurantSlug,
    required this.restaurantName,
    required this.deviceType,
  });

  final String restaurantId;
  final String restaurantSlug;
  final String restaurantName;
  final String deviceType;
}

/// A pending pairing handshake — shown on [PairingScreen] as a 6-digit
/// code (+ QR) while [DeviceIdentityService.waitForClaim] polls in the
/// background. `code`/`pollToken`/`expiresAt` all come straight from
/// `devices:startPairing`'s response.
class PairingChallenge {
  const PairingChallenge({
    required this.requestId,
    required this.code,
    required this.pollToken,
    required this.expiresAt,
  });

  final String requestId;
  final String code;
  final String pollToken;
  final DateTime expiresAt;
}

/// Owns this device's pairing lifecycle. Deliberately does NOT persist the
/// device token across launches — only the app-generated `installId` is
/// persisted (via `shared_preferences`). On every launch, [bootstrap] calls
/// `devices:startPairing` with that installId: recognized, still-active
/// hardware gets a freshly rotated token back immediately (no code, no
/// staff involved); unrecognized or revoked hardware gets a
/// [PairingChallenge] instead, so a device that's been revoked server-side
/// is caught and re-pairs on its very next launch rather than silently
/// keeping on with a token that no longer works.
///
/// For a device that's revoked *mid-session* (app already running,
/// nothing has failed yet), [_finishPairing] also opens a live
/// `devices:whoAmI` subscription (see `DeviceRepository.subscribeToStatus`)
/// — Convex pushes an error the moment the `devices` row's `isActive`
/// flips, and [_handleRevoked] reacts by flipping [isPairedNotifier] back
/// to false immediately, rather than waiting for the next order/menu call
/// to happen to fail.
///
/// Also owns the local Settings-screen lock: [redeemSettingsUnlockCode]
/// (online, staff-generated on the dashboard) and
/// [verifyRecoveryCodeOffline] (offline, checked purely against a locally
/// cached hash — see [_cacheRecoveryHash], refreshed on every successful
/// `whoAmI` call, including the live status subscription's updates).
class DeviceIdentityService {
  DeviceIdentityService._();

  static final DeviceIdentityService instance = DeviceIdentityService._();

  static const _installIdKey = 'device_install_id';
  static const _recoveryHashKey = 'device_settings_recovery_hash';

  String? _installId;
  String? _token;
  DeviceIdentity? _identity;
  String? _recoveryCodeHash;
  RestaurantReceiptConfig? _receiptConfig;
  String? _orgNr;
  String? _registerAddress;
  String? _manRegisterId;
  String? _registerDesignation;
  DeviceCurrency? _currency;
  String? _cachedLogoUrl;
  Uint8List? _logoBytes;
  String? _kioskVideoUrl;
  String? _cachedKioskHeaderLogoUrl;
  Uint8List? _kioskHeaderLogoBytes;
  SubscriptionHandle? _statusSubscription;
  final ValueNotifier<bool> isPairedNotifier = ValueNotifier<bool>(false);

  /// Ticks up by one on every `whoAmI` update (initial pairing and every live push after) -
  /// listen to this (e.g. `ValueListenableBuilder<int>`) to rebuild a widget whenever remote
  /// config it reads directly here (like [kioskVideoUrl]/[kioskHeaderLogoUrl]) changes, since
  /// those are plain getters with no per-field notifier of their own. [ThemeController] and
  /// [logoBytes]'s consumers don't need this - they already have their own reactive path
  /// (respectively `ChangeNotifier` and a fresh read at print time) - this is specifically for
  /// values a long-lived widget (like the kiosk's idle screen) reads once at build time and
  /// otherwise would never see change without a full app restart.
  final ValueNotifier<int> remoteConfigVersion = ValueNotifier<int>(0);

  String? get token => _token;
  DeviceIdentity? get identity => _identity;
  bool get isPaired => _identity != null;

  /// This app-generated (not server-issued) install id, stable across restarts and re-pairing -
  /// unlike [token], which rotates every session. Used only as a stable cache key for
  /// `MenuRepository`'s disk cache (a fast-first-paint convenience while online, never a source
  /// of truth for placing orders — see that class's doc comment). Null only before [bootstrap]
  /// has run once.
  String? get installId => _installId;

  /// This restaurant's printed-receipt customization (logo/header/footer),
  /// kept current by the same live `whoAmI` subscription that watches for
  /// revocation — see `printer_service.dart`'s `printReceipt`.
  RestaurantReceiptConfig? get receiptConfig => _receiptConfig;

  /// SKVFS 2014:9 Ch.7 §1 fiscal receipt fields — kept current by the same
  /// live `whoAmI` subscription as [receiptConfig], so a correction made on
  /// the admin dashboard (e.g. a fixed register address) reaches every
  /// paired device without a restart. Null until the restaurant's fiscal
  /// identity (orgNr/registerAddress/currency) or this specific device's
  /// manRegisterId/registerDesignation have been configured — callers
  /// should fall back to a placeholder in that case (see
  /// `printer_service.dart`'s `printReceipt`), never to a hardcoded org's
  /// real value.
  String? get orgNr => _orgNr;
  String? get registerAddress => _registerAddress;
  String? get manRegisterId => _manRegisterId;
  String? get registerDesignation => _registerDesignation;
  DeviceCurrency? get currency => _currency;

  /// The logo's raw image bytes, fetched once per distinct `logoUrl` and
  /// cached here so a print doesn't do a network round-trip — the Sunmi
  /// printer API takes raw encoded (PNG/JPEG) bytes directly, no decoding
  /// needed on our side (see `printer_service.dart`).
  Uint8List? get logoBytes => _logoBytes;

  /// Looping background video for the kiosk's idle/start screen (see
  /// `kiosk_background_video.dart`). This is the raw remote URL - `KioskBackgroundVideo` itself
  /// resolves it through [RemoteAssetCache] to a local file before ever playing it, so it's only
  /// actually downloaded from the server once (per distinct URL), not on every app restart. Null
  /// until a manager sets one on the admin dashboard, in which case the kiosk falls back to its
  /// bundled local asset.
  String? get kioskVideoUrl => _kioskVideoUrl;

  /// The kiosk ordering screen's own top-bar logo (see `_KioskBrandHeader` in
  /// kiosk_menu_screen.dart) - deliberately separate from [logoBytes] (the receipt logo), since
  /// a restaurant may want a different mark on-screen than what prints on paper. Same
  /// disk-cached-bytes treatment as [logoBytes] (see [RemoteAssetCache]) so it doesn't refetch
  /// from the server on every app restart either.
  Uint8List? get kioskHeaderLogoBytes => _kioskHeaderLogoBytes;

  Future<String> _resolveInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    var installId = prefs.getString(_installIdKey);
    if (installId == null) {
      installId = const Uuid().v4();
      await prefs.setString(_installIdKey, installId);
    }
    _installId = installId;
    return installId;
  }

  Future<void> _cacheRecoveryHash(String? hash) async {
    _recoveryCodeHash = hash;
    final prefs = await SharedPreferences.getInstance();
    if (hash == null) {
      await prefs.remove(_recoveryHashKey);
    } else {
      await prefs.setString(_recoveryHashKey, hash);
    }
  }

  Future<void> _finishPairing(String token) async {
    final info = await DeviceRepository.instance.whoAmI(token);
    _token = token;
    _identity = DeviceIdentity(
      restaurantId: info.restaurantId,
      restaurantSlug: info.restaurantSlug,
      restaurantName: info.restaurantName,
      deviceType: info.deviceType,
    );
    isPairedNotifier.value = true;
    _applyWhoAmI(info);
    _watchStatus(token);
    // TCS-D's mandatory boot heartbeat (Infrasec certification test case 1)
    // — only meaningful for a fiscalizing "pos" device (agentRegisterStatus
    // is server-gated to deviceType "pos" anyway; kiosk/handheld/display/kds
    // tokens would just get rejected). Fire-and-forget: this confirms the
    // register is correctly bound on the TCS, but a transient failure here
    // must never block the app from opening — see registerStatus's own doc
    // comment.
    if (info.deviceType == 'pos') {
      unawaited(_reportRegisterStatus(token));
    }
  }

  Future<void> _reportRegisterStatus(String token) async {
    try {
      final result = await PosPaymentsService.instance.registerStatus(
        deviceToken: token,
      );
      if (!result.success) {
        debugPrint(
          'TCS RegisterStatus not OK: ${result.responseCode}/${result.skvResponseCode} ${result.responseMessage ?? ''}',
        );
      }
    } catch (e) {
      debugPrint('TCS RegisterStatus call failed: $e');
    }
  }

  Future<void> _watchStatus(String token) async {
    _statusSubscription?.cancel();
    _statusSubscription = await DeviceRepository.instance.subscribeToStatus(
      deviceToken: token,
      onUpdate: _applyWhoAmI,
      onError: (message, details) => _handleRevoked(),
    );
  }

  /// Applies everything a `whoAmI` response carries besides identity
  /// itself — the recovery-code hash cache and the restaurant's
  /// appearance/receipt config — called from both the initial pairing
  /// fetch and every live update after, so all three stay current for the
  /// whole session without three separate subscriptions.
  void _applyWhoAmI(DeviceWhoAmI info) {
    _cacheRecoveryHash(info.settingsRecoveryCodeHash);
    _receiptConfig = info.receipt;
    _orgNr = info.orgNr;
    _registerAddress = info.registerAddress;
    _manRegisterId = info.manRegisterId;
    _registerDesignation = info.registerDesignation;
    _currency = info.currency;
    _refreshLogoBytes(info.receipt?.logoUrl);
    _kioskVideoUrl = info.kioskVideoUrl;
    _refreshKioskHeaderLogoBytes(info.kioskHeaderLogoUrl);
    ThemeController.instance.applyRemote(info.appearance);
    remoteConfigVersion.value++;
  }

  Future<void> _refreshLogoBytes(String? logoUrl) async {
    if (logoUrl == _cachedLogoUrl) return;
    _cachedLogoUrl = logoUrl;
    final bytes = await _fetchCachedBytes(logoUrl);
    // Two `whoAmI` updates in quick succession, with the later fetch finishing first, must not
    // let the earlier (now-stale) one overwrite it once its own await resolves - only apply
    // this result if `logoUrl` is still the current target.
    if (_cachedLogoUrl != logoUrl) return;
    _logoBytes = bytes;
    remoteConfigVersion.value++;
  }

  Future<void> _refreshKioskHeaderLogoBytes(String? logoUrl) async {
    if (logoUrl == _cachedKioskHeaderLogoUrl) return;
    _cachedKioskHeaderLogoUrl = logoUrl;
    final bytes = await _fetchCachedBytes(logoUrl);
    if (_cachedKioskHeaderLogoUrl != logoUrl) return;
    _kioskHeaderLogoBytes = bytes;
    remoteConfigVersion.value++;
  }

  /// Shared by [_refreshLogoBytes]/[_refreshKioskHeaderLogoBytes] - routes through
  /// [RemoteAssetCache] (disk-persisted, keyed by URL) rather than fetching over the network
  /// every time, so a restaurant's logo isn't re-downloaded from the server on every app
  /// restart. Falls back to a plain direct fetch (the old behavior, no disk caching) if the
  /// disk cache itself fails for any reason - a broken cache should never mean a broken image.
  Future<Uint8List?> _fetchCachedBytes(String? url) async {
    if (url == null) return null;
    try {
      final file = await RemoteAssetCache.instance.file(url);
      return await file.readAsBytes();
    } catch (_) {
      try {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          return await consolidateHttpClientResponseBytes(response);
        } finally {
          client.close();
        }
      } catch (_) {
        return null;
      }
    }
  }

  void _handleRevoked() {
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _token = null;
    _identity = null;
    isPairedNotifier.value = false;
  }

  /// Call once at startup. Resolves immediately (no UI shown) if this
  /// hardware is already an active, recognized device. Otherwise returns a
  /// [PairingChallenge] for `app.dart`/`PairingScreen` to display and pass
  /// to [waitForClaim].
  ///
  /// Deliberately no offline fallback of any kind, for any device type — including kiosk. A
  /// device with no working network connection to Convex must not be able to reach a
  /// browsable/orderable state: with payments involved, "looks paired but is actually running on
  /// stale, unverifiable state" is a worse failure mode than just blocking on [PairingScreen]'s
  /// own "could not reach the server — retrying…" state until the network comes back.
  Future<PairingChallenge?> bootstrap() async {
    final installId = await _resolveInstallId();
    final deviceInfo = await collectDeviceInfo();
    final outcome = await DeviceRepository.instance.startPairing(
      installId: installId,
      deviceType: appMode,
      deviceInfo: deviceInfo,
    );
    if (outcome.isActive) {
      await _finishPairing(outcome.token!);
      return null;
    }
    return PairingChallenge(
      requestId: outcome.requestId!,
      code: outcome.code!,
      pollToken: outcome.pollToken!,
      expiresAt: outcome.expiresAt!,
    );
  }

  /// Polls `devices:pollPairingRequest` every few seconds until staff
  /// claims [challenge]'s code — resolves once paired. Throws
  /// [PairingExpiredException] if the code expires unclaimed; the caller
  /// (PairingScreen) should call [bootstrap] again to get a fresh one.
  Future<void> waitForClaim(PairingChallenge challenge) async {
    while (true) {
      await Future.delayed(const Duration(seconds: 3));
      final result = await DeviceRepository.instance.pollPairingRequest(
        requestId: challenge.requestId,
        pollToken: challenge.pollToken,
      );
      switch (result.status) {
        case PairingPollStatus.pending:
          continue;
        case PairingPollStatus.claimed:
          await _finishPairing(result.token!);
          return;
        case PairingPollStatus.expired:
          throw const PairingExpiredException();
      }
    }
  }

  /// Online settings-unlock path: redeems a short-lived, single-use code
  /// staff generated on the admin dashboard for this specific device.
  /// Throws if the code is wrong, expired, already used, or was
  /// generated for a different device.
  Future<void> redeemSettingsUnlockCode(String code) async {
    final token = _token;
    if (token == null) throw StateError('Device is not paired');
    await DeviceRepository.instance.redeemSettingsUnlockCode(
      deviceToken: token,
      code: code,
    );
  }

  /// Offline settings-unlock path: hashes [code] locally and compares it
  /// to the last-cached `settingsRecoveryCodeHash` — the actual comparison
  /// is zero network calls, works with no connectivity at all. Before
  /// that, makes one best-effort attempt to refresh the cache via a
  /// one-shot `whoAmI` — covers the case where the device is actually
  /// online but the live subscription just hasn't delivered a change yet
  /// (e.g. right after app resume); a short timeout means this adds
  /// negligible delay when genuinely offline. Falls back to whatever's in
  /// `shared_preferences` if nothing's cached in memory. Returns false
  /// (not an error) if no recovery code has ever synced to this device.
  Future<bool> verifyRecoveryCodeOffline(String code) async {
    final token = _token;
    if (token != null) {
      try {
        final info = await DeviceRepository.instance
            .whoAmI(token)
            .timeout(const Duration(seconds: 3));
        _applyWhoAmI(info);
      } catch (_) {
        // Genuinely offline (or the request just timed out) — fall
        // through to whatever's already cached below.
      }
    }

    var hash = _recoveryCodeHash;
    if (hash == null) {
      final prefs = await SharedPreferences.getInstance();
      hash = prefs.getString(_recoveryHashKey);
    }
    if (hash == null) return false;
    final candidateHash = sha256
        .convert(utf8.encode(_normalizeRecoveryCode(code)))
        .toString();
    return candidateHash == hash;
  }

  /// Must stay byte-for-byte in sync with the backend's
  /// `normalizeRecoveryCode` in devices.ts — strips display-only
  /// dashes/whitespace and uppercases, so "ab3d 9kxp2lmn" and
  /// "AB3D-9KXP-2LMN" hash identically regardless of exactly how staff
  /// wrote it down or how it's retyped here.
  String _normalizeRecoveryCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
}

class PairingExpiredException implements Exception {
  const PairingExpiredException();
}

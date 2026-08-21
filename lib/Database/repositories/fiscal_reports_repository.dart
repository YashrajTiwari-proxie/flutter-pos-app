import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import '../../Feactures/POS/Settings/FiscalReports/fiscal_report_models.dart';
import '../device_identity_service.dart';

/// Device-facing calls for X-day/Z-day fiscal reports — mirrors
/// `convex/fiscalReports.ts`. The X-report is always a live subscription
/// (it's a running total by definition); the Z-report is a formal,
/// numbered, immutable close-of-day event, so it's read via a one-shot
/// query (the latest already-generated one) and only advances via the
/// explicit [generateZReport] mutation, never recomputed silently.
class FiscalReportsRepository {
  FiscalReportsRepository._();

  static final FiscalReportsRepository instance = FiscalReportsRepository._();

  // Applied to generateZReport (never to the subscriptions below, which are long-lived by
  // design) - without this, a Convex call that never responds would leave the "Generate
  // Z-report" button stuck mid-tap indefinitely. See order_repository.dart's identical
  // constant/reasoning.
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

  Future<SubscriptionHandle> subscribeToXReport({
    required void Function(FiscalReport report) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) {
    return ConvexClient.instance.subscribe(
      name: 'fiscalReports:xReportForDevice',
      args: {'deviceToken': _deviceToken},
      onUpdate: (raw) => onUpdate(
        FiscalReport.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
          kind: FiscalReportKind.x,
        ),
      ),
      onError: onError,
    );
  }

  /// Null means no Z-report has ever been generated for this restaurant yet.
  Future<SubscriptionHandle> subscribeToLatestZReport({
    required void Function(FiscalReport? report) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) {
    return ConvexClient.instance.subscribe(
      name: 'fiscalReports:latestZReportForDevice',
      args: {'deviceToken': _deviceToken},
      onUpdate: (raw) {
        final decoded = jsonDecode(raw);
        onUpdate(
          decoded == null
              ? null
              : FiscalReport.fromJson(
                  decoded as Map<String, dynamic>,
                  kind: FiscalReportKind.z,
                ),
        );
      },
      onError: onError,
    );
  }

  /// Closes out the current period (since the last Z-report, or ever, if
  /// none) as a new, formally numbered Z-report. Deliberately not something
  /// the UI calls automatically — this is a staff-initiated day-close action.
  Future<FiscalReport> generateZReport() async {
    final raw = await ConvexClient.instance
        .mutation(
          name: 'fiscalReports:generateZReportForDevice',
          args: {'deviceToken': _deviceToken},
        )
        .timeout(_timeout);
    return FiscalReport.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      kind: FiscalReportKind.z,
    );
  }
}

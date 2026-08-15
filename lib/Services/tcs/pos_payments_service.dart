// Client for the backend's single centralized fiscal orchestration
// function (convex/posPayments.ts). Flutter never calls a raw TCS-D agent
// action (agentSale/agentRefund/etc.) directly — it only ever reports a
// raw hardware outcome (a SoftPay charge/refund result) to this one
// endpoint; VAT math, the TCS-D call, and every table write happen
// entirely server-side (durability: a device going offline right after
// this call can never lose or duplicate a fiscal record, since the
// payment attempt is recorded before any TCS call is even attempted).

import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import 'tcs_models.dart';

/// Result of `posPayments:reportEvent`.
class PosPaymentReportResult {
  const PosPaymentReportResult({
    required this.eventId,
    required this.fiscal,
    required this.requiresRefund,
  });

  factory PosPaymentReportResult.fromJson(Map<String, dynamic> json) =>
      PosPaymentReportResult(
        eventId: json['eventId'] as String,
        fiscal: json['fiscal'] == null
            ? null
            : TcsResult.fromJson(json['fiscal'] as Map<String, dynamic>),
        requiresRefund: json['requiresRefund'] as bool? ?? false,
      );

  final String eventId;

  /// Null for outcomes that never fiscalize on their own (failure,
  /// cancellation, unconfirmed) — only "charge" and "refund" produce one.
  final TcsResult? fiscal;

  /// True only when fiscalization was cleanly rejected by TCS for a
  /// successful charge — never set for "unconfirmed" (network/timeout),
  /// since that might have actually succeeded on Infrasec's side. When
  /// true, the device should immediately drive a SoftPay refund for this
  /// same charge and report it via [PosPaymentsService.reportEvent] with
  /// `type: 'refund'`.
  final bool requiresRefund;
}

class PosPaymentsService {
  PosPaymentsService._();

  static final PosPaymentsService instance = PosPaymentsService._();

  // Real-money/legal-record action — a hung call must never leave the
  // checkout screen stuck forever.
  static const _timeout = Duration(seconds: 20);

  /// Reports one payment-lifecycle event for an already-created order.
  /// [type] is one of `charge` / `refund` / `failure` / `cancellation` /
  /// `unconfirmed` — matching Softpay's own outcome vocabulary exactly (see
  /// `orders:recordPaymentResult`'s doc comment for what each means).
  Future<PosPaymentReportResult> reportEvent({
    required String deviceToken,
    required String orderId,
    String? idempotencyKey,
    required String type,
    int? amountCents,
    Map<String, dynamic>? transaction,
    String? failureCode,
    String? failureMessage,
    String? reason,
  }) async {
    final raw = await ConvexClient.instance
        .action(
          name: 'posPayments:reportEvent',
          args: {
            'deviceToken': deviceToken,
            'orderId': orderId,
            if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
            'type': type,
            if (amountCents != null) 'amountCents': amountCents,
            if (transaction != null) 'transaction': transaction,
            if (failureCode != null) 'failureCode': failureCode,
            if (failureMessage != null) 'failureMessage': failureMessage,
            if (reason != null) 'reason': reason,
          },
        )
        .timeout(_timeout);
    return PosPaymentReportResult.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  /// Requests a real, fiscalized "Kopia" copy of an order's original sale
  /// (`receipts:requestCopy`) — a genuine new TCS-D call referencing the
  /// original sale's own sequence number/dateTime, not just a local
  /// reprint. `code` on the result is always null (kopia never carries a
  /// control code); print with `ReceiptKind.copy`. No idempotency/outbox
  /// durability here — unlike a charge, a failed copy request risks
  /// nothing (no money moved), so the caller can just let staff tap
  /// reprint again.
  Future<TcsResult> requestCopy({
    required String deviceToken,
    required String orderId,
  }) async {
    final raw = await ConvexClient.instance
        .action(
          name: 'receipts:requestCopy',
          args: {'deviceToken': deviceToken, 'orderId': orderId},
        )
        .timeout(_timeout);
    return TcsResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

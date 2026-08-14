import 'dart:async';

import 'package:flutter/services.dart';

import 'softpay_models.dart';

/// Talks to the native SoftPay AppSwitch integration (see
/// `android/app/src/main/kotlin/.../softpay/SoftPayPlugin.kt`) over a MethodChannel/EventChannel pair.
class SoftPayService {
  SoftPayService._();

  static final SoftPayService instance = SoftPayService._();

  static const _methodChannel = MethodChannel(
    'com.proxiestudio.kds_pos/softpay',
  );
  static const _eventChannel = EventChannel(
    'com.proxiestudio.kds_pos/softpay/status',
  );

  // A genuinely hung native call (the Softpay app crashes mid-transaction, the app-switch never
  // returns, an ANR) would otherwise leave `await`ing Dart code - and the whole payment screen -
  // stuck forever, with even the Cancel button routed through this same channel and thus
  // equally stuck. This is a safety-net watchdog, not a UX timeout: generous enough that a real
  // customer taking their time to tap/insert a card is never affected (the SDK has its own,
  // shorter internal timeouts for that), but bounded so a truly dead native side always still
  // unblocks the UI onto a terminal ("unconfirmed", not "declined" - see the callers) state.
  static const _transactionTimeout = Duration(minutes: 3);
  static const _quickCallTimeout = Duration(seconds: 15);

  Stream<PaymentStatusUpdate>? _statusUpdates;

  Stream<PaymentStatusUpdate> get statusUpdates {
    return _statusUpdates ??= _eventChannel.receiveBroadcastStream().map((
      event,
    ) {
      final map = Map<Object?, Object?>.from(event as Map);
      final stage = PaymentStage.values.firstWhere(
        (value) => value.name == map['stage'],
        orElse: () => PaymentStage.processing,
      );
      return PaymentStatusUpdate(
        stage: stage,
        detail: map['detail'] as String?,
      );
    }).asBroadcastStream();
  }

  Future<Map<String, dynamic>> readiness() async {
    final result = await _methodChannel
        .invokeMapMethod<String, dynamic>('readiness')
        .timeout(_quickCallTimeout);
    return result ?? <String, dynamic>{};
  }

  Future<TransactionResult> charge({
    required int amountMinor,
    required String currency,
  }) async {
    try {
      final result = await _methodChannel
          .invokeMapMethod<Object?, Object?>('charge', {
            'amountMinor': amountMinor,
            'currency': currency,
          })
          .timeout(_transactionTimeout);
      return TransactionResult.fromMap(result!);
    } on PlatformException catch (e) {
      final details = e.details;
      final detailedCode = details is Map
          ? (details['detailedCode'] as num?)?.toInt()
          : null;
      throw SoftPayException(
        code: e.code,
        message: e.message ?? 'Unknown SoftPay error',
        detailedCode: detailedCode,
      );
    } on TimeoutException {
      throw const SoftPayException(
        code: 'CLIENT_TIMEOUT',
        message: 'The payment terminal did not respond in time',
      );
    }
  }

  /// Processes a refund as its own card-present transaction (the connected Softpay app will
  /// always require a card tap; there is no "linked by request id" refund). [posReferenceNumber]
  /// is passed through only so the refund can be reconciled against the original order.
  Future<TransactionResult> refund({
    required int amountMinor,
    required String currency,
    String? posReferenceNumber,
  }) async {
    try {
      final result = await _methodChannel
          .invokeMapMethod<Object?, Object?>('refund', {
            'amountMinor': amountMinor,
            'currency': currency,
            'posReferenceNumber': posReferenceNumber,
          })
          .timeout(_transactionTimeout);
      return TransactionResult.fromMap(result!);
    } on PlatformException catch (e) {
      final details = e.details;
      final detailedCode = details is Map
          ? (details['detailedCode'] as num?)?.toInt()
          : null;
      throw SoftPayException(
        code: e.code,
        message: e.message ?? 'Unknown SoftPay error',
        detailedCode: detailedCode,
      );
    } on TimeoutException {
      throw const SoftPayException(
        code: 'CLIENT_TIMEOUT',
        message: 'The payment terminal did not respond in time',
      );
    }
  }

  /// Cancels whichever operation (charge or refund) is currently in flight. Deliberately a short
  /// timeout, not the transaction one - this is meant to be a near-instant signal, and if the
  /// native side is unresponsive enough that even this hangs, the in-flight charge/refund call's
  /// own timeout above is what actually unblocks the screen, not this call.
  Future<void> cancelCharge() async {
    try {
      await _methodChannel
          .invokeMethod<void>('cancelCharge')
          .timeout(_quickCallTimeout);
    } on TimeoutException {
      // Best-effort - nothing further to do here; see doc comment above.
    }
  }
}

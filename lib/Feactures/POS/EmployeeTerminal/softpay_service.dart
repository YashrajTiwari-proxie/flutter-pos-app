import 'package:flutter/services.dart';

import 'softpay_models.dart';

/// Talks to the native SoftPay AppSwitch integration (see
/// `android/app/src/main/kotlin/.../softpay/SoftPayPlugin.kt`) over a MethodChannel/EventChannel pair.
class SoftPayService {
  SoftPayService._();

  static final SoftPayService instance = SoftPayService._();

  static const _methodChannel = MethodChannel('com.proxiestudio.kds_pos/softpay');
  static const _eventChannel = EventChannel('com.proxiestudio.kds_pos/softpay/status');

  Stream<PaymentStatusUpdate>? _statusUpdates;

  Stream<PaymentStatusUpdate> get statusUpdates {
    return _statusUpdates ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<Object?, Object?>.from(event as Map);
      final stage = PaymentStage.values.firstWhere(
        (value) => value.name == map['stage'],
        orElse: () => PaymentStage.processing,
      );
      return PaymentStatusUpdate(stage: stage, detail: map['detail'] as String?);
    }).asBroadcastStream();
  }

  Future<Map<String, dynamic>> readiness() async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('readiness');
    return result ?? <String, dynamic>{};
  }

  Future<TransactionResult> charge({required int amountMinor, required String currency}) async {
    try {
      final result = await _methodChannel.invokeMapMethod<Object?, Object?>('charge', {
        'amountMinor': amountMinor,
        'currency': currency,
      });
      return TransactionResult.fromMap(result!);
    } on PlatformException catch (e) {
      final details = e.details;
      final detailedCode = details is Map ? (details['detailedCode'] as num?)?.toInt() : null;
      throw SoftPayException(
        code: e.code,
        message: e.message ?? 'Unknown SoftPay error',
        detailedCode: detailedCode,
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
      final result = await _methodChannel.invokeMapMethod<Object?, Object?>('refund', {
        'amountMinor': amountMinor,
        'currency': currency,
        'posReferenceNumber': posReferenceNumber,
      });
      return TransactionResult.fromMap(result!);
    } on PlatformException catch (e) {
      final details = e.details;
      final detailedCode = details is Map ? (details['detailedCode'] as num?)?.toInt() : null;
      throw SoftPayException(
        code: e.code,
        message: e.message ?? 'Unknown SoftPay error',
        detailedCode: detailedCode,
      );
    }
  }

  /// Cancels whichever operation (charge or refund) is currently in flight.
  Future<void> cancelCharge() async {
    await _methodChannel.invokeMethod<void>('cancelCharge');
  }
}

import 'transaction_snapshot.dart';

/// Mirrors the backend's `orderPaymentEvents.type` union (schema.ts) — a
/// structured event log rather than fields on `Order` itself, since one
/// order can be refunded more than once.
enum OrderPaymentEventType { charge, refund, failure, cancellation }

OrderPaymentEventType _typeFromJson(String value) {
  switch (value) {
    case 'charge':
      return OrderPaymentEventType.charge;
    case 'refund':
      return OrderPaymentEventType.refund;
    case 'failure':
      return OrderPaymentEventType.failure;
    case 'cancellation':
      return OrderPaymentEventType.cancellation;
    default:
      throw ArgumentError('Unknown order payment event type: $value');
  }
}

class OrderPaymentEvent {
  const OrderPaymentEvent({
    required this.id,
    required this.orderId,
    required this.type,
    this.amountCents,
    this.transaction,
    this.failureCode,
    this.failureMessage,
    this.reason,
    required this.createdAt,
  });

  factory OrderPaymentEvent.fromJson(Map<String, dynamic> json) {
    return OrderPaymentEvent(
      id: json['_id'] as String,
      orderId: json['orderId'] as String,
      type: _typeFromJson(json['type'] as String),
      amountCents: (json['amountCents'] as num?)?.toInt(),
      transaction: json['transaction'] != null
          ? TransactionSnapshot.fromJson(json['transaction'] as Map<String, dynamic>)
          : null,
      failureCode: json['failureCode'] as String?,
      failureMessage: json['failureMessage'] as String?,
      reason: json['reason'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt()),
    );
  }

  final String id;
  final String orderId;
  final OrderPaymentEventType type;
  final int? amountCents;
  final TransactionSnapshot? transaction;
  final String? failureCode;
  final String? failureMessage;
  final String? reason;
  final DateTime createdAt;
}

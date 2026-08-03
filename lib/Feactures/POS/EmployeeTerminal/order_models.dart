enum OrderStatus { processing, paid, failed, cancelled, refunded, partiallyRefunded }

OrderStatus _orderStatusFromJson(String value) {
  switch (value) {
    case 'processing':
      return OrderStatus.processing;
    case 'paid':
      return OrderStatus.paid;
    case 'failed':
      return OrderStatus.failed;
    case 'cancelled':
      return OrderStatus.cancelled;
    case 'refunded':
      return OrderStatus.refunded;
    case 'partially_refunded':
      return OrderStatus.partiallyRefunded;
    default:
      throw ArgumentError('Unknown order status: $value');
  }
}

class OrderItem {
  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.priceMinor,
    required this.quantity,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      menuItemId: json['menuItemId'] as String,
      name: json['name'] as String,
      priceMinor: (json['priceMinor'] as num).toInt(),
      quantity: (json['quantity'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'menuItemId': menuItemId,
    'name': name,
    'priceMinor': priceMinor,
    'quantity': quantity,
  };

  final String menuItemId;
  final String name;
  final int priceMinor;
  final int quantity;

  int get subtotalMinor => priceMinor * quantity;
}

/// A snapshot of a Softpay `Transaction` result, stored as-is for both a charge and a refund.
class TransactionSnapshot {
  const TransactionSnapshot({
    this.requestId,
    this.state,
    this.type,
    this.cardScheme,
    this.partialPan,
    this.auditNumber,
    this.cvm,
    this.terminalId,
    this.batchNumber,
    this.tipMinor,
    this.surchargeMinor,
    this.transactionDate,
  });

  factory TransactionSnapshot.fromJson(Map<String, dynamic> json) {
    return TransactionSnapshot(
      requestId: json['requestId'] as String?,
      state: json['state'] as String?,
      type: json['type'] as String?,
      cardScheme: json['cardScheme'] as String?,
      partialPan: json['partialPan'] as String?,
      auditNumber: json['auditNumber'] as String?,
      cvm: json['cvm'] as String?,
      terminalId: json['terminalId'] as String?,
      batchNumber: json['batchNumber'] as String?,
      tipMinor: (json['tipMinor'] as num?)?.toInt(),
      surchargeMinor: (json['surchargeMinor'] as num?)?.toInt(),
      transactionDate: (json['transactionDate'] as num?)?.toInt(),
    );
  }

  final String? requestId;
  final String? state;
  final String? type;
  final String? cardScheme;
  final String? partialPan;
  final String? auditNumber;
  final String? cvm;
  final String? terminalId;
  final String? batchNumber;
  final int? tipMinor;
  final int? surchargeMinor;
  final int? transactionDate;
}

class OrderFailure {
  const OrderFailure({required this.code, required this.message, this.detailedCode, required this.occurredAt});

  factory OrderFailure.fromJson(Map<String, dynamic> json) {
    return OrderFailure(
      code: json['code'] as String,
      message: json['message'] as String,
      detailedCode: (json['detailedCode'] as num?)?.toInt(),
      occurredAt: DateTime.fromMillisecondsSinceEpoch((json['occurredAt'] as num).toInt()),
    );
  }

  final String code;
  final String message;
  final int? detailedCode;
  final DateTime occurredAt;
}

class OrderRefund {
  const OrderRefund({
    required this.amountMinor,
    this.reason,
    this.transaction,
    required this.refundedAt,
  });

  factory OrderRefund.fromJson(Map<String, dynamic> json) {
    return OrderRefund(
      amountMinor: (json['amountMinor'] as num).toInt(),
      reason: json['reason'] as String?,
      transaction: json['transaction'] != null
          ? TransactionSnapshot.fromJson(json['transaction'] as Map<String, dynamic>)
          : null,
      refundedAt: DateTime.fromMillisecondsSinceEpoch((json['refundedAt'] as num).toInt()),
    );
  }

  final int amountMinor;
  final String? reason;
  final TransactionSnapshot? transaction;
  final DateTime refundedAt;
}

class Order {
  const Order({
    required this.id,
    required this.status,
    required this.currency,
    required this.totalMinor,
    required this.items,
    this.payment,
    this.failure,
    this.refund,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['_id'] as String,
      status: _orderStatusFromJson(json['status'] as String),
      currency: json['currency'] as String,
      totalMinor: (json['totalMinor'] as num).toInt(),
      items: (json['items'] as List<dynamic>)
          .map((entry) => OrderItem.fromJson(entry as Map<String, dynamic>))
          .toList(),
      payment: json['payment'] != null
          ? TransactionSnapshot.fromJson(json['payment'] as Map<String, dynamic>)
          : null,
      failure: json['failure'] != null ? OrderFailure.fromJson(json['failure'] as Map<String, dynamic>) : null,
      refund: json['refund'] != null ? OrderRefund.fromJson(json['refund'] as Map<String, dynamic>) : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt()),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((json['updatedAt'] as num).toInt()),
    );
  }

  final String id;
  final OrderStatus status;
  final String currency;
  final int totalMinor;
  final List<OrderItem> items;
  final TransactionSnapshot? payment;
  final OrderFailure? failure;
  final OrderRefund? refund;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Amount still eligible to be refunded, in minor units.
  int get refundableMinor => totalMinor - (refund?.amountMinor ?? 0);

  bool get canRefund => status == OrderStatus.paid || status == OrderStatus.partiallyRefunded;
}

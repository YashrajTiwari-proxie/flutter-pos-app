enum PaymentStage { connecting, processing, approved, declined, cancelled }

class PaymentStatusUpdate {
  const PaymentStatusUpdate({required this.stage, this.detail});

  final PaymentStage stage;
  final String? detail;
}

class SoftPayException implements Exception {
  const SoftPayException({required this.code, required this.message, this.detailedCode});

  final String code;
  final String message;
  final int? detailedCode;

  @override
  String toString() => 'SoftPayException($code): $message';
}

class TransactionResult {
  const TransactionResult({
    required this.amountMinor,
    required this.currency,
    required this.state,
    this.requestId,
    this.cardScheme,
    this.partialPan,
    this.auditNumber,
    this.type,
    this.cvm,
    this.terminalId,
    this.batchNumber,
    this.tipMinor,
    this.surchargeMinor,
    this.transactionDate,
  });

  factory TransactionResult.fromMap(Map<dynamic, dynamic> map) {
    return TransactionResult(
      requestId: map['requestId'] as String?,
      amountMinor: (map['amountMinor'] as num).toInt(),
      currency: map['currency'] as String,
      state: map['state'] as String,
      cardScheme: map['cardScheme'] as String?,
      partialPan: map['partialPan'] as String?,
      auditNumber: map['auditNumber'] as String?,
      type: map['type'] as String?,
      cvm: map['cvm'] as String?,
      terminalId: map['terminalId'] as String?,
      batchNumber: map['batchNumber'] as String?,
      tipMinor: (map['tipMinor'] as num?)?.toInt(),
      surchargeMinor: (map['surchargeMinor'] as num?)?.toInt(),
      transactionDate: (map['transactionDate'] as num?)?.toInt(),
    );
  }

  final String? requestId;
  final int amountMinor;
  final String currency;
  final String state;
  final String? cardScheme;
  final String? partialPan;
  final String? auditNumber;
  final String? type;
  final String? cvm;
  final String? terminalId;
  final String? batchNumber;
  final int? tipMinor;
  final int? surchargeMinor;
  final int? transactionDate;
}

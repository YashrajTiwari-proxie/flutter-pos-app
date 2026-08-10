/// A snapshot of a Softpay `Transaction` result — the same shape stored on
/// the backend's `orderPaymentEvents.transaction` field (schema.ts),
/// carried as-is for a charge, a refund, or a failed-attempt record.
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

  /// Convex's `v.optional(...)` only accepts a missing key, not an explicit
  /// `null` — null-valued entries are dropped rather than passed through.
  Map<String, dynamic> toJson() => {
    if (requestId != null) 'requestId': requestId,
    if (state != null) 'state': state,
    if (type != null) 'type': type,
    if (cardScheme != null) 'cardScheme': cardScheme,
    if (partialPan != null) 'partialPan': partialPan,
    if (auditNumber != null) 'auditNumber': auditNumber,
    if (cvm != null) 'cvm': cvm,
    if (terminalId != null) 'terminalId': terminalId,
    if (batchNumber != null) 'batchNumber': batchNumber,
    if (tipMinor != null) 'tipMinor': tipMinor,
    if (surchargeMinor != null) 'surchargeMinor': surchargeMinor,
    if (transactionDate != null) 'transactionDate': transactionDate,
  };

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

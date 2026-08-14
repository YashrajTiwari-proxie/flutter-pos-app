// Data shapes for the TCS-D fiscalization calls (Infrasec).
//
// Mirrors the backend's `ShapedTcsResult` / VAT band shape exactly (see
// convex/lib/tcsClient.ts and convex/lib/tcsXml.ts on the fiscal branch) —
// field names and types here must stay byte-for-byte compatible with what
// the Convex actions (agentSale, agentRefund, agentCopy, agentExercise,
// agentProfo, agentRegisterStatus) actually return/accept.

/// One VAT band in a ControlData request — percent/amount/subtotalAmount are
/// all Swedish decimal-comma strings (e.g. "25,00"), never dot-decimal.
class TcsVatBand {
  const TcsVatBand({
    required this.percent,
    required this.amount,
    required this.subtotalAmount,
  });

  final String percent;
  final String amount;
  final String subtotalAmount;

  Map<String, dynamic> toJson() => {
    'percent': percent,
    'amount': amount,
    'subtotalAmount': subtotalAmount,
  };
}

/// Normalized result of any of the 6 fiscal actions — mirrors
/// `ShapedTcsResult` in convex/lib/tcsClient.ts field-for-field.
class TcsResult {
  const TcsResult({
    required this.success,
    required this.httpStatus,
    required this.requestId,
    required this.responseCode,
    required this.responseMessage,
    required this.responseReason,
    required this.skvResponseCode,
    required this.skvResponseMessage,
    required this.controlServerId,
    required this.code,
    required this.sequenceNumber,
    required this.applicationId,
    required this.rawBody,
    required this.error,
  });

  /// true only when the backend saw HTTP 200 + ResponseCode "0" +
  /// SKVResponseCode "STATUS_OK" — all three, not just one.
  final bool success;
  final int? httpStatus;
  final String requestId;
  final String? responseCode;
  final String? responseMessage;
  final String? responseReason;
  final String? skvResponseCode;
  final String? skvResponseMessage;

  /// 17-char TCS Control Server ID — printed on the receipt.
  final String? controlServerId;

  /// 113-char control code for a sale/refund; null for kopia/ovning/profo
  /// (those return an empty code, mapped to null server-side already).
  final String? code;
  final String? sequenceNumber;
  final String? applicationId;

  /// Raw XML response body — kept for debugging, never shown to a customer.
  final String rawBody;

  /// Set only on a network/timeout failure (never on a clean HTTP response,
  /// even an error one — those come back as a normal ShapedTcsResult with
  /// success: false and a responseCode/responseReason instead).
  final String? error;

  factory TcsResult.fromJson(Map<String, dynamic> json) => TcsResult(
    success: json['success'] as bool? ?? false,
    httpStatus: (json['httpStatus'] as num?)?.toInt(),
    requestId: json['requestId'] as String? ?? '',
    responseCode: json['responseCode'] as String?,
    responseMessage: json['responseMessage'] as String?,
    responseReason: json['responseReason'] as String?,
    skvResponseCode: json['skvResponseCode'] as String?,
    skvResponseMessage: json['skvResponseMessage'] as String?,
    controlServerId: json['controlServerId'] as String?,
    code: json['code'] as String?,
    sequenceNumber: json['sequenceNumber'] as String?,
    applicationId: json['applicationId'] as String?,
    rawBody: json['rawBody'] as String? ?? '',
    error: json['error'] as String?,
  );
}

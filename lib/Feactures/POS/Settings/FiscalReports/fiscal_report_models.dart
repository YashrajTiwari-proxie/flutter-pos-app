// Data shapes for the X-day/Z-day report screen — field set matches
// SKVFS 2014:9 Ch.7 §2-3 exactly (both report kinds share the same fields;
// only the "X" vs "Z" label and Z's own sequential report number differ).
// Mirrors the backend's `fiscalReports:xReportForDevice`/
// `fiscalReports:latestZReportForDevice`/`fiscalReports:generateZReportForDevice`
// response shape (convex/lib/fiscalReportAggregation.ts) field-for-field.

enum FiscalReportKind { x, z }

class VatBreakdownEntry {
  const VatBreakdownEntry({required this.label, required this.netCents, required this.vatCents});

  final String label;
  final int netCents;
  final int vatCents;

  factory VatBreakdownEntry.fromJson(Map<String, dynamic> json) => VatBreakdownEntry(
    label: json['label'] as String,
    netCents: (json['netCents'] as num).toInt(),
    vatCents: (json['vatCents'] as num).toInt(),
  );
}

class PaymentMethodTotal {
  const PaymentMethodTotal({required this.method, required this.amountCents, required this.count});

  final String method;
  final int amountCents;
  final int count;

  factory PaymentMethodTotal.fromJson(Map<String, dynamic> json) => PaymentMethodTotal(
    method: json['method'] as String,
    amountCents: (json['amountCents'] as num).toInt(),
    count: (json['count'] as num).toInt(),
  );
}

class FiscalReport {
  const FiscalReport({
    required this.kind,
    required this.generatedAt,
    required this.companyName,
    required this.orgNumber,
    required this.registerDesignation,
    required this.reportNumber,
    required this.totalSalesCents,
    required this.vatBreakdown,
    required this.drawerOpenCount,
    required this.goodsSoldCount,
    required this.receiptCount,
    required this.receiptCopyCount,
    required this.receiptCopyAmountCents,
    required this.practiceCount,
    required this.practiceAmountCents,
    required this.paymentMethods,
    required this.returnCount,
    required this.returnAmountCents,
    required this.discountAmountCents,
    required this.uncompletedSaleCount,
    required this.uncompletedSaleAmountCents,
  });

  final FiscalReportKind kind;
  final DateTime generatedAt;
  final String companyName;
  final String orgNumber;

  /// The physical register's own designation (manufacturing number) — not
  /// the restaurant name, per Ch.7 §2's "cash register designation" field.
  /// Currently the fiscal register's manRegisterId (see the still-open
  /// per-device-vs-per-restaurant fiscalIdentity design question).
  final String registerDesignation;

  /// Only set for a Z-report (its own unbroken sequential number per
  /// Ch.7 §3) — null for an X-report, which has no such requirement.
  final int? reportNumber;

  final int totalSalesCents;
  final List<VatBreakdownEntry> vatBreakdown;
  final int drawerOpenCount;
  final int goodsSoldCount;
  final int receiptCount;
  final int receiptCopyCount;
  final int receiptCopyAmountCents;
  final int practiceCount;
  final int practiceAmountCents;
  final List<PaymentMethodTotal> paymentMethods;
  final int returnCount;
  final int returnAmountCents;
  final int discountAmountCents;
  final int uncompletedSaleCount;
  final int uncompletedSaleAmountCents;

  int get netTotalCents => totalSalesCents - returnAmountCents - discountAmountCents;

  /// [kind] is passed in rather than read from json — the same backend shape is used for both
  /// `xReportForDevice` (which sets `kind: "x"` itself) and `latestZReportForDevice`/
  /// `generateZReportForDevice` (stored `zReports` docs, which have no `kind` field at all since
  /// every stored report is implicitly a Z-report).
  factory FiscalReport.fromJson(Map<String, dynamic> json, {required FiscalReportKind kind}) => FiscalReport(
    kind: kind,
    generatedAt: DateTime.fromMillisecondsSinceEpoch((json['generatedAt'] as num).toInt()),
    companyName: json['companyName'] as String,
    orgNumber: json['orgNumber'] as String,
    registerDesignation: json['registerDesignation'] as String,
    reportNumber: (json['reportNumber'] as num?)?.toInt(),
    totalSalesCents: (json['totalSalesCents'] as num).toInt(),
    vatBreakdown: (json['vatBreakdown'] as List<dynamic>)
        .map((e) => VatBreakdownEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    drawerOpenCount: (json['drawerOpenCount'] as num).toInt(),
    goodsSoldCount: (json['goodsSoldCount'] as num).toInt(),
    receiptCount: (json['receiptCount'] as num).toInt(),
    receiptCopyCount: (json['receiptCopyCount'] as num).toInt(),
    receiptCopyAmountCents: (json['receiptCopyAmountCents'] as num).toInt(),
    practiceCount: (json['practiceCount'] as num).toInt(),
    practiceAmountCents: (json['practiceAmountCents'] as num).toInt(),
    paymentMethods: (json['paymentMethods'] as List<dynamic>)
        .map((e) => PaymentMethodTotal.fromJson(e as Map<String, dynamic>))
        .toList(),
    returnCount: (json['returnCount'] as num).toInt(),
    returnAmountCents: (json['returnAmountCents'] as num).toInt(),
    discountAmountCents: (json['discountAmountCents'] as num).toInt(),
    uncompletedSaleCount: (json['uncompletedSaleCount'] as num).toInt(),
    uncompletedSaleAmountCents: (json['uncompletedSaleAmountCents'] as num).toInt(),
  );
}

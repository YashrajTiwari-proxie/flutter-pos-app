// The staff-facing journal — a chronological view of every fiscal record
// (sale/copy/refund/practice/proforma) plus every sale attempt that never
// reached fiscalization at all, the software-visible counterpart of
// SKVFS's requirement that the register be able to show/export its
// transaction log to a tax inspector on demand. Mirrors the backend's
// `journal:journalForDevice` response shape (convex/journal.ts).

enum JournalEntryKind { sale, copy, refund, practice, proforma, failedSale }

JournalEntryKind _kindFromJson(String value) {
  switch (value) {
    case 'sale':
      return JournalEntryKind.sale;
    case 'copy':
      return JournalEntryKind.copy;
    case 'refund':
      return JournalEntryKind.refund;
    case 'practice':
      return JournalEntryKind.practice;
    case 'proforma':
      return JournalEntryKind.proforma;
    case 'failedSale':
      return JournalEntryKind.failedSale;
    default:
      throw ArgumentError('Unknown journal entry kind: $value');
  }
}

class JournalEntry {
  const JournalEntry({
    required this.timestamp,
    required this.kind,
    required this.orderReference,
    required this.amountCents,
    required this.sequenceNumber,
    required this.success,
    this.controlCode,
    this.controlServerId,
    this.failureReason,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
    timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num).toInt()),
    kind: _kindFromJson(json['kind'] as String),
    orderReference: json['orderReference'] as String,
    amountCents: (json['amountCents'] as num).toInt(),
    sequenceNumber: json['sequenceNumber'] as String,
    success: json['success'] as bool,
    controlCode: json['controlCode'] as String?,
    controlServerId: json['controlServerId'] as String?,
    failureReason: json['failureReason'] as String?,
  );

  final DateTime timestamp;
  final JournalEntryKind kind;
  final String orderReference;
  final int amountCents;
  final String sequenceNumber;
  final bool success;

  /// The 113-char control code — null for kopia/ovning/profo receipts and
  /// for any failed attempt.
  final String? controlCode;
  final String? controlServerId;
  final String? failureReason;
}

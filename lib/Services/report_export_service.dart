import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../Feactures/POS/Settings/FiscalReports/fiscal_report_models.dart';
import '../Feactures/POS/Settings/Journal/journal_entry.dart';

/// Writes X/Z fiscal reports and the journal to a file on the device's own
/// external storage — deliberately NOT `getApplicationCacheDirectory` (OS-
/// clearable, and semantically "temporary scratch space", the opposite of a
/// fiscal record staff may need to hand a tax inspector) or
/// `getApplicationDocumentsDirectory` (internal app storage, wiped on
/// uninstall and invisible outside the app). `getExternalStorageDirectory`
/// gives a real, persistent, app-scoped folder on the device's external
/// storage (visible via any file manager/USB/adb at
/// `Android/data/<package>/files/Reports`, no runtime storage permission
/// required on modern Android since it's app-scoped, not shared/public
/// storage) — "for now", per the initial ask, rather than the extra
/// MediaStore/SAF plumbing a true public-Downloads save would need.
class ReportExportService {
  ReportExportService._();

  static final ReportExportService instance = ReportExportService._();

  static const _currency = 'SEK';

  Future<Directory> _reportsDirectory() async {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Reports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _timestampToken(DateTime time) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${time.year}${pad(time.month)}${pad(time.day)}-${pad(time.hour)}${pad(time.minute)}${pad(time.second)}';
  }

  String _money(int cents) => '${(cents / 100).toStringAsFixed(2)} $_currency';

  /// Saves an X-report or Z-report as a plain-text file matching the same
  /// fields shown on-screen. Returns the saved file's absolute path.
  Future<String> saveFiscalReport(FiscalReport report) async {
    final dir = await _reportsDirectory();
    final kindLabel = report.kind == FiscalReportKind.x ? 'X-Report' : 'Z-Report';
    final suffix = report.reportNumber != null ? '_${report.reportNumber}' : '_${_timestampToken(report.generatedAt)}';
    final file = File('${dir.path}/$kindLabel$suffix.txt');

    final buffer = StringBuffer()
      ..writeln(report.kind == FiscalReportKind.x ? 'X-REPORT (running totals)' : 'Z-REPORT (day close)')
      ..writeln('Company: ${report.companyName}')
      ..writeln('Org. number: ${report.orgNumber}')
      ..writeln('Register designation: ${report.registerDesignation}');
    if (report.reportNumber != null) buffer.writeln('Report number: #${report.reportNumber}');
    buffer
      ..writeln('Generated: ${report.generatedAt}')
      ..writeln()
      ..writeln('-- Sales --')
      ..writeln('Total sales: ${_money(report.totalSalesCents)}')
      ..writeln('Net total (after returns/discounts): ${_money(report.netTotalCents)}')
      ..writeln('Goods/services sold: ${report.goodsSoldCount}')
      ..writeln('Receipts issued: ${report.receiptCount}')
      ..writeln()
      ..writeln('-- VAT breakdown --');
    for (final band in report.vatBreakdown) {
      buffer.writeln('VAT ${band.label} (net ${_money(band.netCents)}): ${_money(band.vatCents)}');
    }
    buffer
      ..writeln()
      ..writeln('-- Payment methods --');
    for (final pm in report.paymentMethods) {
      buffer.writeln('${pm.method} (${pm.count}): ${_money(pm.amountCents)}');
    }
    buffer
      ..writeln()
      ..writeln('-- Other activity --')
      ..writeln('Drawer openings: ${report.drawerOpenCount}')
      ..writeln('Receipt copies: ${report.receiptCopyCount} · ${_money(report.receiptCopyAmountCents)}')
      ..writeln('Practice-mode sales: ${report.practiceCount} · ${_money(report.practiceAmountCents)}')
      ..writeln('Returns: ${report.returnCount} · ${_money(report.returnAmountCents)}')
      ..writeln('Discounts: ${_money(report.discountAmountCents)}')
      ..writeln('Uncompleted sales: ${report.uncompletedSaleCount} · ${_money(report.uncompletedSaleAmountCents)}');

    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Saves the journal as a CSV file (tabular data suits the list-of-events
  /// shape better than free-form text). Returns the saved file's absolute
  /// path.
  Future<String> saveJournal(List<JournalEntry> entries) async {
    final dir = await _reportsDirectory();
    final file = File('${dir.path}/Journal_${_timestampToken(DateTime.now())}.csv');

    String csvField(String value) => '"${value.replaceAll('"', '""')}"';

    final buffer = StringBuffer()
      ..writeln(
        [
          'Timestamp',
          'Kind',
          'Order reference',
          'Amount',
          'Sequence number',
          'Success',
          'Control code',
          'Control server ID',
          'Reason',
        ].map(csvField).join(','),
      );
    for (final entry in entries) {
      buffer.writeln(
        [
          entry.timestamp.toIso8601String(),
          _kindLabel(entry.kind),
          entry.orderReference,
          (entry.amountCents / 100).toStringAsFixed(2),
          entry.sequenceNumber,
          entry.success ? 'yes' : 'no',
          entry.controlCode ?? '',
          entry.controlServerId ?? '',
          entry.failureReason ?? '',
        ].map(csvField).join(','),
      );
    }

    await file.writeAsString(buffer.toString());
    return file.path;
  }

  String _kindLabel(JournalEntryKind kind) => switch (kind) {
    JournalEntryKind.sale => 'Sale',
    JournalEntryKind.copy => 'Copy (Kopia)',
    JournalEntryKind.refund => 'Refund',
    JournalEntryKind.practice => 'Practice (Övning)',
    JournalEntryKind.proforma => 'Proforma (Ej kvitto)',
    JournalEntryKind.failedSale => 'Failed sale',
  };
}

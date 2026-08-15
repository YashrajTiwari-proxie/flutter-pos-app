// Settings pane for X-day/Z-day fiscal reports (SKVFS 2014:9 Ch.7 §2-3).
// X-report is a live subscription (a running total by definition); Z-report
// shows the latest already-generated one and only advances via an explicit
// "Generate Z-report" action — never recomputed silently, since a Z-report
// is a formal, numbered, immutable close-of-day event.

import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:kds_pos/Database/repositories/fiscal_reports_repository.dart';
import 'package:kds_pos/Services/report_export_service.dart';

import 'fiscal_report_models.dart';

class FiscalReportsPane extends StatefulWidget {
  const FiscalReportsPane({super.key});

  @override
  State<FiscalReportsPane> createState() => _FiscalReportsPaneState();
}

class _FiscalReportsPaneState extends State<FiscalReportsPane> {
  final _repository = FiscalReportsRepository.instance;

  FiscalReportKind _kind = FiscalReportKind.x;

  SubscriptionHandle? _xSubscription;
  SubscriptionHandle? _zSubscription;
  FiscalReport? _xReport;
  FiscalReport? _zReport;
  String? _error;
  bool _isGenerating = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  Future<void> _subscribe() async {
    try {
      _xSubscription = await _repository.subscribeToXReport(
        onUpdate: (report) {
          if (mounted) setState(() => _xReport = report);
        },
        onError: (message, _) {
          if (mounted) setState(() => _error = 'Could not load X-report: $message');
        },
      );
      _zSubscription = await _repository.subscribeToLatestZReport(
        onUpdate: (report) {
          if (mounted) setState(() => _zReport = report);
        },
        onError: (message, _) {
          if (mounted) setState(() => _error = 'Could not load Z-report: $message');
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load fiscal reports: $e');
    }
  }

  @override
  void dispose() {
    _xSubscription?.cancel();
    _zSubscription?.cancel();
    super.dispose();
  }

  Future<void> _generateZReport() async {
    setState(() => _isGenerating = true);
    try {
      final report = await _repository.generateZReport();
      if (mounted) setState(() => _zReport = report);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not generate Z-report: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _saveReport(FiscalReport report) async {
    setState(() => _isSaving = true);
    try {
      final path = await ReportExportService.instance.saveFiscalReport(report);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save report: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _kind == FiscalReportKind.x ? _xReport : _zReport;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Fiscal Reports', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                SegmentedButton<FiscalReportKind>(
                  segments: const [
                    ButtonSegment(value: FiscalReportKind.x, label: Text('X-Report')),
                    ButtonSegment(value: FiscalReportKind.z, label: Text('Z-Report')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_kind == FiscalReportKind.z)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: _isGenerating ? null : _generateZReport,
                      icon: _isGenerating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.lock_clock_outlined, size: 18),
                      label: Text(_isGenerating ? 'Generating…' : 'Generate Z-report (close day)'),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: (report == null || _isSaving) ? null : () => _saveReport(report),
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined, size: 18),
                  label: Text(_isSaving ? 'Saving…' : 'Download'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: report == null
                  ? Center(
                      child: Text(
                        _kind == FiscalReportKind.z
                            ? 'No Z-report generated yet for this restaurant.'
                            : 'Loading…',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : SingleChildScrollView(child: _ReportBody(report: report)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final FiscalReport report;

  @override
  Widget build(BuildContext context) {
    final currency = 'SEK';
    String money(int cents) => '${(cents / 100).toStringAsFixed(2)} $currency';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(report.kind == FiscalReportKind.x ? 'X-Report (running totals)' : 'Z-Report (day close)'),
        _Kv('Company', report.companyName),
        _Kv('Org. number', report.orgNumber),
        _Kv('Register designation', report.registerDesignation),
        if (report.reportNumber != null) _Kv('Report number', '#${report.reportNumber}'),
        _Kv('Generated', report.generatedAt.toString()),
        const SizedBox(height: 20),
        _SectionHeader('Sales'),
        _Kv('Total sales', money(report.totalSalesCents)),
        _Kv('Net total (after returns/discounts)', money(report.netTotalCents)),
        _Kv('Goods/services sold', '${report.goodsSoldCount}'),
        _Kv('Receipts issued', '${report.receiptCount}'),
        const SizedBox(height: 20),
        _SectionHeader('VAT breakdown'),
        for (final band in report.vatBreakdown)
          _Kv('VAT ${band.label} (net ${money(band.netCents)})', money(band.vatCents)),
        const SizedBox(height: 20),
        _SectionHeader('Payment methods'),
        for (final pm in report.paymentMethods) _Kv('${pm.method} (${pm.count})', money(pm.amountCents)),
        const SizedBox(height: 20),
        _SectionHeader('Other activity'),
        _Kv('Drawer openings', '${report.drawerOpenCount}'),
        _Kv('Receipt copies', '${report.receiptCopyCount} · ${money(report.receiptCopyAmountCents)}'),
        _Kv('Practice-mode sales', '${report.practiceCount} · ${money(report.practiceAmountCents)}'),
        _Kv('Returns', '${report.returnCount} · ${money(report.returnAmountCents)}'),
        _Kv('Discounts', money(report.discountAmountCents)),
        _Kv('Uncompleted sales', '${report.uncompletedSaleCount} · ${money(report.uncompletedSaleAmountCents)}'),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
  );
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

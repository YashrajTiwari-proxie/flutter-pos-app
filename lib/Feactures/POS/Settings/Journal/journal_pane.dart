import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:kds_pos/Database/repositories/journal_repository.dart';
import 'package:kds_pos/Services/report_export_service.dart';

import 'journal_entry.dart';

class JournalPane extends StatefulWidget {
  const JournalPane({super.key});

  @override
  State<JournalPane> createState() => _JournalPaneState();
}

class _JournalPaneState extends State<JournalPane> {
  final _repository = JournalRepository.instance;

  SubscriptionHandle? _subscription;
  List<JournalEntry>? _entries;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  Future<void> _subscribe() async {
    try {
      _subscription = await _repository.subscribeToJournal(
        onUpdate: (entries) {
          if (mounted) setState(() => _entries = entries);
        },
        onError: (message, _) {
          if (mounted) setState(() => _error = 'Could not load the journal: $message');
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load the journal: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _saveJournal(List<JournalEntry> entries) async {
    setState(() => _isSaving = true);
    try {
      final path = await ReportExportService.instance.saveJournal(entries);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save journal: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Journal', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: (entries == null || entries.isEmpty || _isSaving) ? null : () => _saveJournal(entries),
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined, size: 18),
                  label: Text(_isSaving ? 'Saving…' : 'Download'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Chronological record of every fiscal event on this register — for staff lookup or a tax inspector\'s on-demand review.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                  ? Center(
                      child: Text(
                        'No fiscal events yet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _JournalTile(entry: entries[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.entry});

  final JournalEntry entry;

  IconData get _icon => switch (entry.kind) {
    JournalEntryKind.sale => Icons.receipt_long_outlined,
    JournalEntryKind.copy => Icons.content_copy_outlined,
    JournalEntryKind.refund => Icons.undo_outlined,
    JournalEntryKind.practice => Icons.school_outlined,
    JournalEntryKind.proforma => Icons.description_outlined,
    JournalEntryKind.failedSale => Icons.error_outline,
  };

  String get _label => switch (entry.kind) {
    JournalEntryKind.sale => 'Sale',
    JournalEntryKind.copy => 'Copy (Kopia)',
    JournalEntryKind.refund => 'Refund',
    JournalEntryKind.practice => 'Practice (Övning)',
    JournalEntryKind.proforma => 'Proforma (Ej kvitto)',
    JournalEntryKind.failedSale => 'Failed sale',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: Icon(_icon, color: entry.success ? scheme.primary : scheme.error),
      title: Row(
        children: [
          Text(_label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Text(entry.orderReference, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
      subtitle: Text('${entry.timestamp} · ${(entry.amountCents / 100).toStringAsFixed(2)} SEK'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Kv('Sequence number', entry.sequenceNumber),
              if (entry.controlServerId != null) _Kv('Control server ID', entry.controlServerId!),
              if (entry.controlCode != null) _Kv('Control code', entry.controlCode!, selectable: true),
              if (entry.failureReason != null) _Kv('Reason', entry.failureReason!),
            ],
          ),
        ),
      ],
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value, {this.selectable = false});

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: selectable
                ? SelectableText(value, style: Theme.of(context).textTheme.bodySmall)
                : Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

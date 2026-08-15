// "About Us" settings pane — shows the plain-text software version and
// manufacturer name required by SKVFS 2014:9 Ch.4 §4 for any cash-register
// program. Reads the version from PackageInfo (which Flutter's build
// tooling derives from pubspec.yaml's `version:` at build time), so it can
// never drift from the value actually shipped — never hardcode this string.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Manufacturer name declared on this software's SKV manufacturer's
/// declaration — must match that document exactly (see
/// `ReDocs/Approved Infrasec June v2 Manufacturer Declaration`).
const String _kManufacturerName = 'NorrSpect';

class AboutPane extends StatefulWidget {
  const AboutPane({super.key});

  @override
  State<AboutPane> createState() => _AboutPaneState();
}

class _AboutPaneState extends State<AboutPane> {
  PackageInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _info = info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About Us', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Cash-register software identification — required by Skatteverket for every fiscalized register.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(
                'Could not read app info: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (info == null)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else ...[
              _InfoRow(label: 'Manufacturer', value: _kManufacturerName),
              _InfoRow(label: 'Product', value: info.appName),
              _InfoRow(label: 'Software version', value: info.version),
              _InfoRow(label: 'Build number', value: info.buildNumber),
              _InfoRow(label: 'Package', value: info.packageName),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kds_pos/Core/theme/theme_controller.dart';
import 'package:kds_pos/Widgets/accent_swatch_picker.dart';

/// Matches the Figma Settings layout (left nav + right detail pane), but only "Appearance" is
/// wired — the rest of the sections shown in the reference (Products Management, Notifications,
/// Security, About) aren't part of this app yet, so they're shown as disabled placeholders.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _NavEntry {
  const _NavEntry({required this.icon, required this.title, required this.subtitle, this.enabled = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _entries = [
    _NavEntry(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      subtitle: 'Dark and Light mode, accent color',
      enabled: true,
    ),
    _NavEntry(icon: Icons.storefront_outlined, title: 'Your Restaurant', subtitle: 'Coming soon'),
    _NavEntry(icon: Icons.notifications_outlined, title: 'Notifications', subtitle: 'Coming soon'),
    _NavEntry(icon: Icons.lock_outline_rounded, title: 'Security', subtitle: 'Coming soon'),
    _NavEntry(icon: Icons.info_outline_rounded, title: 'About Us', subtitle: 'Coming soon'),
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 280, child: _NavList(entries: _entries, selected: _selected, onSelected: _select)),
            const SizedBox(width: 24),
            Expanded(
              child: _selected == 0
                  ? const _AppearancePane()
                  : _ComingSoonPane(entry: _entries[_selected]),
            ),
          ],
        ),
      ),
    );
  }

  void _select(int index) {
    if (!_entries[index].enabled) return;
    setState(() => _selected = index);
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.entries, required this.selected, required this.onSelected});

  final List<_NavEntry> entries;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < entries.length; i++)
              Material(
                color: i == selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: entries[i].enabled ? () => onSelected(i) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          entries[i].icon,
                          color: i == selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant.withValues(alpha: entries[i].enabled ? 1 : 0.4),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entries[i].title,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: i == selected
                                      ? scheme.primary
                                      : entries[i].enabled
                                      ? null
                                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              Text(
                                entries[i].subtitle,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppearancePane extends StatelessWidget {
  const _AppearancePane();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            Text('Theme', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: ThemeController.instance,
              builder: (context, _) {
                final mode = ThemeController.instance.themeMode;
                return SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) => ThemeController.instance.setThemeMode(selection.first),
                );
              },
            ),
            const SizedBox(height: 32),
            Text('Accent color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            const AccentSwatchPicker(),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonPane extends StatelessWidget {
  const _ComingSoonPane({required this.entry});

  final _NavEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(entry.icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Coming soon', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

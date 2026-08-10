import 'package:flutter/material.dart';
import 'package:kds_pos/Database/models/menu_item.dart';
import 'package:kds_pos/Database/models/menu_item_addon.dart';

/// Bottom sheet for choosing which of [item]'s addons go on this cart
/// line — shown before adding an item that has any addons at all (see
/// callers in `employee_terminal_screen.dart`/`kiosk_menu_screen.dart`).
/// Resolves to the selected addons, or `null` if dismissed without
/// confirming.
Future<List<MenuItemAddon>?> showAddonPickerSheet(BuildContext context, {required MenuItem item, List<MenuItemAddon> initiallySelected = const []}) {
  return showModalBottomSheet<List<MenuItemAddon>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddonPickerSheet(item: item, initiallySelected: initiallySelected),
  );
}

class _AddonPickerSheet extends StatefulWidget {
  const _AddonPickerSheet({required this.item, required this.initiallySelected});

  final MenuItem item;
  final List<MenuItemAddon> initiallySelected;

  @override
  State<_AddonPickerSheet> createState() => _AddonPickerSheetState();
}

class _AddonPickerSheetState extends State<_AddonPickerSheet> {
  late final Set<String> _selectedIds = widget.initiallySelected.map((addon) => addon.id).toSet();

  int get _addonsCents => widget.item.addons.where((addon) => _selectedIds.contains(addon.id)).fold(0, (sum, addon) => sum + addon.priceCents);

  @override
  Widget build(BuildContext context) {
    final total = widget.item.priceCents + _addonsCents;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Choose any add-ons', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.item.addons.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final addon = widget.item.addons[index];
                  final selected = _selectedIds.contains(addon.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _selectedIds.add(addon.id);
                      } else {
                        _selectedIds.remove(addon.id);
                      }
                    }),
                    title: Text(addon.name),
                    secondary: Text('+${(addon.priceCents / 100).toStringAsFixed(2)}'),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () {
                  final selected = widget.item.addons.where((addon) => _selectedIds.contains(addon.id)).toList();
                  Navigator.of(context).pop(selected);
                },
                child: Text('Add · ${(total / 100).toStringAsFixed(2)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

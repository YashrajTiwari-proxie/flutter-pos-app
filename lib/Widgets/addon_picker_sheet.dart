import 'package:flutter/material.dart';
import 'package:kds_pos/Database/models/menu_item.dart';
import 'package:kds_pos/Database/models/menu_item_addon.dart';

/// Result of [showAddonPickerSheet] — carries the chosen addons AND how many of the item to add,
/// so a single confirm tap can add e.g. "3 with extra cheese" in one shot rather than forcing a
/// second trip to the cart's own +/- stepper to reach the desired quantity.
class AddonSelection {
  const AddonSelection({required this.addons, required this.quantity});

  final List<MenuItemAddon> addons;
  final int quantity;
}

/// Bottom sheet for choosing which of [item]'s addons go on this cart line, and how many of the
/// item to add — shown before adding an item that has any addons at all (see callers in
/// `employee_terminal_screen.dart`/`kiosk_menu_screen.dart`). Resolves to `null` if dismissed
/// without confirming.
///
/// [initiallySelected]/[initialQuantity] let a caller reopen this for an item already in the
/// cart pre-filled with its current addons/quantity — so tapping the same item again reads as
/// "here's what you have, adjust it" rather than starting over from a blank quantity of 1 every
/// time.
Future<AddonSelection?> showAddonPickerSheet(
  BuildContext context, {
  required MenuItem item,
  List<MenuItemAddon> initiallySelected = const [],
  int initialQuantity = 1,
}) {
  return showModalBottomSheet<AddonSelection>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddonPickerSheet(
      item: item,
      initiallySelected: initiallySelected,
      initialQuantity: initialQuantity,
    ),
  );
}

class _AddonPickerSheet extends StatefulWidget {
  const _AddonPickerSheet({
    required this.item,
    required this.initiallySelected,
    required this.initialQuantity,
  });

  final MenuItem item;
  final List<MenuItemAddon> initiallySelected;
  final int initialQuantity;

  @override
  State<_AddonPickerSheet> createState() => _AddonPickerSheetState();
}

class _AddonPickerSheetState extends State<_AddonPickerSheet> {
  late final Set<String> _selectedIds = widget.initiallySelected
      .map((addon) => addon.id)
      .toSet();
  late int _quantity = widget.initialQuantity;

  int get _unitAddonsCents => widget.item.addons
      .where((addon) => _selectedIds.contains(addon.id))
      .fold(0, (sum, addon) => sum + addon.priceCents);

  @override
  Widget build(BuildContext context) {
    final total = (widget.item.priceCents + _unitAddonsCents) * _quantity;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _ItemImage(item: widget.item)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _QuantityStepper(
                  quantity: _quantity,
                  onChanged: (value) => setState(() => _quantity = value),
                ),
              ],
            ),
            if (widget.item.addons.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Choose any add-ons',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.item.addons.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final addon = widget.item.addons[index];
                    final selected = _selectedIds.contains(addon.id);
                    return _AddonTile(
                      addon: addon,
                      selected: selected,
                      onTap: () => setState(() {
                        if (selected) {
                          _selectedIds.remove(addon.id);
                        } else {
                          _selectedIds.add(addon.id);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () {
                  final selected = widget.item.addons
                      .where((addon) => _selectedIds.contains(addon.id))
                      .toList();
                  Navigator.of(
                    context,
                  ).pop(AddonSelection(addons: selected, quantity: _quantity));
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

/// The item's own photo, top-and-center - gives this sheet the same visual anchor the menu
/// grid/cart already show for the item, rather than just a name with nothing to look at.
class _ItemImage extends StatelessWidget {
  const _ItemImage({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = item.imageUrl;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.ramen_dining_rounded,
                color: scheme.primary,
                size: 40,
              ),
            )
          : Icon(Icons.ramen_dining_rounded, color: scheme.primary, size: 40),
    );
  }
}

/// Big, kiosk/POS-touch-friendly +/- stepper - replaces having to reopen this sheet (or find the
/// cart line afterward) just to get more than one of the same item+addon combo.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove_rounded,
            onTap: quantity > 1 ? () => onChanged(quantity - 1) : null,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            onTap: () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            size: 22,
            color: enabled
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

/// Card-style addon row - bigger and easier to hit accurately than a stock CheckboxListTile,
/// with the whole card (not just a small checkbox) as the tap target.
class _AddonTile extends StatelessWidget {
  const _AddonTile({
    required this.addon,
    required this.selected,
    required this.onTap,
  });

  final MenuItemAddon addon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  addon.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '+${(addon.priceCents / 100).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

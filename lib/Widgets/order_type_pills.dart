import 'package:flutter/material.dart';

/// Decorative Dine In / To Go / Delivery segmented control matching the Figma order panel.
/// Orders have no order-type field yet, so this only tracks a local selection.
class OrderTypePills extends StatefulWidget {
  const OrderTypePills({super.key});

  @override
  State<OrderTypePills> createState() => _OrderTypePillsState();
}

class _OrderTypePillsState extends State<OrderTypePills> {
  static const _options = ['Dine In', 'To Go', 'Delivery'];
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < _options.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i == _options.length - 1 ? 0 : 8),
            child: ChoiceChip(
              label: Text(_options[i]),
              selected: i == _selected,
              onSelected: (_) => setState(() => _selected = i),
              selectedColor: scheme.primary,
              labelStyle: TextStyle(
                color: i == _selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              backgroundColor: scheme.surfaceContainerHigh,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
      ],
    );
  }
}

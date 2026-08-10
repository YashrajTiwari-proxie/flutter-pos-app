import 'package:flutter/material.dart';

/// Mirrors the backend's `orders.orderType` union (schema.ts) — `toGo` maps
/// to `"takeaway"` there (the pill label matches the Figma reference,
/// the wire value matches the backend's own vocabulary).
enum OrderType { dineIn, toGo, delivery }

extension OrderTypeBackendValue on OrderType {
  String get backendValue => switch (this) {
    OrderType.dineIn => 'dine_in',
    OrderType.toGo => 'takeaway',
    OrderType.delivery => 'delivery',
  };

  String get label => switch (this) {
    OrderType.dineIn => 'Dine In',
    OrderType.toGo => 'To Go',
    OrderType.delivery => 'Delivery',
  };
}

/// Dine In / To Go / Delivery segmented control matching the Figma order
/// panel — a controlled component (like `SegmentedButton` elsewhere in this
/// app): the parent owns [selected] and reacts to [onChanged], rather than
/// this widget tracking its own hidden state, so the chosen order type can
/// actually flow into `OrderRepository.createOrder`.
class OrderTypePills extends StatelessWidget {
  const OrderTypePills({super.key, required this.selected, required this.onChanged, this.options = OrderType.values});

  final OrderType selected;
  final ValueChanged<OrderType> onChanged;
  final List<OrderType> options;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i == options.length - 1 ? 0 : 8),
            child: ChoiceChip(
              label: Text(options[i].label),
              selected: options[i] == selected,
              onSelected: (_) => onChanged(options[i]),
              selectedColor: scheme.primary,
              labelStyle: TextStyle(
                color: options[i] == selected ? scheme.onPrimary : scheme.onSurfaceVariant,
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

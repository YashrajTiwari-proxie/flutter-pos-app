import 'package:flutter/material.dart';
import 'package:kds_pos/Feactures/POS/EmployeeTerminal/menu_models.dart';

/// A single dish card in the "Choose Dishes" grid, styled after the Figma reference.
/// `MenuItem` has no photo yet, so a colored icon avatar stands in for the dish photo.
class DishTile extends StatelessWidget {
  const DishTile({
    super.key,
    required this.item,
    required this.quantityInCart,
    required this.enabled,
    required this.onTap,
  });

  final MenuItem item;
  final int quantityInCart;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inCart = quantityInCart > 0;
    final available = item.available;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: inCart ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: enabled && available ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: available ? 0.16 : 0.06),
                      ),
                      child: Icon(
                        Icons.ramen_dining_rounded,
                        color: available ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text('\$ ${item.price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium),
                    if (!available) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Sold out',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (inCart)
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: scheme.primary,
                child: Text(
                  '$quantityInCart',
                  style: TextStyle(color: scheme.onPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

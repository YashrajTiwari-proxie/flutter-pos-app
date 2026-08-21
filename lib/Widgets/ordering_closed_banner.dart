import 'package:flutter/material.dart';

/// Proactive "restaurant is closed for ordering" banner — shown ahead of a
/// charge attempt, not just discovered when `createOrder` rejects it (see
/// `OrderRepository.subscribeToOrderingStatus`). Renders nothing (zero
/// size, no gap) while the restaurant is open, same pattern as
/// [ConnectivityBanner].
class OrderingClosedBanner extends StatelessWidget {
  const OrderingClosedBanner({super.key, required this.message});

  /// Null (or empty) means the restaurant is open — render nothing.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

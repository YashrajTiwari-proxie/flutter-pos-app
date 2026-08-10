import 'package:flutter/material.dart';

/// Customer-facing pickup board for a plain Android display: shows live order status
/// progression (Preparing -> Ready to pick up). Placeholder until the screen designs are
/// provided; the live Convex order subscription lands once they are.
class OrderStatusDisplayScreen extends StatelessWidget {
  const OrderStatusDisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: const Center(
        child: Text('Order status display — coming soon'),
      ),
    );
  }
}

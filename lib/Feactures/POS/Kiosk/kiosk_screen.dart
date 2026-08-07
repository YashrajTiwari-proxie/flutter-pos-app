import 'package:flutter/material.dart';
import 'package:kds_pos/Widgets/connectivity_banner.dart';

/// Self-service ordering screen for the Sunmi Flex 3 kiosk (single screen, no cashier -
/// the customer builds their own cart and pays themselves). Placeholder until the kiosk
/// screen designs are provided; menu/cart/SoftPay/printer wiring lands once they are.
class KioskScreen extends StatelessWidget {
  const KioskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ConnectivityBanner(),
              const Expanded(child: Center(child: Text('Kiosk — coming soon'))),
            ],
          ),
        ),
      ),
    );
  }
}

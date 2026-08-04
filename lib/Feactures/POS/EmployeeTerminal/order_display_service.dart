import 'package:flutter/services.dart';

import 'menu_models.dart';

/// Pushes cart snapshots to the customer-facing display, if one is attached (see
/// `android/app/.../dualdisplay/DisplayBridge.kt`). Safe to call even when no customer display
/// exists - the native side just has nothing to forward it to.
class OrderDisplayService {
  OrderDisplayService._();

  static final OrderDisplayService instance = OrderDisplayService._();

  static const _methodChannel = MethodChannel('com.proxiestudio.kds_pos/orderdisplay');

  Future<void> pushCart({required List<CartEntry> cart, required String currency}) {
    return _methodChannel.invokeMethod('pushCart', {
      'currency': currency,
      'items': cart.map((entry) => {...entry.item.toJson(), 'quantity': entry.quantity}).toList(),
    });
  }

  /// Explicitly (re)triggers detecting and showing the customer-display Presentation, rather
  /// than relying on it happening automatically at app startup - see DualDisplayLauncher's class
  /// doc. Returns true if the customer display is now showing.
  Future<bool> activateSecondaryDisplay() async {
    final result = await _methodChannel.invokeMethod<bool>('activateSecondaryDisplay');
    return result ?? false;
  }
}

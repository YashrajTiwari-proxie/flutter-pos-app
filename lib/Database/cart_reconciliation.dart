import 'models/cart_entry.dart';
import 'models/menu_category.dart';

/// Result of checking an in-progress cart against a fresh live menu
/// snapshot (see `MenuRepository.subscribeToMenu`) — [cart] is the
/// filtered survivor set, [removedItemNames] is what got dropped and
/// needs surfacing to whoever's building the order.
class CartReconciliationResult {
  const CartReconciliationResult({
    required this.cart,
    required this.removedItemNames,
  });

  final Map<String, CartEntry> cart;
  final List<String> removedItemNames;
}

/// Drops any cart line whose item is no longer in the menu at all, or is
/// there but no longer in stock — a cart is built from a snapshot of each
/// `MenuItem` at add-time, so it doesn't automatically notice a later
/// stock/availability change on its own. Call this from the menu
/// subscription's `onUpdate` in both `EmployeeTerminalScreen` and
/// `KioskMenuScreen` so a cart never quietly holds something that would
/// get rejected at checkout anyway (`orders:createDeviceOrder` already
/// hard-blocks this server-side — this is what makes the *building* the
/// order experience catch it too, not just the final charge attempt).
CartReconciliationResult reconcileCartWithMenu(
  Map<String, CartEntry> cart,
  List<MenuCategory> categories,
) {
  final latestById = {
    for (final category in categories)
      for (final item in category.items) item.id: item,
  };

  final survivors = <String, CartEntry>{};
  final removedNames = <String>{};
  for (final mapEntry in cart.entries) {
    final entry = mapEntry.value;
    final latest = latestById[entry.item.id];
    if (latest == null || !latest.isInStock) {
      removedNames.add(entry.item.name);
      continue;
    }
    survivors[mapEntry.key] = entry;
  }
  return CartReconciliationResult(
    cart: survivors,
    removedItemNames: removedNames.toList(),
  );
}

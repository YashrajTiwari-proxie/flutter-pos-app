import 'device_cart_item.dart';
import 'menu_item.dart';
import 'menu_item_addon.dart';

/// A line in an in-progress, not-yet-placed cart — shared by every flavour
/// that builds a cart before checkout (POS, Kiosk). Not a Convex-mirrored
/// model; [toDeviceCartItem] is the bridge into what `orders:
/// createDeviceOrder` actually accepts.
///
/// Two entries for the same [item] with a *different* [selectedAddons]
/// combination are deliberately kept as separate cart lines (see
/// [cartKey]) — the backend snapshots one fixed set of addons per
/// `orderItems` row, so "2x Burger with cheese" and "1x Burger, no
/// extras" can't be merged into a single line.
class CartEntry {
  const CartEntry({required this.item, required this.quantity, this.note, this.selectedAddons = const []});

  final MenuItem item;
  final int quantity;
  final String? note;
  final List<MenuItemAddon> selectedAddons;

  int get addonsCentsPerUnit => selectedAddons.fold(0, (sum, addon) => sum + addon.priceCents);

  int get subtotalCents => (item.priceCents + addonsCentsPerUnit) * quantity;

  /// Cart map key — item id alone isn't unique once addons are involved,
  /// since the same dish can be added twice with different selections.
  /// Addon ids are sorted so selection order never produces a different
  /// key for what's otherwise the same combination.
  String get cartKey => selectedAddons.isEmpty
      ? item.id
      : '${item.id}::${(selectedAddons.map((addon) => addon.id).toList()..sort()).join(',')}';

  CartEntry copyWith({int? quantity, String? note, List<MenuItemAddon>? selectedAddons}) => CartEntry(
    item: item,
    quantity: quantity ?? this.quantity,
    note: note ?? this.note,
    selectedAddons: selectedAddons ?? this.selectedAddons,
  );

  DeviceCartItem toDeviceCartItem() =>
      DeviceCartItem(menuItemId: item.id, quantity: quantity, notes: note, addonIds: selectedAddons.map((addon) => addon.id).toList());
}

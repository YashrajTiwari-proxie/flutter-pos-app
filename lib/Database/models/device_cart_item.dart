/// One cart line sent to `orders:createDeviceOrder` — mirrors that
/// mutation's `cartItemArg` shape in orders.ts, not a stored model of its
/// own (the backend re-derives name/price live from `menuItems` and snapshots
/// them onto the resulting `orderItems` row).
class DeviceCartItem {
  const DeviceCartItem({required this.menuItemId, required this.quantity, this.notes, this.addonIds});

  final String menuItemId;
  final int quantity;
  final String? notes;
  final List<String>? addonIds;

  Map<String, dynamic> toJson() => {
    'menuItemId': menuItemId,
    'quantity': quantity,
    if (notes != null) 'notes': notes,
    if (addonIds != null && addonIds!.isNotEmpty) 'addonIds': addonIds,
  };
}

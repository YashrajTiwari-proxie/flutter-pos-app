/// One line item on an order, as returned by `orders:listForDevice`. Note:
/// this shape has no `addons` field yet — `orders:createDeviceOrder` writes
/// per-item addon selections into a separate `orderItemAddons` table
/// (schema.ts), but `orders:listForDevice` doesn't join it in yet. A future
/// backend pass can add that join the same way staff's `orders:getWithItems`
/// already does, if/when the POS UI needs to show addons per line.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    this.menuItemId,
    this.categoryId,
    required this.name,
    required this.priceCents,
    required this.quantity,
    this.notes,
    required this.cooked,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['_id'] as String,
      orderId: json['orderId'] as String,
      menuItemId: json['menuItemId'] as String?,
      categoryId: json['categoryId'] as String?,
      name: json['name'] as String,
      priceCents: (json['priceCents'] as num).toInt(),
      quantity: (json['quantity'] as num).toInt(),
      notes: json['notes'] as String?,
      cooked: json['cooked'] as bool? ?? false,
    );
  }

  final String id;
  final String orderId;
  final String? menuItemId;
  final String? categoryId;
  final String name;
  final int priceCents;
  final int quantity;
  final String? notes;
  final bool cooked;

  int get subtotalCents => priceCents * quantity;
}

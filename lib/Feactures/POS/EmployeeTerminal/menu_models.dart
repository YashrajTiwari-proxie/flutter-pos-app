class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.available,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      available: json['available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'price': price,
    'available': available,
  };

  final String id;
  final String name;
  /// Major-unit price (e.g. SEK), not minor units. May include decimals.
  final double price;
  final bool available;
}

class CartEntry {
  const CartEntry({required this.item, required this.quantity});

  final MenuItem item;
  final int quantity;

  double get subtotal => item.price * quantity;

  CartEntry copyWith({int? quantity}) => CartEntry(item: item, quantity: quantity ?? this.quantity);
}

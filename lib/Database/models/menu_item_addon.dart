/// One addon available for a menu item, already resolved to its effective
/// price (the item-specific override, if any, else the addon's own price)
/// — matches the shape `menu:listForDevice`/`menu:listPublic` embed on
/// each item (`menu.ts`'s `resolveItemAddons`).
class MenuItemAddon {
  const MenuItemAddon({required this.id, required this.name, required this.priceCents});

  factory MenuItemAddon.fromJson(Map<String, dynamic> json) {
    return MenuItemAddon(id: json['_id'] as String, name: json['name'] as String, priceCents: (json['priceCents'] as num).toInt());
  }

  final String id;
  final String name;
  final int priceCents;
}

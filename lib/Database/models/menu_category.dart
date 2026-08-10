import 'menu_item.dart';

/// A menu category with its items nested inline — shared shape for both
/// `menu:listForDevice` (full) and `menu:listPublic` (Kiosk's guest-safe
/// browsing, which omits restaurantId/slug/sortOrder/isActive entirely —
/// hence those being nullable here rather than required).
class MenuCategory {
  const MenuCategory({
    required this.id,
    this.restaurantId,
    required this.name,
    this.slug,
    this.icon,
    this.description,
    this.imageUrl,
    this.sortOrder,
    this.isActive,
    required this.items,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    return MenuCategory(
      id: json['_id'] as String,
      restaurantId: json['restaurantId'] as String?,
      name: json['name'] as String,
      slug: json['slug'] as String?,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt(),
      isActive: json['isActive'] as bool?,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((entry) => MenuItem.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final String? restaurantId;
  final String name;
  final String? slug;
  final String? icon;
  final String? description;
  final String? imageUrl;
  final int? sortOrder;
  final bool? isActive;
  final List<MenuItem> items;
}

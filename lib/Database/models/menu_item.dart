import 'menu_item_addon.dart';

/// A menu item — shared shape for both `menu:listForDevice` (full,
/// unfiltered, includes unavailable items — POS/handheld show those
/// grayed-out rather than hiding them) and `menu:listPublic` (Kiosk's
/// guest-safe browsing, already filtered to available/in-stock items
/// server-side, and missing several staff-only bookkeeping fields
/// entirely — restaurantId/categoryId/slug/sortOrder aren't present on
/// that payload at all, hence those being nullable here rather than
/// required).
class MenuItem {
  const MenuItem({
    required this.id,
    this.restaurantId,
    this.categoryId,
    required this.name,
    this.slug,
    required this.description,
    required this.priceCents,
    required this.isAvailable,
    required this.stockStatus,
    this.unavailableUntil,
    required this.tags,
    this.sortOrder,
    this.imageUrl,
    this.addons = const [],
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['_id'] as String,
      restaurantId: json['restaurantId'] as String?,
      categoryId: json['categoryId'] as String?,
      name: json['name'] as String,
      slug: json['slug'] as String?,
      description: json['description'] as String? ?? '',
      priceCents: (json['priceCents'] as num).toInt(),
      isAvailable: json['isAvailable'] as bool? ?? true,
      stockStatus: json['stockStatus'] as String? ?? 'in_stock',
      unavailableUntil: (json['unavailableUntil'] as num?)?.toInt(),
      tags: (json['tags'] as List<dynamic>? ?? const []).map((tag) => tag as String).toList(),
      sortOrder: (json['sortOrder'] as num?)?.toInt(),
      imageUrl: json['imageUrl'] as String?,
      addons: (json['addons'] as List<dynamic>? ?? const [])
          .map((entry) => MenuItemAddon.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Round-trips through the dual-display native bridge (see
  /// `Database/order_display_service.dart`) — not sent to Convex (menu
  /// items aren't created/updated from this app).
  Map<String, dynamic> toJson() => {
    '_id': id,
    if (restaurantId != null) 'restaurantId': restaurantId,
    if (categoryId != null) 'categoryId': categoryId,
    'name': name,
    if (slug != null) 'slug': slug,
    'description': description,
    'priceCents': priceCents,
    'isAvailable': isAvailable,
    'stockStatus': stockStatus,
    if (unavailableUntil != null) 'unavailableUntil': unavailableUntil,
    'tags': tags,
    if (sortOrder != null) 'sortOrder': sortOrder,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'addons': [for (final addon in addons) {'_id': addon.id, 'name': addon.name, 'priceCents': addon.priceCents}],
  };

  final String id;
  final String? restaurantId;
  final String? categoryId;
  final String name;
  final String? slug;
  final String description;
  final int priceCents;
  final bool isAvailable;
  final String stockStatus;
  final int? unavailableUntil;
  final List<String> tags;
  final int? sortOrder;
  final String? imageUrl;
  final List<MenuItemAddon> addons;

  bool get isInStock => isAvailable && stockStatus == 'in_stock';
}

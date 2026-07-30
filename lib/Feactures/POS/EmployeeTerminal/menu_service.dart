import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import 'menu_models.dart';

class MenuService {
  MenuService._();

  static final MenuService instance = MenuService._();

  Future<List<MenuItem>> fetchMenuItems() async {
    final raw = await ConvexClient.instance.query('menu_items:list', const {});
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((entry) => MenuItem.fromJson(entry as Map<String, dynamic>)).toList();
  }
}

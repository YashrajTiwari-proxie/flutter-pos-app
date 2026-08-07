import 'package:flutter/material.dart';

/// Decorative category tabs (Hot Dishes/Cold Dishes/...) matching the Figma reference.
/// Menu items have no category field yet, so selecting a tab only changes which one is
/// highlighted — it does not filter the dish grid.
class CategoryTabBar extends StatefulWidget {
  const CategoryTabBar({
    super.key,
    this.categories = const ['Hot Dishes', 'Cold Dishes', 'Soup', 'Grill', 'Appetizer', 'Dessert'],
  });

  final List<String> categories;

  @override
  State<CategoryTabBar> createState() => _CategoryTabBarState();
}

class _CategoryTabBarState extends State<CategoryTabBar> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < widget.categories.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 28),
              child: InkWell(
                onTap: () => setState(() => _selected = i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.categories[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: i == _selected ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 3,
                        width: i == _selected ? 28 : 0,
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

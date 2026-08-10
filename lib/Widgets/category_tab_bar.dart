import 'package:flutter/material.dart';

/// Category tabs matching the Figma reference — a controlled component
/// (parent owns [selectedIndex]) so selecting a tab can actually filter the
/// dish grid, now that menu items carry a real category from
/// `menu:listForDevice`/`menu:listPublic`. Index 0 is conventionally "All"
/// (the caller includes it in [categories] itself, since this widget has
/// no opinion on that label).
class CategoryTabBar extends StatelessWidget {
  const CategoryTabBar({super.key, required this.categories, required this.selectedIndex, required this.onSelected});

  final List<String> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < categories.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 28),
              child: InkWell(
                onTap: () => onSelected(i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categories[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: i == selectedIndex ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 3,
                        width: i == selectedIndex ? 28 : 0,
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

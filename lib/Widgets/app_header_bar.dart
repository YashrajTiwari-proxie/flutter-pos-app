import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Restaurant name/date header + a live search field, matching the Figma "Jaegar Resto" bar.
/// The search field is real (filters the menu grid by name) rather than decorative.
class AppHeaderBar extends StatelessWidget {
  const AppHeaderBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatDate(DateTime date) =>
      '${_weekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]} ${date.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Dedicated light/dark logo artwork rather than a colorFilter tint, so the mark can carry
    // its own theme-specific styling instead of always being a flat recolor of one source file.
    final logoAsset = theme.brightness == Brightness.dark
        ? 'assets/NorrSpectMarkLight.svg'
        : 'assets/NorrSpectMarkDark.svg';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(logoAsset, height: 34),
                  const SizedBox(width: 10),
                  Text(
                    'NorrOne',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatDate(DateTime.now()),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 320,
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search for food, coffe, etc..',
            ),
          ),
        ),
      ],
    );
  }
}

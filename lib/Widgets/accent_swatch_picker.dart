import 'package:flutter/material.dart';
import 'package:kds_pos/Core/theme/app_colors.dart';
import 'package:kds_pos/Core/theme/theme_controller.dart';

/// Curated accent-color swatches for Settings > Appearance. Deliberately a fixed palette
/// (not a full HSV picker) so no new color-picker dependency is needed.
class AccentSwatchPicker extends StatelessWidget {
  const AccentSwatchPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final current = ThemeController.instance.accent;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final color in AppColors.accentSwatches)
              _Swatch(
                color: color,
                selected: color.toARGB32() == current.toARGB32(),
                onTap: () => ThemeController.instance.setAccent(color),
              ),
          ],
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10)] : null,
        ),
        child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// "Powered by NorrSpect" brand credit, shared by every customer-facing screen (D3 mini
/// secondary display, Kiosk, ...) - deliberately muted (reduced opacity) so it reads as
/// attribution rather than competing with the actual order/payment content around it. Picks the
/// light/dark logo mark (see `NorrSpectMarkDark.svg`/`NorrSpectMarkLight.svg`) and matching text
/// color off [surfaceBrightness] - which defaults to the ambient theme's brightness, but can be
/// overridden when the actual surface this sits on doesn't match the app's theme (e.g. the
/// kiosk's light-themed app still shows this over a dark video background + scrim).
class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({super.key, this.iconHeight = 44, this.opacity = 0.7, this.surfaceBrightness});

  final double iconHeight;
  final double opacity;
  final Brightness? surfaceBrightness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = surfaceBrightness ?? theme.brightness;
    final isDarkSurface = brightness == Brightness.dark;
    final logoAsset = isDarkSurface ? 'assets/NorrSpectMarkLight.svg' : 'assets/NorrSpectMarkDark.svg';
    final textColor = isDarkSurface ? Colors.white : null;
    return Opacity(
      opacity: opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Powered by', style: theme.textTheme.titleMedium?.copyWith(color: textColor)),
          const SizedBox(width: 12),
          SvgPicture.asset(logoAsset, height: iconHeight),
          const SizedBox(width: 10),
          Text(
            'NorrSpect',
            style: theme.textTheme.titleMedium?.copyWith(color: textColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

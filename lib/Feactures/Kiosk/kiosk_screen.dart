import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kds_pos/Core/theme/app_colors.dart';
import 'package:kds_pos/Database/device_identity_service.dart';
import 'package:kds_pos/Widgets/connectivity_banner.dart';
import 'package:kds_pos/Widgets/powered_by_footer.dart';

import 'kiosk_background_video.dart';
import 'kiosk_menu_screen.dart';

enum KioskOrderType { dineIn, takeOut }

/// Kiosk idle/start screen (Sunmi Flex 3, portrait - see `main.dart`'s per-flavor orientation
/// lock): a full-bleed looping background video (or, absent one, the branded animation - see
/// `KioskBackgroundVideo`) with a single frosted-glass "island" floating near the bottom holding
/// everything else - the Dine In/Take Out buttons, the language selector, and the brand credit -
/// rather than a separate solid footer bar below the video. Deliberately just the order-type
/// choice here - no menu/cart/SoftPay, that's `KioskMenuScreen`.
class KioskScreen extends StatelessWidget {
  const KioskScreen({super.key});

  void _selectOrderType(BuildContext context, KioskOrderType type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => KioskMenuScreen(orderType: type)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Rebuilds (and so re-initializes the video controller) whenever a manager
          // uploads/changes the kiosk background video live - without this, a long-lived
          // KioskScreen instance would only ever pick up whatever URL was current the moment
          // it was first built. See `DeviceIdentityService.remoteConfigVersion`.
          ValueListenableBuilder<int>(
            valueListenable: DeviceIdentityService.instance.remoteConfigVersion,
            builder: (context, _, _) => KioskBackgroundVideo(
              key: ValueKey(DeviceIdentityService.instance.kioskVideoUrl),
              networkUrl: DeviceIdentityService.instance.kioskVideoUrl,
            ),
          ),
          // A plain video (or the fallback animation) can land anywhere in brightness/contrast
          // - this scrim guarantees the island stays legible over it regardless.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.5, 1],
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                children: [
                  const ConnectivityBanner(),
                  const Spacer(),
                  _KioskIsland(
                    onSelected: (type) => _selectOrderType(context, type),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single floating "island" holding everything that used to be a separate solid footer bar
/// plus the order-type buttons: the Dine In/Take Out choice, the language selector, and the
/// brand credit - all in one frosted-glass panel (blurred backdrop + translucent dark tint,
/// consistent regardless of whatever's behind it) so it reads as one cohesive control surface
/// floating over the video/animation rather than two disconnected pieces.
class _KioskIsland extends StatelessWidget {
  const _KioskIsland({required this.onSelected});

  final ValueChanged<KioskOrderType> onSelected;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OrderTypeButtons(onSelected: onSelected),
              const SizedBox(height: 16),
              Row(
                children: [
                  const _LanguageSelector(),
                  const Spacer(),
                  const PoweredByFooter(
                    iconHeight: 32,
                    opacity: 0.9,
                    surfaceBrightness: Brightness.dark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderTypeButtons extends StatelessWidget {
  const _OrderTypeButtons({required this.onSelected});

  final ValueChanged<KioskOrderType> onSelected;

  @override
  Widget build(BuildContext context) {
    // Side-by-side, matching the reference's own row layout - each button shares the width
    // equally (Expanded) so both stay big/easy to tap rather than shrinking to content size.
    return Row(
      children: [
        Expanded(
          child: _OrderTypeButton(
            label: 'Dine In',
            icon: Icons.restaurant_rounded,
            onTap: () => onSelected(KioskOrderType.dineIn),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _OrderTypeButton(
            label: 'Take Out',
            icon: Icons.shopping_bag_outlined,
            onTap: () => onSelected(KioskOrderType.takeOut),
          ),
        ),
      ],
    );
  }
}

/// White pill matching the "Food POS Dark - Tablet Device" reference's own "Äta här"/"Ta med"
/// buttons exactly - white background, dark text, accent-colored icon - just generously padded
/// so it's a much bigger, easier touch target than that reference's compact pills.
class _OrderTypeButton extends StatelessWidget {
  const _OrderTypeButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(),
      elevation: 6,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: AppColors.coralAccent, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dummy language picker - no real localization is wired up, this only changes which button is
/// highlighted. Placeholder until actual multi-language menu content exists to switch between.
/// Only English/Svenska are offered (not a dropdown of many options), so two plain toggle
/// buttons read faster at a glance than opening a picker for a two-way choice.
class _LanguageSelector extends StatefulWidget {
  const _LanguageSelector();

  @override
  State<_LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<_LanguageSelector> {
  static const _languages = ['English', 'Svenska'];
  String _selected = _languages.first;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final language in _languages) ...[
          _LanguageButton(
            label: language,
            selected: language == _selected,
            onTap: () => setState(() => _selected = language),
          ),
          if (language != _languages.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Explicit colors rather than ambient theme ones - this sits on the dark frosted-glass
    // island (see `_KioskIsland`), not on the app's own light/dark surface, so it needs to look
    // right regardless of which theme the kiosk is otherwise configured with.
    return Material(
      color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

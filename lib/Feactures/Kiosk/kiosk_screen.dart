import 'package:flutter/material.dart';
import 'package:kds_pos/Core/theme/app_colors.dart';
import 'package:kds_pos/Database/device_identity_service.dart';
import 'package:kds_pos/Widgets/connectivity_banner.dart';

import 'kiosk_background_video.dart';
import 'kiosk_menu_screen.dart';

enum KioskOrderType { dineIn, takeOut }

/// Kiosk idle/start screen (Sunmi Flex 3, portrait - see `main.dart`'s per-flavor orientation
/// lock): a full-bleed looping background video (or, absent one, the branded animation - see
/// `KioskBackgroundVideo`), the Dine In/Take Out buttons floating directly over it, and a solid
/// white bar flush against the bottom edge - matching the "Food POS Dark - Tablet Device"
/// reference photo's own layout (plain pills over the poster image, language switcher + brand
/// mark in a white strip along the bottom) rather than a single frosted-glass panel holding
/// everything. Deliberately just the order-type choice here - no menu/cart/SoftPay, that's
/// `KioskMenuScreen`.
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
          // - this scrim guarantees the buttons/connectivity banner stay legible over it
          // regardless. Stops short of the bottom bar, which is opaque white and needs no scrim
          // of its own.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.5, 0.85],
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          // Bottom bar first (behind), buttons layered on top - the buttons' bottom padding
          // keeps them clear of the bar rather than the two ever overlapping.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: _KioskBottomBar()),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                children: [
                  const ConnectivityBanner(),
                  const Spacer(),
                  _OrderTypeButtons(
                    onSelected: (type) => _selectOrderType(context, type),
                  ),
                  // Clears the white bottom bar (which sizes itself to its own content) rather
                  // than a fixed guess - the bar is a sibling in the Stack, not a parent this
                  // column can size against directly.
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Solid white strip flush against the bottom edge, edge-to-edge - the language switcher on the
/// left, the brand mark on the right - matching the reference photo's own bottom bar exactly
/// rather than floating either over the video.
class _KioskBottomBar extends StatelessWidget {
  const _KioskBottomBar();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Row(
          children: [
            const _LanguageSelector(),
            const Spacer(),
            Image.asset('assets/NorrSpectBlack 1.png', height: 46),
          ],
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

enum _KioskLanguage { english, swedish }

/// Dummy language picker - no real localization is wired up yet, this only changes which flag/
/// label is highlighted. Placeholder until actual multi-language menu content exists to switch
/// between. Matches the reference photo's own bottom-bar layout: one flag badge (showing
/// whichever language is currently active), then the two language names separated by a plain
/// "|" divider - only English/Swedish are offered, so this reads faster at a glance than opening
/// a picker for a two-way choice.
class _LanguageSelector extends StatefulWidget {
  const _LanguageSelector();

  @override
  State<_LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<_LanguageSelector> {
  var _selected = _KioskLanguage.english;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FlagBadge(language: _selected),
        const SizedBox(width: 12),
        _LanguageLabel(
          label: 'English',
          selected: _selected == _KioskLanguage.english,
          onTap: () => setState(() => _selected = _KioskLanguage.english),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '|',
            style: TextStyle(color: Colors.black26, fontSize: 18),
          ),
        ),
        _LanguageLabel(
          label: 'Swedish',
          selected: _selected == _KioskLanguage.swedish,
          onTap: () => setState(() => _selected = _KioskLanguage.swedish),
        ),
      ],
    );
  }
}

/// Round flag badge sitting on the white bottom bar - a plain emoji flag is used rather than a
/// bundled image asset (no flag SVGs exist in this project yet, and only two are ever needed).
class _FlagBadge extends StatelessWidget {
  const _FlagBadge({required this.language});

  final _KioskLanguage language;

  @override
  Widget build(BuildContext context) {
    final emoji = language == _KioskLanguage.english ? '🇬🇧' : '🇸🇪';
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1F1F1),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 18)),
    );
  }
}

class _LanguageLabel extends StatelessWidget {
  const _LanguageLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Sits on the white bottom bar (see `_KioskBottomBar`), not the dark video background, so
    // this uses plain dark-on-light text rather than the rest of this screen's white-on-dark
    // styling.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.black87 : Colors.black45,
          ),
        ),
      ),
    );
  }
}

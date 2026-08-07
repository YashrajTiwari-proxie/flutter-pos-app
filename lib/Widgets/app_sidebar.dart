import 'package:flutter/material.dart';

/// Left icon rail matching the Figma reference. `Orders`, the secondary-display connect
/// action, and `Settings` are wired to real behavior; `Messages`/`Notifications`/`Logout`
/// are placeholders (no backing feature yet) and show a "coming soon" tooltip instead of
/// responding to taps.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.onOpenOrders,
    required this.onOpenSettings,
    required this.onActivateSecondaryDisplay,
    this.isActivatingSecondaryDisplay = false,
  });

  final VoidCallback onOpenOrders;
  final VoidCallback onOpenSettings;
  final VoidCallback onActivateSecondaryDisplay;
  final bool isActivatingSecondaryDisplay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 84,
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(24)),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Column(
        children: [
          _SidebarLogo(color: scheme.primary),
          const SizedBox(height: 28),
          _SidebarIcon(icon: Icons.home_rounded, selected: true, tooltip: 'Home', onTap: null),
          const SizedBox(height: 28),
          Expanded(
            child: Column(
              children: [
                _SidebarIcon(icon: Icons.receipt_long_rounded, tooltip: 'Orders', onTap: onOpenOrders),
                const SizedBox(height: 20),
                _SidebarIcon(
                  icon: Icons.cast_connected_rounded,
                  tooltip: 'Connect secondary display',
                  onTap: onActivateSecondaryDisplay,
                  loading: isActivatingSecondaryDisplay,
                ),
                const SizedBox(height: 20),
                const _SidebarIcon(icon: Icons.mail_outline_rounded, tooltip: 'Messages (coming soon)'),
                const SizedBox(height: 20),
                const _SidebarIcon(icon: Icons.notifications_none_rounded, tooltip: 'Notifications (coming soon)'),
              ],
            ),
          ),
          _SidebarIcon(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: onOpenSettings),
          const SizedBox(height: 20),
          const _SidebarIcon(icon: Icons.logout_rounded, tooltip: 'Log out (coming soon)'),
        ],
      ),
    );
  }
}

class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      child: const Icon(Icons.storefront_rounded, color: Colors.white),
    );
  }
}

class _SidebarIcon extends StatelessWidget {
  const _SidebarIcon({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.selected = false,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null && !loading;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant),
                    )
                  : Icon(
                      icon,
                      color: selected
                          ? scheme.onPrimary
                          : enabled
                          ? scheme.onSurfaceVariant
                          : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

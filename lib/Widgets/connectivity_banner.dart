import 'package:flutter/material.dart';
import 'package:kds_pos/Core/connectivity/connectivity_service.dart';

/// Slim "no internet connection" banner shared by every screen (POS, Kiosk, ...) - reflects
/// [ConnectivityService.isOnline] live, including while a payment is in flight, rather than only
/// appearing after a one-off check. Renders nothing (zero size, no gap) while online.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (context, online, _) {
        if (online) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No internet connection - payments and menu updates may fail',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

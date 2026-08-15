import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'device_identity_service.dart';

/// Shown by `app.dart` whenever `DeviceIdentityService` isn't paired yet.
/// Drives the whole handshake itself — on mount it calls `bootstrap()`:
/// recognized, still-active hardware pairs silently with no UI beyond a
/// brief loading spinner (isPairedNotifier flips before this screen even
/// finishes rendering); unrecognized/revoked hardware gets a 6-digit code
/// (+ QR) shown here while `waitForClaim` polls in the background. Once
/// staff claims the code on the admin dashboard's Devices page, pairing
/// completes automatically — nothing else on this screen needs to react,
/// `app.dart`'s `ValueListenableBuilder` on `isPairedNotifier` swaps this
/// screen out the moment `DeviceIdentityService` flips it.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  PairingChallenge? _challenge;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runPairingLoop();
  }

  Future<void> _runPairingLoop() async {
    while (mounted) {
      try {
        final challenge = await DeviceIdentityService.instance.bootstrap();
        if (challenge == null) return; // Paired silently — nothing left to do.
        if (mounted) setState(() => _challenge = challenge);
        await DeviceIdentityService.instance.waitForClaim(challenge);
        return; // Claimed — isPairedNotifier already flipped by now.
      } on PairingExpiredException {
        if (mounted) {
          setState(() => _challenge = null); // Loop again for a fresh code.
        }
      } catch (e) {
        if (mounted) setState(() => _error = 'Device offline — retrying…');
        await Future.delayed(const Duration(seconds: 5));
        if (mounted) setState(() => _error = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.point_of_sale_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  if (challenge == null) ...[
                    Text(
                      'Setting up this device…',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ] else ...[
                    Text(
                      'Pair this device',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter this code on the admin dashboard\'s Devices page to finish pairing.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      challenge.code,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                          ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: challenge.code,
                        size: 160,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

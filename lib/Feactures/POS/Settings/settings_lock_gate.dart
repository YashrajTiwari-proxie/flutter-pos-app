import 'package:flutter/material.dart';
import 'package:kds_pos/Database/device_identity_service.dart';

/// Gates [child] behind a code entry — re-locks every time this widget is
/// (re)built fresh (i.e. every time Settings is opened), it does not
/// persist "unlocked" across navigations. Two ways in:
///  - **Online**: a short-lived, single-use code staff generates for this
///    exact device from the admin dashboard's Devices page
///    (`devices:generateSettingsUnlockCode`) — requires connectivity to
///    redeem.
///  - **Offline recovery**: a long-lived code staff generated once and
///    wrote down (`devices:generateSettingsRecoveryCode`) — verified
///    purely locally against a cached hash, works with zero connectivity.
class SettingsLockGate extends StatefulWidget {
  const SettingsLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<SettingsLockGate> createState() => _SettingsLockGateState();
}

class _SettingsLockGateState extends State<SettingsLockGate> {
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    return _unlocked
        ? widget.child
        : _UnlockScreen(onUnlocked: () => setState(() => _unlocked = true));
  }
}

enum _UnlockMode { online, offlineRecovery }

class _UnlockScreen extends StatefulWidget {
  const _UnlockScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<_UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<_UnlockScreen> {
  _UnlockMode _mode = _UnlockMode.online;
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _UnlockMode.online:
          await DeviceIdentityService.instance.redeemSettingsUnlockCode(code);
          widget.onUnlocked();
        case _UnlockMode.offlineRecovery:
          final valid = await DeviceIdentityService.instance
              .verifyRecoveryCodeOffline(code);
          if (valid) {
            widget.onUnlocked();
          } else {
            setState(() => _error = 'That recovery code isn\'t valid.');
          }
      }
    } catch (_) {
      setState(
        () => _error = 'That code isn\'t valid — check it and try again.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings locked'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      // Center normally, but let the content scroll instead of overflowing
      // once the on-screen keyboard eats into the available height (a
      // fixed Center+Column here would otherwise render past the bottom
      // edge the moment the code TextField gets focus).
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Enter an unlock code',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 24),
                          SegmentedButton<_UnlockMode>(
                            segments: const [
                              ButtonSegment(
                                value: _UnlockMode.online,
                                label: Text('Code from web'),
                                icon: Icon(Icons.wifi_rounded),
                              ),
                              ButtonSegment(
                                value: _UnlockMode.offlineRecovery,
                                label: Text('Recovery code'),
                                icon: Icon(Icons.wifi_off_rounded),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (selection) => setState(() {
                              _mode = selection.first;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _mode == _UnlockMode.online
                                ? 'Ask a manager to generate a code for this device on the admin dashboard.'
                                : 'Use this device\'s long-lived recovery code — works with no internet connection.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _controller,
                            autofocus: true,
                            textCapitalization: TextCapitalization.characters,
                            textAlign: TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(letterSpacing: 4),
                            decoration: InputDecoration(
                              hintText: _mode == _UnlockMode.online
                                  ? '000000'
                                  : 'XXXX-XXXX-XXXX',
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Unlock'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kds_pos/Core/theme/app_colors.dart';

/// Stage shown by [PaymentStatusPanel]. Deliberately independent of `PaymentStage` (defined in
/// the EmployeeTerminal feature's `softpay_models.dart`) so this shared widget doesn't couple
/// `Widgets/` to a specific feature folder — callers map their own status enum to this one.
enum PaymentPanelStage { connecting, processing, approved, declined, cancelled }

/// The animated "Pay {amount}" experience shown by both the Employee Terminal (while charging)
/// and the Customer Display (mirroring the same charge) — this is the one shared component that
/// gives both screens the same connecting -> approved/declined/cancelled animation.
class PaymentStatusPanel extends StatelessWidget {
  const PaymentStatusPanel({
    super.key,
    required this.stage,
    required this.amountLabel,
    this.detail,
    this.onCancel,
    this.onDismiss,
    this.onPrint,
    this.isPrinting = false,
  });

  final PaymentPanelStage stage;
  final String amountLabel;
  final String? detail;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;
  final Future<void> Function()? onPrint;
  final bool isPrinting;

  String get _title => switch (stage) {
    PaymentPanelStage.connecting => 'Connecting to terminal…',
    PaymentPanelStage.processing => 'Tap, insert, or swipe card',
    PaymentPanelStage.approved => 'Payment approved',
    PaymentPanelStage.declined => 'Payment declined',
    PaymentPanelStage.cancelled => 'Payment cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Pay', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(amountLabel, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 36),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
            child: StageVisual(key: ValueKey(stage), stage: stage),
          ),
          const SizedBox(height: 24),
          Text(_title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 32),
          _Actions(
            stage: stage,
            onCancel: onCancel,
            onDismiss: onDismiss,
            onPrint: onPrint,
            isPrinting: isPrinting,
          ),
        ],
      ),
    );
  }
}

/// The animated visual for a given [PaymentPanelStage] - a spinner while connecting, a pulsing
/// "tap your card" ring while processing, and a pop/shake icon for the terminal stages. Public
/// (not just used internally by [PaymentStatusPanel]) so a screen with a different layout - e.g.
/// the customer display's larger side-by-side panel - can reuse the same animations at a
/// different [size] instead of duplicating them.
class StageVisual extends StatelessWidget {
  const StageVisual({super.key, required this.stage, this.size = 72});

  final PaymentPanelStage stage;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (stage) {
      PaymentPanelStage.connecting => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: size / 18, color: scheme.primary),
      ),
      PaymentPanelStage.processing => TapToPayPulse(color: scheme.primary, size: size),
      PaymentPanelStage.approved => PopIcon(
        icon: Icons.check_rounded,
        color: AppColors.success,
        size: size,
      ),
      PaymentPanelStage.declined => ShakeIcon(icon: Icons.close_rounded, color: scheme.error, size: size),
      PaymentPanelStage.cancelled => PopIcon(
        icon: Icons.block_rounded,
        color: scheme.onSurfaceVariant,
        size: size,
      ),
    };
  }
}

/// A repeating "ping" - an expanding, fading ring behind a static contactless-card icon - shown
/// while the terminal is waiting for the customer to actually tap/insert/swipe, so this reads as
/// an instruction rather than a generic loading spinner.
class TapToPayPulse extends StatefulWidget {
  const TapToPayPulse({super.key, required this.color, this.size = 72});

  final Color color;
  final double size;

  @override
  State<TapToPayPulse> createState() => _TapToPayPulseState();
}

class _TapToPayPulseState extends State<TapToPayPulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The ring and icon scale with `size`, keeping the same proportions as the original
    // 72px-icon-in-a-72px-box design (icon ~55% of the box, ring growing from ~55% to full size).
    final iconBoxSize = widget.size * 0.55;
    final iconSize = iconBoxSize * 0.6;
    final ringGrowth = widget.size - iconBoxSize;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final phase in const [0.0, 0.5])
                Builder(
                  builder: (context) {
                    final t = (_controller.value + phase) % 1.0;
                    return Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Container(
                        width: iconBoxSize + (ringGrowth * t),
                        height: iconBoxSize + (ringGrowth * t),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: widget.color, width: 2),
                        ),
                      ),
                    );
                  },
                ),
              child!,
            ],
          );
        },
        child: Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.15)),
          child: Icon(Icons.contactless_rounded, color: widget.color, size: iconSize),
        ),
      ),
    );
  }
}

/// [PopIcon]'s entrance pop, followed by a short horizontal shake - makes a declined payment
/// visually distinct from a plain "cancelled" state instead of just swapping the icon.
class ShakeIcon extends StatefulWidget {
  const ShakeIcon({super.key, required this.icon, required this.color, this.size = 72});

  final IconData icon;
  final Color color;
  final double size;

  @override
  State<ShakeIcon> createState() => _ShakeIconState();
}

class _ShakeIconState extends State<ShakeIcon> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
    ..forward();
  late final _shake = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: -1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -1.0, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0)));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_shake.value * (widget.size / 9), 0), child: child),
      child: PopIcon(icon: widget.icon, color: widget.color, size: widget.size),
    );
  }
}

class PopIcon extends StatelessWidget {
  const PopIcon({super.key, required this.icon, required this.color, this.size = 72});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
        child: Icon(icon, color: color, size: size * (40 / 72)),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.stage,
    required this.onCancel,
    required this.onDismiss,
    required this.onPrint,
    required this.isPrinting,
  });

  final PaymentPanelStage stage;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;
  final Future<void> Function()? onPrint;
  final bool isPrinting;

  @override
  Widget build(BuildContext context) {
    final isConnecting = stage == PaymentPanelStage.connecting || stage == PaymentPanelStage.processing;

    if (isConnecting) {
      if (onCancel == null) return const SizedBox.shrink();
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
      );
    }

    final showPrint = stage == PaymentPanelStage.approved && onPrint != null;
    return Row(
      children: [
        if (showPrint)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isPrinting ? null : onPrint,
              icon: isPrinting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined),
              label: const Text('Print receipt'),
            ),
          ),
        if (showPrint) const SizedBox(width: 12),
        Expanded(
          child: FilledButton(onPressed: onDismiss, child: const Text('Done')),
        ),
      ],
    );
  }
}

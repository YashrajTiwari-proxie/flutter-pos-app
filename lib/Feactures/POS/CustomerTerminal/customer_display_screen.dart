import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kds_pos/Widgets/payment_status_panel.dart';

import '../EmployeeTerminal/error_state.dart';
import '../EmployeeTerminal/menu_models.dart';
import '../EmployeeTerminal/softpay_models.dart';
import '../EmployeeTerminal/softpay_service.dart';
import 'customer_display_bridge.dart';

/// Customer-facing screen shown on the Sunmi D3 mini's secondary display: a read-only view
/// of the current order, and the SoftPay charge flow itself (so the AppSwitch hand-off lands
/// here instead of on the cashier screen). Shares the same visual language and the same
/// [PaymentStatusPanel] animation as the Employee Terminal.
class CustomerDisplayScreen extends StatefulWidget {
  const CustomerDisplayScreen({super.key});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen> {
  final _softPay = SoftPayService.instance;
  final _bridge = CustomerDisplayBridge.instance;

  StreamSubscription<CustomerBridgeEvent>? _eventSubscription;
  StreamSubscription<PaymentStatusUpdate>? _statusSubscription;

  List<CartEntry> _cart = const [];
  String _currency = '';
  bool _isCharging = false;
  PaymentStatusUpdate? _status;
  String? _chargeAmountLabel;

  @override
  void initState() {
    super.initState();
    _eventSubscription = _bridge.events.listen(_handleEvent);
  }

  void _handleEvent(CustomerBridgeEvent event) {
    switch (event) {
      case CartUpdated(:final cart, :final currency):
        setState(() {
          _cart = cart;
          _currency = currency;
        });
      case StartChargeRequested(:final amountMinor, :final currency):
        _charge(amountMinor: amountMinor, currency: currency);
      case CancelChargeRequested():
        _softPay.cancelCharge();
    }
  }

  double get _total => _cart.fold(0, (sum, entry) => sum + entry.subtotal);

  Future<void> _charge({
    required int amountMinor,
    required String currency,
  }) async {
    if (_isCharging) return;
    setState(() {
      _isCharging = true;
      _status = const PaymentStatusUpdate(stage: PaymentStage.connecting);
      _chargeAmountLabel =
          '${(amountMinor / 100).toStringAsFixed(2)} $currency';
    });

    _statusSubscription = _softPay.statusUpdates.listen((update) {
      // While processing, the SDK reports its raw internal phase name (e.g.
      // "PROCESSING_KERNEL") rather than a customer-facing message - humanize it here rather
      // than showing that technical string on a screen with no cashier around to explain it.
      // The same humanized text is relayed up to the cashier screen too, for consistency.
      final friendly =
          update.stage == PaymentStage.processing && update.detail != null
          ? PaymentStatusUpdate(
              stage: update.stage,
              detail: friendlySoftPayProcessingUpdate(update.detail!),
            )
          : update;
      if (mounted) setState(() => _status = friendly);
      _bridge.reportStatus(friendly);
    });

    try {
      final result = await _softPay.charge(
        amountMinor: amountMinor,
        currency: currency,
      );
      await _bridge.reportResult(result);
    } on SoftPayException catch (e) {
      await _bridge.reportError(e);
    } catch (e) {
      // Anything other than a SoftPayException (e.g. reporting the result back over the bridge
      // failing) must still land this screen on a terminal state - otherwise it's stuck showing
      // the in-progress animation forever, with no cashier present to dismiss it.
      if (mounted) {
        setState(
          () => _status = PaymentStatusUpdate(
            stage: PaymentStage.declined,
            detail: friendlyErrorMessage(e, action: 'processing this payment'),
          ),
        );
      }
    } finally {
      await _statusSubscription?.cancel();
      _statusSubscription = null;
    }

    // Native SoftPay already emits the settled stage (approved/declined/cancelled) over the
    // status stream before the charge/refund call resolves, so `_status` is already correct
    // here - just leave the settled animation on screen for a moment before reverting to the
    // plain order view, since there's no cashier at this screen to dismiss it manually.
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() {
        _isCharging = false;
        _status = null;
        _chargeAmountLabel = null;
      });
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: (_isCharging && _status != null)
                        ? _SecondaryPaymentPanel(
                            stage: PaymentPanelStage.values.byName(
                              _status!.stage.name,
                            ),
                            amountLabel:
                                _chargeAmountLabel ??
                                '${_total.toStringAsFixed(2)} $_currency',
                            detail: _status!.detail,
                          )
                        : _OrderSummary(
                            cart: _cart,
                            total: _total,
                            currency: _currency,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _PoweredByFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Customer-facing charge animation, laid out as amount/status on the left and a large stage
/// animation on the right (rather than [PaymentStatusPanel]'s stacked/centered layout, which is
/// tuned for the cashier screen's narrower cart panel) - the tap-to-pay moment is the one thing
/// a customer standing at this screen actually needs to notice, so it gets the most visual
/// weight. No action buttons here: unlike the cashier screen, there's no one at this display to
/// press Cancel/Print/Done - it just reflects state and resets itself (see `_charge` above).
class _SecondaryPaymentPanel extends StatelessWidget {
  const _SecondaryPaymentPanel({
    required this.stage,
    required this.amountLabel,
    this.detail,
  });

  final PaymentPanelStage stage;
  final String amountLabel;
  final String? detail;

  // "Tap, insert, or swipe card" (the cashier-screen wording) is more than a customer glancing at
  // a big animation needs - the animation itself is the instruction, so this just says what to do
  // with a card, full stop.
  String get _title => switch (stage) {
    PaymentPanelStage.connecting => 'Connecting to terminal…',
    PaymentPanelStage.processing => 'Tap to pay',
    PaymentPanelStage.approved => 'Payment approved',
    PaymentPanelStage.declined => 'Payment declined',
    PaymentPanelStage.cancelled => 'Payment cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Measured directly off this panel's own constraints and used to compute the animation size
    // explicitly below, rather than reading it back out of a LayoutBuilder nested inside
    // Expanded/Row further down - that depends on exactly how Row's non-stretch cross-axis
    // sizing and every ancestor (Card, Material, Padding) happen to propagate tight vs. loose
    // constraints, which is fragile and was silently capping the size lower than intended.
    return LayoutBuilder(
      builder: (context, panelConstraints) {
        final panelHeight = panelConstraints.hasBoundedHeight
            ? panelConstraints.maxHeight
            : 320.0;
        final rightColumnWidth = panelConstraints.maxWidth * 0.42;
        final iconSize = math
            .min(panelHeight * 0.85, rightColumnWidth)
            .clamp(160.0, 520.0);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Pay', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(amountLabel, style: theme.textTheme.displaySmall),
                  const SizedBox(height: 24),
                  Text(_title, style: theme.textTheme.titleLarge),
                  if (detail != null) ...[
                    const SizedBox(height: 8),
                    Text(detail!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: StageVisual(
                    key: ValueKey(stage),
                    stage: stage,
                    size: iconSize,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Small, low-emphasis brand credit at the bottom of the customer-facing screen - deliberately
/// muted (reduced opacity, small size) so it reads as attribution rather than competing with the
/// actual order/payment content above it.
class _PoweredByFooter extends StatelessWidget {
  const _PoweredByFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logoAsset = theme.brightness == Brightness.dark
        ? 'assets/NorrSpectMarkLight.svg'
        : 'assets/NorrSpectMarkDark.svg';
    return Opacity(
      opacity: 0.7,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Powered by', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 12),
          SvgPicture.asset(logoAsset, height: 44),
          const SizedBox(width: 10),
          Text(
            'NorrSpect',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({
    required this.cart,
    required this.total,
    required this.currency,
  });

  final List<CartEntry> cart;
  final double total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: cart.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: 'Waiting for your order…',
                )
              : ListView.separated(
                  itemCount: cart.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final entry = cart[index];
                    final scheme = Theme.of(context).colorScheme;
                    return Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primary.withValues(alpha: 0.15),
                          ),
                          child: Icon(
                            Icons.ramen_dining_rounded,
                            color: scheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            entry.item.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${entry.quantity} × ${entry.item.price.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          entry.subtotal.toStringAsFixed(2),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    );
                  },
                ),
        ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total', style: Theme.of(context).textTheme.headlineSmall),
            Text(
              '${total.toStringAsFixed(2)} $currency',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ],
    );
  }
}

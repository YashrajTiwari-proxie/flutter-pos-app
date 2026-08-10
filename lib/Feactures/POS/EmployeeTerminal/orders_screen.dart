import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:kds_pos/Database/device_identity_service.dart';
import 'package:kds_pos/Database/models/order.dart' as db;
import 'package:kds_pos/Database/repositories/order_repository.dart';

import 'error_state.dart';
import 'printer_service.dart';
import 'softpay_models.dart';
import 'softpay_service.dart';
import 'softpay_transaction_mapper.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

// Every restaurant on this backend is Swedish — orders carry no currency
// field of their own (see employee_terminal_screen.dart's same constant).
const _currency = 'SEK';

enum _OrderFilter { all, pending, paid, failed, refunded }

class _OrdersScreenState extends State<OrdersScreen> {
  final _orders = OrderRepository.instance;

  SubscriptionHandle? _subscription;
  List<db.Order>? _orders_;
  String? _error;
  _OrderFilter _filter = _OrderFilter.all;

  // Presence of a key means that order's refund is in flight; the value is the latest terminal
  // status update for it, if any has arrived yet.
  final Map<String, PaymentStatusUpdate?> _refunding = {};
  StreamSubscription<PaymentStatusUpdate>? _statusSubscription;

  final Set<String> _printingOrderIds = {};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  Future<void> _subscribe() async {
    _subscription?.cancel();
    _subscription = null;

    try {
      _subscription = await _orders.subscribeToOrders(
        onUpdate: (orders) {
          if (!mounted) return;
          setState(() {
            _orders_ = orders;
            _error = null;
          });
        },
        onError: (message, _) {
          if (!mounted) return;
          setState(() => _error = friendlyErrorMessage(message, action: 'loading orders'));
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e, action: 'loading orders'));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refund(db.Order order) async {
    final amountCents = await _promptRefundAmount(order);
    if (amountCents == null) return;
    if (!mounted) return;

    setState(() => _refunding[order.id] = null);
    _statusSubscription = SoftPayService.instance.statusUpdates.listen((update) {
      if (mounted) setState(() => _refunding[order.id] = update);
    });

    try {
      final transaction = await SoftPayService.instance.refund(
        amountMinor: amountCents,
        currency: _currency,
        posReferenceNumber: order.id,
      );
      await _orders.recordRefund(orderId: order.id, amountMinor: amountCents, transaction: toTransactionSnapshot(transaction));
      // The live subscription above will push the updated order once Convex applies it - no
      // manual reload needed.
    } on SoftPayException catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(Icons.error_outline, color: Theme.of(dialogContext).colorScheme.error),
            title: const Text('Refund failed'),
            content: Text(friendlySoftPayMessage(e.message)),
            actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(Icons.error_outline, color: Theme.of(dialogContext).colorScheme.error),
            title: const Text('Refund not saved'),
            content: Text(friendlyErrorMessage(e, action: 'saving the refund')),
            actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      await _statusSubscription?.cancel();
      _statusSubscription = null;
      if (mounted) setState(() => _refunding.remove(order.id));
    }
  }

  Future<void> _printReceipt(db.Order order) async {
    setState(() => _printingOrderIds.add(order.id));
    try {
      final charge = order.latestCharge;
      await PrinterService.instance.printReceipt(
        items: order.items
            .map((item) => ReceiptLine(name: item.name, quantity: item.quantity, subtotalCents: item.subtotalCents))
            .toList(),
        currency: _currency,
        totalCents: order.totalCents,
        cardScheme: charge?.transaction?.cardScheme,
        partialPan: charge?.transaction?.partialPan,
        orderReference: order.displayId,
        logoBytes: DeviceIdentityService.instance.logoBytes,
        headerText: DeviceIdentityService.instance.receiptConfig?.headerText,
        footerText: DeviceIdentityService.instance.receiptConfig?.footerText,
      );
    } on PrinterException catch (e) {
      if (mounted) {
        final issue = friendlyPrinterIssue(e.code) ?? e.message ?? 'Could not print the receipt';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(issue)));
      }
    } finally {
      if (mounted) setState(() => _printingOrderIds.remove(order.id));
    }
  }

  Future<int?> _promptRefundAmount(db.Order order) {
    final controller = TextEditingController(text: (order.refundableCents / 100).toStringAsFixed(2));
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refund amount'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: _currency),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.replaceAll(',', '.'));
              if (value == null || value <= 0) return;
              final cents = (value * 100).round();
              if (cents > order.refundableCents) return;
              Navigator.of(dialogContext).pop(cents);
            },
            child: const Text('Refund'),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(db.Order order) {
    switch (_filter) {
      case _OrderFilter.all:
        return true;
      case _OrderFilter.pending:
        return order.paymentStatus == 'pending';
      case _OrderFilter.paid:
        return order.paymentStatus == 'paid';
      case _OrderFilter.failed:
        return order.paymentStatus == 'failed';
      case _OrderFilter.refunded:
        return order.paymentStatus == 'refunded' || order.paymentStatus == 'partially_refunded';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 8),
                  Text('Orders', style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 16),
              _FilterRow(selected: _filter, onSelected: (filter) => setState(() => _filter = filter)),
              const SizedBox(height: 16),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final orders = _orders_;

    if (orders == null) {
      if (_error != null) {
        return ErrorState(message: _error!, onRetry: _subscribe);
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (orders.isEmpty) {
      return const EmptyState(icon: Icons.receipt_long_outlined, message: 'No orders yet');
    }

    final filtered = orders.where(_matchesFilter).toList();
    final anyRefundInProgress = _refunding.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) _ReconnectBanner(message: _error!, onRetry: _subscribe),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(icon: Icons.filter_alt_off_outlined, message: 'No orders match this filter')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    return _OrderCard(
                      order: order,
                      isRefunding: _refunding.containsKey(order.id),
                      refundStatus: _refunding[order.id],
                      refundEnabled: !anyRefundInProgress,
                      onRefund: () => _refund(order),
                      isPrinting: _printingOrderIds.contains(order.id),
                      onPrint: () => _printReceipt(order),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onSelected});

  final _OrderFilter selected;
  final ValueChanged<_OrderFilter> onSelected;

  static const _labels = {
    _OrderFilter.all: 'All',
    _OrderFilter.pending: 'Pending',
    _OrderFilter.paid: 'Paid',
    _OrderFilter.failed: 'Failed',
    _OrderFilter.refunded: 'Refunded',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final filter in _OrderFilter.values)
          ChoiceChip(label: Text(_labels[filter]!), selected: selected == filter, onSelected: (_) => onSelected(filter)),
      ],
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.isRefunding,
    required this.refundStatus,
    required this.refundEnabled,
    required this.onRefund,
    required this.isPrinting,
    required this.onPrint,
  });

  final db.Order order;
  final bool isRefunding;
  final PaymentStatusUpdate? refundStatus;
  final bool refundEnabled;
  final VoidCallback onRefund;
  final bool isPrinting;
  final VoidCallback onPrint;

  String _formatCents(int cents) => '${(cents / 100).toStringAsFixed(2)} $_currency';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${_months[local.month - 1]} ${local.day} · $hour:$minute $period';
  }

  // A plain foreground color per status - the tag background is a tint of this same color
  // (see _StatusTag), the same "colored icon/text on a light tint of that color" pattern used
  // elsewhere in the app (DishTile, cart-line avatars). Deliberately NOT scheme.*Container:
  // this theme's ColorScheme never sets primaryContainer/secondaryContainer/errorContainer/
  // tertiaryContainer, so they silently fall back to the same color as their "on" counterpart -
  // which is exactly the foreground color used here, making the tag's text invisible against
  // its own background.
  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (order.paymentStatus) {
      case 'paid':
        return scheme.primary;
      case 'failed':
        return scheme.error;
      case 'refunded':
      case 'partially_refunded':
        return scheme.tertiary;
      default:
        return scheme.secondary;
    }
  }

  String _statusLabel() {
    switch (order.paymentStatus) {
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Failed';
      case 'refunded':
        return 'Refunded';
      case 'partially_refunded':
        return 'Partially refunded';
      default:
        return 'Pending';
    }
  }

  String _refundStageLabel() {
    final status = refundStatus;
    if (status == null) return 'Connecting to terminal…';
    switch (status.stage) {
      case PaymentStage.connecting:
        return 'Connecting to terminal…';
      case PaymentStage.processing:
        return status.detail ?? 'Tap card to refund…';
      case PaymentStage.approved:
        return 'Refund approved';
      case PaymentStage.declined:
        return 'Refund declined';
      case PaymentStage.cancelled:
        return 'Refund cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final charge = order.latestCharge?.transaction;
    final failure = order.latestFailure;
    final statusColor = _statusColor(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${order.displayId} · ${_formatTimestamp(order.placedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 12),
                _StatusTag(label: _statusLabel(), color: statusColor),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${item.quantity}× ${item.name}', style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    Text(_formatCents(item.subtotalCents), style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            if (charge?.cardScheme != null) ...[
              const SizedBox(height: 4),
              Text(
                [charge!.cardScheme, if (charge.partialPan != null) '•••• ${charge.partialPan}'].join(' '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (failure != null) ...[
              const SizedBox(height: 4),
              Text(
                friendlySoftPayMessage(failure.failureMessage ?? 'Payment failed'),
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
              ),
            ],
            if (order.refundedCents > 0) ...[
              const SizedBox(height: 4),
              Text('Refunded: ${_formatCents(order.refundedCents)}'),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: Theme.of(context).textTheme.titleMedium),
                Text(_formatCents(order.totalCents), style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            if (isRefunding) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_refundStageLabel(), style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ] else if (order.canRefund || charge != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (charge != null)
                    isPrinting
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : OutlinedButton.icon(
                            onPressed: onPrint,
                            icon: const Icon(Icons.print_outlined, size: 18),
                            label: const Text('Print receipt'),
                          ),
                  if (order.canRefund) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: refundEnabled ? onRefund : null,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Refund'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

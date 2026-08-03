import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';

import 'error_state.dart';
import 'order_models.dart';
import 'order_service.dart';
import 'printer_service.dart';
import 'softpay_models.dart';
import 'softpay_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  SubscriptionHandle? _subscription;
  List<Order>? _orders;
  String? _error;

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
      _subscription = await ConvexClient.instance.subscribe(
        name: 'orders:list',
        args: const {},
        onUpdate: (raw) {
          if (!mounted) return;
          final decoded = jsonDecode(raw) as List<dynamic>;
          setState(() {
            _orders = decoded.map((entry) => Order.fromJson(entry as Map<String, dynamic>)).toList();
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

  Future<void> _refund(Order order) async {
    final amountMinor = await _promptRefundAmount(order);
    if (amountMinor == null) return;
    if (!mounted) return;

    setState(() => _refunding[order.id] = null);
    _statusSubscription = SoftPayService.instance.statusUpdates.listen((update) {
      if (mounted) setState(() => _refunding[order.id] = update);
    });

    try {
      final transaction = await SoftPayService.instance.refund(
        amountMinor: amountMinor,
        currency: order.currency,
        posReferenceNumber: order.id,
      );
      await OrderService.instance.recordRefund(orderId: order.id, amountMinor: amountMinor, transaction: transaction);
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

  Future<void> _printReceipt(Order order) async {
    setState(() => _printingOrderIds.add(order.id));
    try {
      await PrinterService.instance.printReceipt(
        items: order.items,
        currency: order.currency,
        totalMinor: order.totalMinor,
        cardScheme: order.payment?.cardScheme,
        partialPan: order.payment?.partialPan,
        orderReference: order.id,
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

  Future<int?> _promptRefundAmount(Order order) {
    final controller = TextEditingController(text: (order.refundableMinor / 100).toStringAsFixed(2));
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refund amount'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: order.currency),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.replaceAll(',', '.'));
              if (value == null || value <= 0) return;
              final minor = (value * 100).round();
              if (minor > order.refundableMinor) return;
              Navigator.of(dialogContext).pop(minor);
            },
            child: const Text('Refund'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Orders')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final orders = _orders;

    if (orders == null) {
      if (_error != null) {
        return ErrorState(message: _error!, onRetry: _subscribe);
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (orders.isEmpty) {
      return const EmptyState(icon: Icons.receipt_long_outlined, message: 'No orders yet');
    }

    final anyRefundInProgress = _refunding.isNotEmpty;
    return Column(
      children: [
        if (_error != null) _ReconnectBanner(message: _error!, onRetry: _subscribe),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
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
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
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

  final Order order;
  final bool isRefunding;
  final PaymentStatusUpdate? refundStatus;
  final bool refundEnabled;
  final VoidCallback onRefund;
  final bool isPrinting;
  final VoidCallback onPrint;

  String _formatMinor(int minor, String currency) => '${(minor / 100).toStringAsFixed(2)} $currency';

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

  (IconData, Color, Color) _statusStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (order.status) {
      case OrderStatus.paid:
        return (Icons.check_circle, scheme.primary, scheme.primaryContainer);
      case OrderStatus.failed:
        return (Icons.error, scheme.error, scheme.errorContainer);
      case OrderStatus.cancelled:
        return (Icons.block, scheme.onSurfaceVariant, scheme.surfaceContainerHighest);
      case OrderStatus.refunded:
        return (Icons.undo, scheme.tertiary, scheme.tertiaryContainer);
      case OrderStatus.partiallyRefunded:
        return (Icons.undo, scheme.tertiary, scheme.tertiaryContainer);
      case OrderStatus.processing:
        return (Icons.hourglass_top, scheme.secondary, scheme.secondaryContainer);
    }
  }

  String _statusLabel() {
    switch (order.status) {
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.paid:
        return 'Paid';
      case OrderStatus.failed:
        return 'Failed';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.refunded:
        return 'Refunded';
      case OrderStatus.partiallyRefunded:
        return 'Partially refunded';
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
    final itemSummary = order.items.map((item) => '${item.quantity}× ${item.name}').join(', ');
    final payment = order.payment;
    final (statusIcon, statusColor, statusBackground) = _statusStyle(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Chip(
                    avatar: Icon(statusIcon, size: 18, color: statusColor),
                    label: Text(_statusLabel(), overflow: TextOverflow.ellipsis),
                    backgroundColor: statusBackground,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatMinor(order.totalMinor, order.currency),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(itemSummary, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(order.createdAt),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (payment?.cardScheme != null) ...[
              const SizedBox(height: 4),
              Text(
                [
                  payment!.cardScheme,
                  if (payment.partialPan != null) '•••• ${payment.partialPan}',
                ].join(' '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (order.failure != null) ...[
              const SizedBox(height: 4),
              Text(
                'Failed: ${friendlySoftPayMessage(order.failure!.message)}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (order.refund != null) ...[
              const SizedBox(height: 4),
              Text('Refunded: ${_formatMinor(order.refund!.amountMinor, order.currency)}'),
            ],
            if (isRefunding) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_refundStageLabel(), style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ] else if (order.canRefund || order.payment != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (order.payment != null)
                    isPrinting
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            onPressed: onPrint,
                            icon: const Icon(Icons.print_outlined),
                            tooltip: 'Print receipt',
                          ),
                  if (order.canRefund)
                    OutlinedButton.icon(
                      onPressed: refundEnabled ? onRefund : null,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Refund'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'error_state.dart';
import 'menu_models.dart';
import 'menu_service.dart';
import 'order_display_service.dart';
import 'order_models.dart';
import 'order_service.dart';
import 'orders_screen.dart';
import 'printer_service.dart';
import 'softpay_models.dart';
import 'softpay_service.dart';

class EmployeeTerminalScreen extends StatefulWidget {
  const EmployeeTerminalScreen({super.key});

  @override
  State<EmployeeTerminalScreen> createState() => _EmployeeTerminalScreenState();
}

class _EmployeeTerminalScreenState extends State<EmployeeTerminalScreen> {
  // Sandbox test store/terminal (Norrspect) is configured for SEK.
  static const _currency = 'SEK';

  final _softPay = SoftPayService.instance;
  final _menuService = MenuService.instance;
  final _orderDisplay = OrderDisplayService.instance;
  final _orders = OrderService.instance;
  final _printer = PrinterService.instance;

  Future<List<MenuItem>>? _menuFuture;

  // Keyed by MenuItem.id, insertion order preserved for a stable cart display.
  final Map<String, CartEntry> _cart = {};

  bool _isCharging = false;
  PaymentStatusUpdate? _status;
  StreamSubscription<PaymentStatusUpdate>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  void _loadMenu() {
    setState(() {
      _menuFuture = _menuService.fetchMenuItems();
    });
  }

  double get _total => _cart.values.fold(0, (sum, entry) => sum + entry.subtotal);

  int get _totalMinor => (_total * 100).round();

  void _addToCart(MenuItem item) {
    if (_isCharging) return;
    setState(() {
      final existing = _cart[item.id];
      _cart[item.id] = CartEntry(item: item, quantity: (existing?.quantity ?? 0) + 1);
    });
    _syncCart();
  }

  void _removeFromCart(MenuItem item) {
    if (_isCharging) return;
    setState(() {
      final existing = _cart[item.id];
      if (existing == null) return;
      if (existing.quantity <= 1) {
        _cart.remove(item.id);
      } else {
        _cart[item.id] = existing.copyWith(quantity: existing.quantity - 1);
      }
    });
    _syncCart();
  }

  void _syncCart() {
    _orderDisplay.pushCart(cart: _cart.values.toList(), currency: _currency);
  }

  Future<void> _clearCart() async {
    if (_cart.isEmpty || _isCharging) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: Theme.of(dialogContext).colorScheme.error),
        title: const Text('Clear order?'),
        content: const Text('This removes every item from the current order.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(_cart.clear);
    _syncCart();
  }

  Future<void> _charge() async {
    if (_totalMinor <= 0 || _isCharging) return;

    setState(() {
      _isCharging = true;
      _status = const PaymentStatusUpdate(stage: PaymentStage.connecting);
    });

    _statusSubscription = _softPay.statusUpdates.listen((update) {
      if (mounted) {
        setState(() {
          _status = update;
        });
      }
    });

    final orderItems = _cart.values
        .map(
          (entry) => OrderItem(
            menuItemId: entry.item.id,
            name: entry.item.name,
            priceMinor: (entry.item.price * 100).round(),
            quantity: entry.quantity,
          ),
        )
        .toList();

    // Record the order before charging so failed/cancelled payments are tracked too, not just
    // successful ones. If Convex is unreachable we still let the charge proceed - losing order
    // tracking for one sale is better than blocking the till.
    String? orderId;
    try {
      orderId = await _orders.createOrder(currency: _currency, totalMinor: _totalMinor, items: orderItems);
    } catch (e) {
      orderId = null;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e, action: 'saving this order'))));
      }
    }

    try {
      final transaction = await _softPay.charge(amountMinor: _totalMinor, currency: _currency);
      if (orderId != null) {
        unawaited(_orders.recordPaymentSuccess(orderId: orderId, transaction: transaction));
      }
      if (!mounted) return;
      await _showResultDialog(
        success: true,
        title: 'Payment approved',
        message: transaction.cardScheme == null
            ? 'Amount: ${_total.toStringAsFixed(2)} $_currency'
            : '${transaction.cardScheme} · ${_total.toStringAsFixed(2)} $_currency',
        onPrint: () => _printReceipt(items: orderItems, transaction: transaction),
      );
      if (mounted) setState(_cart.clear);
      _syncCart();
    } on SoftPayException catch (e) {
      if (orderId != null) {
        unawaited(
          e.code == 'CANCELLED'
              ? _orders.recordCancellation(orderId: orderId)
              : _orders.recordPaymentFailure(
                  orderId: orderId,
                  code: e.code,
                  message: e.message,
                  detailedCode: e.detailedCode,
                ),
        );
      }
      if (!mounted) return;
      await _showResultDialog(success: false, title: 'Payment failed', message: friendlySoftPayMessage(e.message));
    } finally {
      await _statusSubscription?.cancel();
      _statusSubscription = null;
      if (mounted) {
        setState(() {
          _isCharging = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _cancelCharge() => _softPay.cancelCharge();

  Future<void> _printReceipt({required List<OrderItem> items, required TransactionResult transaction}) async {
    try {
      await _printer.printReceipt(
        items: items,
        currency: _currency,
        totalMinor: transaction.amountMinor,
        cardScheme: transaction.cardScheme,
        partialPan: transaction.partialPan,
      );
    } on PrinterException catch (e) {
      if (!mounted) return;
      final issue = friendlyPrinterIssue(e.code) ?? e.message ?? 'Could not print the receipt';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Receipt not printed: $issue')));
    }
  }

  Future<void> _showResultDialog({
    required bool success,
    required String title,
    required String message,
    Future<void> Function()? onPrint,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var isPrinting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            icon: Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: success ? Theme.of(dialogContext).colorScheme.primary : Theme.of(dialogContext).colorScheme.error,
            ),
            title: Text(title),
            content: Text(message),
            actions: [
              if (onPrint != null)
                TextButton.icon(
                  onPressed: isPrinting
                      ? null
                      : () async {
                          setDialogState(() => isPrinting = true);
                          await onPrint();
                          setDialogState(() => isPrinting = false);
                        },
                  icon: isPrinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: const Text('Print receipt'),
                ),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
            ],
          ),
        );
      },
    );
  }

  bool _activatingSecondaryDisplay = false;

  Future<void> _activateSecondaryDisplay() async {
    setState(() => _activatingSecondaryDisplay = true);
    try {
      final connected = await _orderDisplay.activateSecondaryDisplay();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(connected ? 'Secondary display connected' : 'No secondary display found'),
        ),
      );
    } finally {
      if (mounted) setState(() => _activatingSecondaryDisplay = false);
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quantities = {for (final entry in _cart.values) entry.item.id: entry.quantity};
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Employee Terminal'),
        actions: [
          IconButton(
            onPressed: _activatingSecondaryDisplay ? null : _activateSecondaryDisplay,
            icon: _activatingSecondaryDisplay
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.connected_tv),
            tooltip: 'Connect secondary display',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OrdersScreen())),
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Orders',
          ),
          IconButton(onPressed: _loadMenu, icon: const Icon(Icons.refresh), tooltip: 'Refresh menu'),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _Section(
                  title: 'Menu',
                  child: _MenuPanel(
                    future: _menuFuture,
                    quantities: quantities,
                    onTap: _addToCart,
                    enabled: !_isCharging,
                    onRetry: _loadMenu,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _Section(
                  title: 'Current Order',
                  trailing: TextButton.icon(
                    onPressed: (_cart.isNotEmpty && !_isCharging) ? _clearCart : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear'),
                  ),
                  child: _OrderPanel(
                    cart: _cart.values.toList(),
                    total: _total,
                    currency: _currency,
                    status: _status,
                    isCharging: _isCharging,
                    onIncrement: _addToCart,
                    onDecrement: _removeFromCart,
                    onCharge: _charge,
                    onCancel: _cancelCharge,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled card container used to visually group the menu and current-order panels.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.future,
    required this.quantities,
    required this.onTap,
    required this.enabled,
    required this.onRetry,
  });

  final Future<List<MenuItem>>? future;
  final Map<String, int> quantities;
  final ValueChanged<MenuItem> onTap;
  final bool enabled;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MenuItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: friendlyErrorMessage(snapshot.error!, action: 'loading the menu'),
            onRetry: onRetry,
          );
        }
        final items = snapshot.data ?? const <MenuItem>[];
        if (items.isEmpty) {
          return const EmptyState(icon: Icons.restaurant_menu, message: 'No menu items found');
        }
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _MenuItemTile(
              item: item,
              quantityInCart: quantities[item.id] ?? 0,
              enabled: enabled && item.available,
              onTap: () => onTap(item),
            );
          },
        );
      },
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({
    required this.item,
    required this.quantityInCart,
    required this.enabled,
    required this.onTap,
  });

  final MenuItem item;
  final int quantityInCart;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inCart = quantityInCart > 0;
    return Card(
      color: item.available ? null : Theme.of(context).disabledColor.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: inCart ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5) : BorderSide.none,
      ),
      child: Stack(
        children: [
          // Stack gives non-positioned children loose constraints, so without this the InkWell
          // would shrink to fit just its text instead of filling (and staying tappable across)
          // the whole tile.
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(item.price.toStringAsFixed(2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (!item.available) ...[
                      const SizedBox(height: 4),
                      Text('Sold out', style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (inCart)
            Positioned(
              top: 6,
              right: 6,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  '$quantityInCart',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.cart,
    required this.total,
    required this.currency,
    required this.status,
    required this.isCharging,
    required this.onIncrement,
    required this.onDecrement,
    required this.onCharge,
    required this.onCancel,
  });

  final List<CartEntry> cart;
  final double total;
  final String currency;
  final PaymentStatusUpdate? status;
  final bool isCharging;
  final ValueChanged<MenuItem> onIncrement;
  final ValueChanged<MenuItem> onDecrement;
  final VoidCallback onCharge;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: cart.isEmpty
              ? const EmptyState(icon: Icons.shopping_cart_outlined, message: 'Tap a menu item to add it')
              : ListView.separated(
                  itemCount: cart.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = cart[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(entry.subtotal.toStringAsFixed(2)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${entry.item.price.toStringAsFixed(2)} each',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: isCharging ? null : () => onDecrement(entry.item),
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  Text('${entry.quantity}'),
                                  IconButton(
                                    onPressed: isCharging ? null : () => onIncrement(entry.item),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: Theme.of(context).textTheme.titleMedium),
              Text('${total.toStringAsFixed(2)} $currency', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        if (status != null) ...[
          _StatusBanner(status: status!),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          height: 64,
          child: FilledButton(
            onPressed: (!isCharging && total > 0) ? onCharge : null,
            child: isCharging
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Charge'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: isCharging ? onCancel : null,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final PaymentStatusUpdate status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (status.stage) {
      PaymentStage.connecting => 'Connecting to terminal…',
      PaymentStage.processing => status.detail ?? 'Processing…',
      PaymentStage.approved => 'Approved',
      PaymentStage.declined => 'Declined',
      PaymentStage.cancelled => 'Cancelled',
    };
    final (icon, color) = switch (status.stage) {
      PaymentStage.connecting || PaymentStage.processing => (null, scheme.secondary),
      PaymentStage.approved => (Icons.check_circle, scheme.primary),
      PaymentStage.declined => (Icons.error, scheme.error),
      PaymentStage.cancelled => (Icons.block, scheme.onSurfaceVariant),
    };
    return Chip(
      avatar: icon != null
          ? Icon(icon, size: 18, color: color)
          : SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
      label: Text(label),
    );
  }
}

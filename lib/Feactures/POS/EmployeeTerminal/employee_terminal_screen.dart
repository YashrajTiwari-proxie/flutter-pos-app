import 'dart:async';

import 'package:flutter/material.dart';

import 'menu_models.dart';
import 'menu_service.dart';
import 'order_display_service.dart';
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

    try {
      final transaction = await _softPay.charge(amountMinor: _totalMinor, currency: _currency);
      if (!mounted) return;
      await _showResultDialog(
        success: true,
        title: 'Payment approved',
        message: transaction.cardScheme == null
            ? 'Amount: ${_total.toStringAsFixed(2)} $_currency'
            : '${transaction.cardScheme} · ${_total.toStringAsFixed(2)} $_currency',
      );
      if (mounted) setState(_cart.clear);
      _syncCart();
    } on SoftPayException catch (e) {
      if (!mounted) return;
      await _showResultDialog(success: false, title: 'Payment failed', message: e.message);
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

  Future<void> _showResultDialog({required bool success, required String title, required String message}) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Terminal'),
        actions: [
          IconButton(onPressed: _loadMenu, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _MenuPanel(future: _menuFuture, onTap: _addToCart, enabled: !_isCharging)),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.future, required this.onTap, required this.enabled});

  final Future<List<MenuItem>>? future;
  final ValueChanged<MenuItem> onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MenuItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load menu: ${snapshot.error}'));
        }
        final items = snapshot.data ?? const <MenuItem>[];
        if (items.isEmpty) {
          return const Center(child: Text('No menu items found'));
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
            return _MenuItemTile(item: item, enabled: enabled && item.available, onTap: () => onTap(item));
          },
        );
      },
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item, required this.enabled, required this.onTap});

  final MenuItem item;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: item.available ? null : Theme.of(context).disabledColor.withValues(alpha: 0.08),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(item.price.toStringAsFixed(2)),
              if (!item.available) ...[
                const SizedBox(height: 4),
                Text('Sold out', style: Theme.of(context).textTheme.labelSmall),
              ],
            ],
          ),
        ),
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
              ? const Center(child: Text('Tap a menu item to add it'))
              : ListView.separated(
                  itemCount: cart.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = cart[index];
                    return ListTile(
                      title: Text(entry.item.name),
                      subtitle: Text('${entry.item.price.toStringAsFixed(2)} × ${entry.quantity}'),
                      trailing: Row(
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
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 64,
                            child: Text(entry.subtotal.toStringAsFixed(2), textAlign: TextAlign.right),
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
    final label = switch (status.stage) {
      PaymentStage.connecting => 'Connecting to terminal…',
      PaymentStage.processing => status.detail ?? 'Processing…',
      PaymentStage.approved => 'Approved',
      PaymentStage.declined => 'Declined',
      PaymentStage.cancelled => 'Cancelled',
    };
    return Chip(label: Text(label));
  }
}

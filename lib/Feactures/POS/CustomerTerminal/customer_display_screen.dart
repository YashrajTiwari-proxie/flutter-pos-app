import 'dart:async';

import 'package:flutter/material.dart';

import '../EmployeeTerminal/menu_models.dart';
import '../EmployeeTerminal/softpay_models.dart';
import '../EmployeeTerminal/softpay_service.dart';
import 'customer_display_bridge.dart';

/// Customer-facing screen shown on the Sunmi D3 mini's secondary display: a read-only view
/// of the current order, and the SoftPay charge flow itself (so the AppSwitch hand-off lands
/// here instead of on the cashier screen).
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

  Future<void> _charge({required int amountMinor, required String currency}) async {
    if (_isCharging) return;
    setState(() {
      _isCharging = true;
      _status = const PaymentStatusUpdate(stage: PaymentStage.connecting);
    });

    _statusSubscription = _softPay.statusUpdates.listen((update) {
      if (mounted) setState(() => _status = update);
      _bridge.reportStatus(update);
    });

    try {
      final result = await _softPay.charge(amountMinor: amountMinor, currency: currency);
      await _bridge.reportResult(result);
    } on SoftPayException catch (e) {
      await _bridge.reportError(e);
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

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your order', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Expanded(
                child: _cart.isEmpty
                    ? const Center(child: Text('Waiting for order…'))
                    : ListView.separated(
                        itemCount: _cart.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = _cart[index];
                          return ListTile(
                            title: Text(entry.item.name, style: Theme.of(context).textTheme.titleLarge),
                            trailing: Text(
                              '${entry.quantity} × ${entry.item.price.toStringAsFixed(2)}  =  ${entry.subtotal.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: Theme.of(context).textTheme.headlineSmall),
                    Text('${_total.toStringAsFixed(2)} $_currency', style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
              if (_status != null) _StatusBanner(status: _status!),
            ],
          ),
        ),
      ),
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
      PaymentStage.approved => 'Payment approved',
      PaymentStage.declined => 'Payment declined',
      PaymentStage.cancelled => 'Payment cancelled',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: Chip(label: Text(label, style: Theme.of(context).textTheme.titleMedium)),
      ),
    );
  }
}

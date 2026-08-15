import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';

import '../../Database/models/order.dart';
import '../../Database/repositories/order_repository.dart';
import '../POS/EmployeeTerminal/error_state.dart';

/// Customer-facing pickup board for a plain Android display: every order this restaurant
/// currently has in progress, split into two columns by kitchen status — still being made on
/// the left, ready to collect on the right. Deliberately minimal: just each order's number, big
/// enough to read from a few metres away. No items, no customer names, no timestamps - staff
/// already have that detail on the POS/kiosk order screens; this board exists purely so a
/// waiting customer can tell at a glance whether their order is still coming or ready now.
class OrderStatusDisplayScreen extends StatefulWidget {
  const OrderStatusDisplayScreen({super.key});

  @override
  State<OrderStatusDisplayScreen> createState() =>
      _OrderStatusDisplayScreenState();
}

class _OrderStatusDisplayScreenState extends State<OrderStatusDisplayScreen> {
  final _orders = OrderRepository.instance;

  SubscriptionHandle? _subscription;
  List<Order>? _liveOrders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  Future<void> _subscribe() async {
    try {
      _subscription = await _orders.subscribeToOrders(
        onUpdate: (orders) {
          if (!mounted) return;
          setState(() {
            _liveOrders = orders;
            _error = null;
          });
        },
        onError: (message, _) {
          if (mounted) {
            setState(
              () => _error = friendlyErrorMessage(
                message,
                action: 'loading orders',
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = friendlyErrorMessage(e, action: 'loading orders'),
        );
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = _liveOrders;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: orders == null
            ? Center(
                child: _error != null
                    ? Text(
                        _error!,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      )
                    : const CircularProgressIndicator(),
              )
            : _Board(orders: orders),
      ),
    );
  }
}

// Everything still on its way to the customer: queued, being cooked, or being packed. Kept as
// one bucket rather than three separate columns - the point of this board is "is it ready or
// not", not a detailed kitchen-stage breakdown.
const _preparingStatuses = {'pending', 'cooking', 'packing'};
const _readyStatus = 'ready';

class _Board extends StatelessWidget {
  const _Board({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    // Oldest first in each column - whichever order has been waiting longest shows at the top,
    // matching the order customers actually arrived in.
    final preparing =
        orders.where((o) => _preparingStatuses.contains(o.status)).toList()
          ..sort((a, b) => a.placedAt.compareTo(b.placedAt));
    final ready = orders.where((o) => o.status == _readyStatus).toList()
      ..sort((a, b) => a.placedAt.compareTo(b.placedAt));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Column(
            title: 'Preparing',
            color: Theme.of(context).colorScheme.secondary,
            orders: preparing,
          ),
        ),
        VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: _Column(
            title: 'Ready',
            color: Theme.of(context).colorScheme.primary,
            orders: ready,
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.color,
    required this.orders,
  });

  final String title;
  final Color color;
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Text(
                    'None right now',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 16,
                    children: orders
                        .map((order) => _OrderTile(order: order, color: color))
                        .toList(),
                  ),
                ),
        ),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.color});

  final Order order;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        // The daily ticket number is what a waiting customer actually remembers from checkout
        // (see the receipt/payment panel) - the lifetime displayId is meaningless to them. Falls
        // back to displayId only for the unexpected case of an order with no dailyOrderNumber.
        order.dailyOrderNumber != null ? '#${order.dailyOrderNumber}' : order.displayId,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

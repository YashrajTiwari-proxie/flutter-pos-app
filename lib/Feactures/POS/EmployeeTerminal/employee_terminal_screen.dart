import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kds_pos/Core/connectivity/connectivity_service.dart';
import 'package:kds_pos/Core/navigation/route_observer.dart';
import 'package:kds_pos/Feactures/POS/Settings/settings_screen.dart';
import 'package:kds_pos/Widgets/app_header_bar.dart';
import 'package:kds_pos/Widgets/app_sidebar.dart';
import 'package:kds_pos/Widgets/category_tab_bar.dart';
import 'package:kds_pos/Widgets/connectivity_banner.dart';
import 'package:kds_pos/Widgets/dish_tile.dart';
import 'package:kds_pos/Widgets/order_type_pills.dart';
import 'package:kds_pos/Widgets/payment_status_panel.dart';

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

class _EmployeeTerminalScreenState extends State<EmployeeTerminalScreen>
    with RouteAware {
  // Sandbox test store/terminal (Norrspect) is configured for SEK.
  static const _currency = 'SEK';

  final _softPay = SoftPayService.instance;
  final _menuService = MenuService.instance;
  final _orderDisplay = OrderDisplayService.instance;
  final _orders = OrderService.instance;
  final _printer = PrinterService.instance;
  final _searchController = TextEditingController();
  // Owns focus for every focusable field on this screen (search field, cart-note fields) so
  // there's a single scope we control directly, rather than fighting the ambient FocusScope
  // Navigator itself manages - see didPopNext below for why that distinction matters.
  final _screenFocusScope = FocusScopeNode();

  Future<List<MenuItem>>? _menuFuture;

  // Keyed by MenuItem.id, insertion order preserved for a stable cart display.
  final Map<String, CartEntry> _cart = {};
  // Decorative per-line notes (see class doc on OrderTypePills) - local UI state only, not
  // sent to Convex since orders have no notes field yet.
  final Map<String, String> _notes = {};

  String _searchQuery = '';

  StreamSubscription<PaymentStatusUpdate>? _statusSubscription;
  PaymentPanelStage? _paymentStage;
  String? _paymentDetail;
  String? _activeAmountLabel;
  List<OrderItem>? _lastOrderItems;
  TransactionResult? _lastTransaction;
  bool _isPrinting = false;

  bool get _isBusy => _paymentStage != null;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute<void>);
  }

  @override
  void didPopNext() {
    // Unfocus our own scope, not the ambient FocusScope.of(context) - that resolves to whatever
    // scope Navigator hands back for this route, and Navigator's own FocusScopeNode restores
    // focus to whichever field was focused here before we navigated away once the covering
    // route's exit transition actually finishes, which can happen after an unfocus() on that
    // node. _screenFocusScope is a node we own outright, so nothing else re-requests focus on it
    // - one unfocus is enough, no more timing races.
    _screenFocusScope.unfocus();
  }

  void _loadMenu() {
    setState(() {
      _menuFuture = _menuService.fetchMenuItems();
    });
  }

  double get _total =>
      _cart.values.fold(0, (sum, entry) => sum + entry.subtotal);

  int get _totalMinor => (_total * 100).round();

  void _addToCart(MenuItem item) {
    if (_isBusy) return;
    setState(() {
      final existing = _cart[item.id];
      _cart[item.id] = CartEntry(
        item: item,
        quantity: (existing?.quantity ?? 0) + 1,
      );
    });
    _syncCart();
  }

  void _removeFromCart(MenuItem item) {
    if (_isBusy) return;
    setState(() {
      final existing = _cart[item.id];
      if (existing == null) return;
      if (existing.quantity <= 1) {
        _cart.remove(item.id);
        _notes.remove(item.id);
      } else {
        _cart[item.id] = existing.copyWith(quantity: existing.quantity - 1);
      }
    });
    _syncCart();
  }

  void _removeLine(MenuItem item) {
    if (_isBusy) return;
    setState(() {
      _cart.remove(item.id);
      _notes.remove(item.id);
    });
    _syncCart();
  }

  void _syncCart() {
    _orderDisplay.pushCart(cart: _cart.values.toList(), currency: _currency);
  }

  Future<void> _clearCart() async {
    if (_cart.isEmpty || _isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Clear order?'),
        content: const Text('This removes every item from the current order.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _cart.clear();
      _notes.clear();
    });
    _syncCart();
  }

  Future<void> _charge() async {
    if (_totalMinor <= 0 || _isBusy) return;

    // The continuous ConnectivityService already keeps ConnectivityBanner live for the whole
    // session (including mid-charge), but that's a background signal that can be a few seconds
    // stale - force one more fresh check right at the moment of starting a charge, on top of
    // (not instead of) that continuous monitoring.
    final online = await ConnectivityService.instance.checkNow();
    if (!online) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No internet connection. Check your connection and try again.',
            ),
          ),
        );
      }
      return;
    }

    final amountLabel = '${_total.toStringAsFixed(2)} $_currency';
    setState(() {
      _paymentStage = PaymentPanelStage.connecting;
      _paymentDetail = null;
      _activeAmountLabel = amountLabel;
    });

    _statusSubscription = _softPay.statusUpdates.listen((update) {
      if (mounted) {
        setState(() {
          _paymentStage = PaymentPanelStage.values.byName(update.stage.name);
          // While processing, the SDK reports its raw internal phase name (e.g.
          // "PROCESSING_KERNEL") rather than a customer-facing message - humanize it here
          // rather than showing that technical string as-is.
          _paymentDetail = update.stage == PaymentStage.processing && update.detail != null
              ? friendlySoftPayProcessingUpdate(update.detail!)
              : update.detail;
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
      orderId = await _orders.createOrder(
        currency: _currency,
        totalMinor: _totalMinor,
        items: orderItems,
      );
    } catch (e) {
      orderId = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e, action: 'saving this order')),
          ),
        );
      }
    }

    try {
      final transaction = await _softPay.charge(
        amountMinor: _totalMinor,
        currency: _currency,
      );
      if (orderId != null) {
        unawaited(
          _orders.recordPaymentSuccess(
            orderId: orderId,
            transaction: transaction,
          ),
        );
      }
      _lastOrderItems = orderItems;
      _lastTransaction = transaction;
      if (mounted) {
        setState(() {
          _paymentStage = PaymentPanelStage.approved;
          _paymentDetail = transaction.cardScheme == null
              ? amountLabel
              : '${transaction.cardScheme} · $amountLabel';
          _cart.clear();
          _notes.clear();
        });
      }
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
      if (mounted) {
        setState(() {
          _paymentStage = e.code == 'CANCELLED'
              ? PaymentPanelStage.cancelled
              : PaymentPanelStage.declined;
          _paymentDetail = e.code == 'CANCELLED'
              ? null
              : friendlySoftPayMessage(e.message);
        });
      }
    } catch (e) {
      // Anything other than a SoftPayException (e.g. a Convex/network failure while recording
      // the order) must still land the panel on a terminal state - otherwise it's stuck showing
      // the in-progress animation forever with no way to recover.
      if (mounted) {
        setState(() {
          _paymentStage = PaymentPanelStage.declined;
          _paymentDetail = friendlyErrorMessage(
            e,
            action: 'processing this payment',
          );
        });
      }
    } finally {
      await _statusSubscription?.cancel();
      _statusSubscription = null;
    }
  }

  Future<void> _cancelCharge() => _softPay.cancelCharge();

  void _dismissPaymentPanel() {
    setState(() {
      _paymentStage = null;
      _paymentDetail = null;
      _activeAmountLabel = null;
      _lastOrderItems = null;
      _lastTransaction = null;
    });
  }

  Future<void> _printReceipt() async {
    final items = _lastOrderItems;
    final transaction = _lastTransaction;
    if (items == null || transaction == null) return;
    setState(() => _isPrinting = true);
    try {
      await _printer.printReceipt(
        items: items,
        currency: _currency,
        totalMinor: transaction.amountMinor,
        cardScheme: transaction.cardScheme,
        partialPan: transaction.partialPan,
      );
    } on PrinterException catch (e) {
      if (mounted) {
        final issue =
            friendlyPrinterIssue(e.code) ??
            e.message ??
            'Could not print the receipt';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Receipt not printed: $issue')));
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  bool _activatingSecondaryDisplay = false;

  Future<void> _activateSecondaryDisplay() async {
    setState(() => _activatingSecondaryDisplay = true);
    try {
      final connected = await _orderDisplay.activateSecondaryDisplay();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            connected
                ? 'Secondary display connected'
                : 'No secondary display found',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _activatingSecondaryDisplay = false);
    }
  }

  void _openOrders() {
    // Also unfocus on the way out so the keyboard doesn't stay up during the push transition;
    // didPopNext (above) is what handles it on the way back.
    _screenFocusScope.unfocus();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const OrdersScreen()));
  }

  void _openSettings() {
    _screenFocusScope.unfocus();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _screenFocusScope.dispose();
    _statusSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quantities = {
      for (final entry in _cart.values) entry.item.id: entry.quantity,
    };
    return Scaffold(
      // This is a fixed tablet layout (sidebar + menu + cart panel filling the screen) - the
      // keyboard opening for the search field or a cart note should overlay it, not force the
      // whole Row to resize/compress to make room.
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      // With windowSoftInputMode="adjustNothing" (see AndroidManifest.xml) the keyboard never
      // auto-dismisses on an outside tap the way it would under adjustPan/adjustResize, so that
      // has to be done explicitly here. Scoping every field on this screen under our own
      // FocusScopeNode (rather than the ambient one Navigator manages) is what makes a single
      // unfocus() in didPopNext actually stick when returning from Orders/Settings.
      body: FocusScope(
        node: _screenFocusScope,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _screenFocusScope.unfocus(),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConnectivityBanner(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSidebar(
                          onOpenOrders: _openOrders,
                          onOpenSettings: _openSettings,
                          onActivateSecondaryDisplay: _activateSecondaryDisplay,
                          isActivatingSecondaryDisplay:
                              _activatingSecondaryDisplay,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppHeaderBar(
                                searchController: _searchController,
                                onSearchChanged: (value) =>
                                    setState(() => _searchQuery = value),
                              ),
                              const SizedBox(height: 20),
                              const CategoryTabBar(),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Choose Dishes',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _loadMenu,
                                    icon: const Icon(Icons.refresh_rounded),
                                    tooltip: 'Refresh menu',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: _MenuPanel(
                                  future: _menuFuture,
                                  quantities: quantities,
                                  onTap: _addToCart,
                                  enabled: !_isBusy,
                                  onRetry: _loadMenu,
                                  searchQuery: _searchQuery,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 2,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: _OrderPanel(
                                cart: _cart.values.toList(),
                                notes: _notes,
                                total: _total,
                                currency: _currency,
                                isBusy: _isBusy,
                                paymentStage: _paymentStage,
                                paymentDetail: _paymentDetail,
                                amountLabel:
                                    _activeAmountLabel ??
                                    '${_total.toStringAsFixed(2)} $_currency',
                                isPrinting: _isPrinting,
                                onIncrement: _addToCart,
                                onDecrement: _removeFromCart,
                                onRemoveLine: _removeLine,
                                onNoteChanged: (item, note) =>
                                    setState(() => _notes[item.id] = note),
                                onClear: (_cart.isNotEmpty && !_isBusy)
                                    ? _clearCart
                                    : null,
                                onCharge: _charge,
                                onCancelCharge: _cancelCharge,
                                onDismissPayment: _dismissPaymentPanel,
                                onPrint: _lastTransaction != null
                                    ? _printReceipt
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    required this.searchQuery,
  });

  final Future<List<MenuItem>>? future;
  final Map<String, int> quantities;
  final ValueChanged<MenuItem> onTap;
  final bool enabled;
  final VoidCallback onRetry;
  final String searchQuery;

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
            message: friendlyErrorMessage(
              snapshot.error!,
              action: 'loading the menu',
            ),
            onRetry: onRetry,
          );
        }
        final allItems = snapshot.data ?? const <MenuItem>[];
        final query = searchQuery.trim().toLowerCase();
        final items = query.isEmpty
            ? allItems
            : allItems
                  .where((item) => item.name.toLowerCase().contains(query))
                  .toList();
        if (allItems.isEmpty) {
          return const EmptyState(
            icon: Icons.restaurant_menu,
            message: 'No menu items found',
          );
        }
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off_rounded,
            message: 'No dishes match your search',
          );
        }
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return DishTile(
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

class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.cart,
    required this.notes,
    required this.total,
    required this.currency,
    required this.isBusy,
    required this.paymentStage,
    required this.paymentDetail,
    required this.amountLabel,
    required this.isPrinting,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemoveLine,
    required this.onNoteChanged,
    required this.onClear,
    required this.onCharge,
    required this.onCancelCharge,
    required this.onDismissPayment,
    required this.onPrint,
  });

  final List<CartEntry> cart;
  final Map<String, String> notes;
  final double total;
  final String currency;
  final bool isBusy;
  final PaymentPanelStage? paymentStage;
  final String? paymentDetail;
  final String amountLabel;
  final bool isPrinting;
  final ValueChanged<MenuItem> onIncrement;
  final ValueChanged<MenuItem> onDecrement;
  final ValueChanged<MenuItem> onRemoveLine;
  final void Function(MenuItem item, String note) onNoteChanged;
  final VoidCallback? onClear;
  final VoidCallback onCharge;
  final VoidCallback onCancelCharge;
  final VoidCallback onDismissPayment;
  final Future<void> Function()? onPrint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Current Order',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: paymentStage != null
              ? PaymentStatusPanel(
                  stage: paymentStage!,
                  amountLabel: amountLabel,
                  detail: paymentDetail,
                  onCancel:
                      (paymentStage == PaymentPanelStage.connecting ||
                          paymentStage == PaymentPanelStage.processing)
                      ? onCancelCharge
                      : null,
                  onDismiss:
                      (paymentStage == PaymentPanelStage.approved ||
                          paymentStage == PaymentPanelStage.declined ||
                          paymentStage == PaymentPanelStage.cancelled)
                      ? onDismissPayment
                      : null,
                  onPrint: onPrint,
                  isPrinting: isPrinting,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const OrderTypePills(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: cart.isEmpty
                          ? const EmptyState(
                              icon: Icons.shopping_cart_outlined,
                              message: 'Tap a menu item to add it',
                            )
                          : ListView.separated(
                              itemCount: cart.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 24),
                              itemBuilder: (context, index) {
                                final entry = cart[index];
                                return _CartLine(
                                  entry: entry,
                                  note: notes[entry.item.id] ?? '',
                                  isBusy: isBusy,
                                  onIncrement: () => onIncrement(entry.item),
                                  onDecrement: () => onDecrement(entry.item),
                                  onRemove: () => onRemoveLine(entry.item),
                                  onNoteChanged: (note) =>
                                      onNoteChanged(entry.item, note),
                                );
                              },
                            ),
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Discount',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '\$0',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sub total',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${total.toStringAsFixed(2)} $currency',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: (!isBusy && total > 0) ? onCharge : null,
                        child: Text(
                          'Charge ${total.toStringAsFixed(2)} $currency',
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.entry,
    required this.note,
    required this.isBusy,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onNoteChanged,
  });

  final CartEntry entry;
  final String note;
  final bool isBusy;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final ValueChanged<String> onNoteChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.ramen_dining_rounded,
                color: scheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: isBusy ? null : onDecrement,
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text('${entry.quantity}'),
                  IconButton(
                    onPressed: isBusy ? null : onIncrement,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              entry.subtotal.toStringAsFixed(2),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            IconButton(
              onPressed: isBusy ? null : onRemove,
              icon: Icon(Icons.delete_outline, color: scheme.error, size: 20),
              tooltip: 'Remove item',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          enabled: !isBusy,
          onChanged: onNoteChanged,
          initialValue: note,
          decoration: const InputDecoration(
            hintText: 'Order Note...',
            isDense: true,
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

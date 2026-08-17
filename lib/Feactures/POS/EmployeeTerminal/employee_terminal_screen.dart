import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:kds_pos/Core/connectivity/connectivity_service.dart';
import 'package:kds_pos/Core/navigation/route_observer.dart';
import 'package:kds_pos/Database/cart_reconciliation.dart';
import 'package:kds_pos/Database/device_identity_service.dart';
import 'package:kds_pos/Database/models/cart_entry.dart';
import 'package:kds_pos/Database/models/menu_category.dart';
import 'package:kds_pos/Database/models/menu_item.dart';
import 'package:kds_pos/Database/models/menu_item_addon.dart';
import 'package:kds_pos/Database/repositories/menu_repository.dart';
import 'package:kds_pos/Database/repositories/order_repository.dart';
import 'package:kds_pos/Feactures/POS/Settings/settings_screen.dart';
import 'package:kds_pos/Services/tcs/pos_payments_service.dart';
import 'package:kds_pos/Services/tcs/tcs_models.dart';
import 'package:kds_pos/Widgets/addon_picker_sheet.dart';
import 'package:kds_pos/Widgets/app_header_bar.dart';
import 'package:kds_pos/Widgets/app_sidebar.dart';
import 'package:kds_pos/Widgets/category_tab_bar.dart';
import 'package:kds_pos/Widgets/connectivity_banner.dart';
import 'package:kds_pos/Widgets/dish_tile.dart';
import 'package:kds_pos/Widgets/order_type_pills.dart';
import 'package:kds_pos/Widgets/payment_status_panel.dart';
import 'package:uuid/uuid.dart';

import 'error_state.dart';
import 'order_display_service.dart';
import 'orders_screen.dart';
import 'printer_service.dart';
import 'softpay_models.dart';
import 'softpay_service.dart';
import 'softpay_transaction_mapper.dart';

class EmployeeTerminalScreen extends StatefulWidget {
  const EmployeeTerminalScreen({super.key});

  @override
  State<EmployeeTerminalScreen> createState() => _EmployeeTerminalScreenState();
}

class _EmployeeTerminalScreenState extends State<EmployeeTerminalScreen>
    with RouteAware {
  // Every restaurant on this backend is Swedish (see admin-panel-v2's
  // stockholmTime.ts) — orders carry no currency field of their own.
  static const _currency = 'SEK';

  final _softPay = SoftPayService.instance;
  final _menuRepository = MenuRepository.instance;
  final _orderDisplay = OrderDisplayService.instance;
  final _orders = OrderRepository.instance;
  final _printer = PrinterService.instance;
  final _searchController = TextEditingController();
  // Owns focus for every focusable field on this screen (search field, cart-note fields) so
  // there's a single scope we control directly, rather than fighting the ambient FocusScope
  // Navigator itself manages - see didPopNext below for why that distinction matters.
  final _screenFocusScope = FocusScopeNode();

  List<MenuCategory>? _categories;
  String? _menuError;
  SubscriptionHandle? _menuSubscription;

  // Keyed by CartEntry.cartKey, insertion order preserved for a stable cart display.
  final Map<String, CartEntry> _cart = {};

  String _searchQuery = '';
  OrderType _orderType = OrderType.dineIn;

  StreamSubscription<PaymentStatusUpdate>? _statusSubscription;
  PaymentPanelStage? _paymentStage;
  String? _paymentDetail;
  String? _activeAmountLabel;
  String? _activeOrderReference;
  List<CartEntry>? _lastOrderItems;
  TransactionResult? _lastTransaction;
  TcsResult? _lastFiscal;
  bool _isPrinting = false;

  // _paymentStage alone isn't set until partway through `_charge()` (after the connectivity
  // check, delivery-postal-code prompt, and order-creation await all already happened) - a
  // rapid double-tap on Pay during that window would pass a guard based on _paymentStage alone
  // twice, creating two separate orders (each with its own fresh idempotencyKey, so Convex's
  // idempotency check doesn't catch it either) and firing two real SoftPay charges. This flag is
  // set synchronously as the very first thing `_charge()` does, before any `await`, so no
  // re-entrant call can ever slip through the gap - Dart only yields to another event at an
  // `await`, never mid-synchronous-block.
  bool _isChargeInFlight = false;

  bool get _isBusy => _paymentStage != null || _isChargeInFlight;

  @override
  void initState() {
    super.initState();
    _subscribeMenu();
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

  Future<void> _subscribeMenu() async {
    _menuSubscription?.cancel();
    try {
      _menuSubscription = await _menuRepository.subscribeToMenu(
        onUpdate: (categories) {
          if (!mounted) return;
          final reconciled = reconcileCartWithMenu(_cart, categories);
          setState(() {
            _categories = categories;
            _menuError = null;
            _cart
              ..clear()
              ..addAll(reconciled.cart);
          });
          if (reconciled.removedItemNames.isNotEmpty) {
            _syncCart();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No longer available, removed from the order: ${reconciled.removedItemNames.join(', ')}',
                ),
              ),
            );
          }
        },
        onError: (message, _) {
          if (mounted) {
            setState(
              () => _menuError = friendlyErrorMessage(
                message,
                action: 'loading the menu',
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _menuError = friendlyErrorMessage(e, action: 'loading the menu'),
        );
      }
    }
  }

  int get _totalCents =>
      _cart.values.fold(0, (sum, entry) => sum + entry.subtotalCents);

  Future<void> _addToCart(MenuItem item) async {
    if (_isBusy) return;
    // If this item is already in the cart, reopen the sheet pre-filled with its current
    // addons/quantity - so tapping the same tile again reads as "here's what you have, adjust
    // it" rather than always starting over from a blank quantity of 1. Only the first match
    // matters here: an item can have more than one distinct addon combo in the cart, but this is
    // "edit the one I'm looking at", not a picker over which combo to edit.
    CartEntry? existingEntry;
    for (final entry in _cart.values) {
      if (entry.item.id == item.id) {
        existingEntry = entry;
        break;
      }
    }

    var selectedAddons =
        existingEntry?.selectedAddons ?? const <MenuItemAddon>[];
    var quantity = existingEntry?.quantity ?? 1;
    if (item.addons.isNotEmpty) {
      final picked = await showAddonPickerSheet(
        context,
        item: item,
        initiallySelected: selectedAddons,
        initialQuantity: quantity,
      );
      if (picked == null) return; // Dismissed without confirming.
      selectedAddons = picked.addons;
      quantity = picked.quantity;
    } else if (existingEntry == null) {
      // No addons and nothing already in the cart - a plain tap just adds one.
      quantity = 1;
    } else {
      // No addons to pick, but this exact item is already in the cart - a repeat tap on the
      // tile just bumps the existing line by one, same as before this change.
      quantity = existingEntry.quantity + 1;
    }

    final draft = CartEntry(
      item: item,
      quantity: quantity,
      selectedAddons: selectedAddons,
    );
    setState(() {
      final keptNote = existingEntry?.cartKey == draft.cartKey
          ? existingEntry?.note
          : null;
      if (existingEntry != null) _cart.remove(existingEntry.cartKey);
      final mergeTarget = _cart[draft.cartKey];
      _cart[draft.cartKey] = draft.copyWith(
        quantity: (mergeTarget?.quantity ?? 0) + quantity,
        note: mergeTarget?.note ?? keptNote,
      );
    });
    _syncCart();
  }

  void _incrementLine(CartEntry entry) {
    if (_isBusy) return;
    setState(
      () => _cart[entry.cartKey] = entry.copyWith(quantity: entry.quantity + 1),
    );
    _syncCart();
  }

  void _decrementLine(CartEntry entry) {
    if (_isBusy) return;
    setState(() {
      if (entry.quantity <= 1) {
        _cart.remove(entry.cartKey);
      } else {
        _cart[entry.cartKey] = entry.copyWith(quantity: entry.quantity - 1);
      }
    });
    _syncCart();
  }

  void _removeLine(CartEntry entry) {
    if (_isBusy) return;
    setState(() => _cart.remove(entry.cartKey));
    _syncCart();
  }

  void _setNote(CartEntry entry, String note) {
    setState(() => _cart[entry.cartKey] = entry.copyWith(note: note));
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
    setState(() => _cart.clear());
    _syncCart();
  }

  /// Delivery orders need a postal code (`orders:createDeviceOrder` rejects
  /// one without it) — prompted here rather than always shown, since
  /// Dine In/To Go never need it.
  Future<String?> _promptDeliveryPostalCode() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delivery postal code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 11122'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _charge() async {
    if (_totalCents <= 0 || _isBusy) return;
    _isChargeInFlight =
        true; // Set synchronously, before any await - see the flag's doc comment.
    try {
      await _runCharge();
    } finally {
      _isChargeInFlight = false;
    }
  }

  Future<void> _runCharge() async {
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

    String? deliveryPostalCode;
    if (_orderType == OrderType.delivery) {
      deliveryPostalCode = await _promptDeliveryPostalCode();
      if (deliveryPostalCode == null) return; // Cancelled the prompt.
    }

    final cartSnapshot = _cart.values.toList();

    // The order must be created (and its server-computed total known) BEFORE charging anything -
    // that server total, never this screen's own cart sum, is what gets passed to
    // SoftPayService.charge() below. If Convex can't be reached at all, we do not fall back to
    // charging the client-computed total: that would let a stale cached price, a coupon-math
    // mismatch, or a patched client charge the wrong amount with nothing server-side able to
    // catch it after the fact. Better to block the till for one sale than risk that.
    final String orderId;
    final int chargeAmountCents;
    try {
      final result = await _orders.createOrder(
        idempotencyKey: const Uuid().v4(),
        items: cartSnapshot.map((entry) => entry.toDeviceCartItem()).toList(),
        fulfillmentType: 'asap',
        orderType: _orderType.backendValue,
        paymentMethod: 'card',
        deliveryPostalCode: deliveryPostalCode,
        customerName: 'Walk-in',
      );
      orderId = result.orderId;
      chargeAmountCents = result.totalCents;
      _activeOrderReference = result.dailyOrderNumber != null
          ? '#${result.dailyOrderNumber} · ${result.displayId}'
          : result.displayId;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e, action: 'saving this order')),
          ),
        );
      }
      return;
    }

    final amountLabel =
        '${(chargeAmountCents / 100).toStringAsFixed(2)} $_currency';
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
          _paymentDetail =
              update.stage == PaymentStage.processing && update.detail != null
              ? friendlySoftPayProcessingUpdate(update.detail!)
              : update.detail;
        });
      }
    });

    try {
      final TransactionResult transaction;
      try {
        transaction = await _softPay.charge(
          amountMinor: chargeAmountCents,
          currency: _currency,
        );
      } on SoftPayException catch (e) {
        // TRANSACTION_INCOMPLETE/CLIENT_TIMEOUT mean the SDK (or this app's own watchdog -
        // see SoftPayService) couldn't determine whether the charge went through - recorded as
        // its own "unconfirmed" state (never "failed", which would risk a double-charge on
        // retry if it actually succeeded) for staff to reconcile manually.
        final isUnconfirmed =
            e.code == 'TRANSACTION_INCOMPLETE' || e.code == 'CLIENT_TIMEOUT';
        await (e.code == 'CANCELLED'
            ? _orders.recordCancellation(orderId: orderId)
            : isUnconfirmed
            ? _orders.recordPaymentUnconfirmed(
                orderId: orderId,
                code: e.code,
                message: e.message,
                detailedCode: e.detailedCode,
              )
            : _orders.recordPaymentFailure(
                orderId: orderId,
                code: e.code,
                message: e.message,
                detailedCode: e.detailedCode,
              ));
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
        return;
      } catch (e) {
        // Anything other than a SoftPayException from the charge call itself is unexpected
        // enough that we genuinely don't know whether money moved - treated the same as
        // "unconfirmed", never "failed", for the same double-charge-on-retry reason as above.
        await _orders.recordPaymentUnconfirmed(
          orderId: orderId,
          code: 'UNKNOWN',
          message: e.toString(),
        );
        if (mounted) {
          setState(() {
            _paymentStage = PaymentPanelStage.declined;
            _paymentDetail = friendlyErrorMessage(
              e,
              action: 'processing this payment',
            );
          });
        }
        return;
      }

      // The charge succeeded - everything below is reporting/fiscalization/UI bookkeeping. A
      // failure here (e.g. a transient disk/Convex issue) must NEVER downgrade an already-
      // successful charge to a declined/failed state on screen - the money moved regardless, and
      // reportChargeAndFiscalize durably queues + retries this report in the background either
      // way (see its own doc comment), so losing the live result here doesn't lose the report.
      PosPaymentReportResult? report;
      String? fiscalConfigError;
      try {
        report = await _orders.reportChargeAndFiscalize(
          orderId: orderId,
          amountCents: chargeAmountCents,
          transaction: toTransactionSnapshot(transaction),
        );
      } on ClientError_ConvexError catch (e) {
        // A genuine, permanent backend rejection (e.g. `VAT_NOT_CONFIGURED` — a menu item with
        // no VAT rate assigned) — never "pending"/transient, so this must NOT be shown as
        // "finalizing fiscal record…", which would make staff think it'll resolve on its own.
        // The money already moved (charge succeeded above), so this only affects the on-screen
        // message and printability, never the charge itself.
        fiscalConfigError = friendlyErrorMessage(e, action: 'fiscalizing this sale');
        debugPrint(
          'Permanent fiscal config error reporting charge for order $orderId: $e',
        );
      } catch (e) {
        debugPrint(
          'Failed to report/fiscalize a successful charge for order $orderId: $e',
        );
      }

      if (report?.requiresRefund == true || fiscalConfigError != null) {
        // Fiscalization either was cleanly rejected by TCS, or hit a permanent config error
        // (e.g. `VAT_NOT_CONFIGURED`/`FISCAL_NOT_CONFIGURED`) — never for a null/"unconfirmed"
        // report, which might have actually succeeded on Infrasec's side, and auto-refunding
        // that too would risk refunding a sale that's actually fine. Both cases share the same
        // underlying risk: this sale can never be fiscalized, so the customer must not stay
        // charged for it. Refund immediately rather than leaving it to a manual follow-up staff
        // could forget.
        //
        // `moneyRefunded` is set true the instant `_softPay.refund` itself returns without
        // throwing — that's the moment the money actually moves back to the customer. A failure
        // in the report/fiscalize call AFTER that point never downgrades the on-screen message
        // (same reasoning as the successful-charge path above: the outbox durably retries the
        // report in the background either way — and if the refund report hits the exact same
        // permanent config error the charge did, that's expected, not a new failure). But if
        // `_softPay.refund` itself throws, no money has moved — telling staff/the customer
        // "refunded automatically" in that case would be false, so this must show a distinct,
        // actionable message instead.
        var moneyRefunded = false;
        try {
          final refundTransaction = await _softPay.refund(
            amountMinor: chargeAmountCents,
            currency: _currency,
          );
          moneyRefunded = true;
          await _orders.reportRefundAndFiscalize(
            orderId: orderId,
            amountCents: chargeAmountCents,
            reason: fiscalConfigError != null
                ? 'Fiscalization not configured ($fiscalConfigError) — refunded automatically'
                : 'Fiscalization rejected by TCS-D — refunded automatically',
            transaction: toTransactionSnapshot(refundTransaction),
          );
        } catch (e) {
          debugPrint(
            'Auto-refund after fiscal rejection failed for order $orderId: $e',
          );
        }
        if (mounted) {
          setState(() {
            _paymentStage = PaymentPanelStage.declined;
            _paymentDetail = moneyRefunded
                ? 'Payment could not be fiscalized — refunded automatically.'
                : 'Payment could not be fiscalized and the automatic refund failed — call a manager, do not retry.';
          });
        }
        _syncCart();
        return;
      }

      _lastOrderItems = cartSnapshot;
      _lastTransaction = transaction;
      // Printing is gated on this being a genuine success (see the onPrint wiring below) — never
      // print a receipt for a fiscal call that's still pending in the background or came back
      // "unconfirmed"; SKVFS requires a confirmed registration before the receipt is issued.
      _lastFiscal = report?.fiscal;
      if (mounted) {
        setState(() {
          _paymentStage = PaymentPanelStage.approved;
          // fiscalConfigError is never set here — that case always returns early above (via the
          // auto-refund branch), never falling through to this "approved" state.
          _paymentDetail = _lastFiscal?.success == true
              ? (transaction.cardScheme == null
                    ? amountLabel
                    : '${transaction.cardScheme} · $amountLabel')
              : 'Payment approved — finalizing fiscal record…';
          _cart.clear();
        });
      }
      _syncCart();
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
      _activeOrderReference = null;
      _lastOrderItems = null;
      _lastTransaction = null;
      _lastFiscal = null;
    });
  }

  /// "19,63" -> 1963. The fiscal result's VAT bands are Swedish decimal-comma
  /// strings (TCS's own format); the printer works in integer cents.
  int _parseSwedishCents(String value) {
    // Sign is read from the string itself, not the parsed `whole` value — for a magnitude under
    // 1,00 (e.g. "-0,50"), `int.tryParse("-0")` returns 0, which is not negative, and would flip
    // the sign to positive if this used `whole < 0` instead.
    final isNegative = value.trim().startsWith('-');
    final parts = value.replaceFirst('-', '').split(',');
    final whole = int.tryParse(parts[0]) ?? 0;
    final fraction = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final magnitude = whole * 100 + fraction;
    return isNegative ? -magnitude : magnitude;
  }

  Future<void> _printReceipt() async {
    final items = _lastOrderItems;
    final transaction = _lastTransaction;
    final fiscal = _lastFiscal;
    // Gated on a genuine fiscal success — never print a receipt for a fiscal call that's still
    // pending in the background or came back "unconfirmed"/rejected (see onPrint's own gating and
    // the doc comment on _lastFiscal above).
    if (items == null || transaction == null || fiscal == null || !fiscal.success) return;
    setState(() => _isPrinting = true);
    try {
      await _printer.printReceipt(
        items: items
            .map(
              (entry) => ReceiptLine(
                name: entry.item.name,
                quantity: entry.quantity,
                subtotalCents: entry.subtotalCents,
              ),
            )
            .toList(),
        currency: _currency,
        totalCents: transaction.amountMinor,
        cardScheme: transaction.cardScheme,
        partialPan: transaction.partialPan,
        orderReference: _activeOrderReference,
        logoBytes: DeviceIdentityService.instance.logoBytes,
        headerText: DeviceIdentityService.instance.receiptConfig?.headerText,
        footerText: DeviceIdentityService.instance.receiptConfig?.footerText,
        orgNumber: fiscal.orgNr,
        controlServerId: fiscal.controlServerId,
        controlCode: fiscal.code,
        sequenceNumber: fiscal.sequenceNumber,
        vatBreakdown: fiscal.vats
            .map(
              (band) => ReceiptVatBand(
                label: '${band.percent}%',
                netCents: _parseSwedishCents(band.subtotalAmount),
                vatCents: _parseSwedishCents(band.amount),
              ),
            )
            .where((band) => band.netCents != 0 || band.vatCents != 0)
            .toList(),
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
    _menuSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Summed across every addon-combo line for the same item, so the
    // DishTile badge reflects "how many of this dish total", not just one
    // specific combo's count.
    final quantities = <String, int>{};
    for (final entry in _cart.values) {
      quantities[entry.item.id] =
          (quantities[entry.item.id] ?? 0) + entry.quantity;
    }
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
                                    onPressed: _subscribeMenu,
                                    icon: const Icon(Icons.refresh_rounded),
                                    tooltip: 'Reconnect menu',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: _MenuPanel(
                                  categories: _categories,
                                  error: _menuError,
                                  quantities: quantities,
                                  onTap: _addToCart,
                                  enabled: !_isBusy,
                                  onRetry: _subscribeMenu,
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
                                totalCents: _totalCents,
                                currency: _currency,
                                isBusy: _isBusy,
                                orderType: _orderType,
                                onOrderTypeChanged: (type) =>
                                    setState(() => _orderType = type),
                                paymentStage: _paymentStage,
                                paymentDetail: _paymentDetail,
                                amountLabel:
                                    _activeAmountLabel ??
                                    '${(_totalCents / 100).toStringAsFixed(2)} $_currency',
                                orderReference: _activeOrderReference,
                                isPrinting: _isPrinting,
                                onIncrement: _incrementLine,
                                onDecrement: _decrementLine,
                                onRemoveLine: _removeLine,
                                onNoteChanged: _setNote,
                                onClear: (_cart.isNotEmpty && !_isBusy)
                                    ? _clearCart
                                    : null,
                                onCharge: _charge,
                                onCancelCharge: _cancelCharge,
                                onDismissPayment: _dismissPaymentPanel,
                                onPrint:
                                    (_lastTransaction != null &&
                                        _lastFiscal?.success == true)
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

class _MenuPanel extends StatefulWidget {
  const _MenuPanel({
    required this.categories,
    required this.error,
    required this.quantities,
    required this.onTap,
    required this.enabled,
    required this.onRetry,
    required this.searchQuery,
  });

  /// Null while the initial subscription result hasn't arrived yet; kept
  /// live-updated by `EmployeeTerminalScreen`'s `menu:listForDevice`
  /// subscription for the whole lifetime of this screen (see
  /// `_subscribeMenu`) — never re-fetched via a one-shot call.
  final List<MenuCategory>? categories;
  final String? error;
  final Map<String, int> quantities;
  final ValueChanged<MenuItem> onTap;
  final bool enabled;
  final VoidCallback onRetry;
  final String searchQuery;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  // 0 = "All"; index i>0 selects categories[i-1].
  int _selectedCategoryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    if (categories == null) {
      if (widget.error != null) {
        return ErrorState(message: widget.error!, onRetry: widget.onRetry);
      }
      return const Center(child: CircularProgressIndicator());
    }
    final allItems = categories.expand((category) => category.items).toList();
    if (allItems.isEmpty) {
      return const EmptyState(
        icon: Icons.restaurant_menu,
        message: 'No menu items found',
      );
    }

    final query = widget.searchQuery.trim().toLowerCase();
    var items = query.isEmpty
        ? allItems
        : allItems
              .where((item) => item.name.toLowerCase().contains(query))
              .toList();
    // Category filter only applies when not searching, matching how search already
    // overrides category context in the reference design.
    if (query.isEmpty &&
        _selectedCategoryIndex > 0 &&
        _selectedCategoryIndex - 1 < categories.length) {
      final selectedCategory = categories[_selectedCategoryIndex - 1];
      items = items
          .where((item) => item.categoryId == selectedCategory.id)
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A connection error while data is already loaded shows as a banner, not a
        // full-screen replacement - staff can keep working off the last-known menu.
        if (widget.error != null)
          _MenuErrorBanner(message: widget.error!, onRetry: widget.onRetry),
        CategoryTabBar(
          categories: ['All', ...categories.map((category) => category.name)],
          selectedIndex: _selectedCategoryIndex,
          onSelected: (index) => setState(() => _selectedCategoryIndex = index),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  message: 'No dishes match your search',
                )
              : GridView.builder(
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
                      quantityInCart: widget.quantities[item.id] ?? 0,
                      enabled: widget.enabled && item.isInStock,
                      onTap: () => widget.onTap(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MenuErrorBanner extends StatelessWidget {
  const _MenuErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
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
    required this.totalCents,
    required this.currency,
    required this.isBusy,
    required this.orderType,
    required this.onOrderTypeChanged,
    required this.paymentStage,
    required this.paymentDetail,
    required this.amountLabel,
    this.orderReference,
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
  final int totalCents;
  final String currency;
  final bool isBusy;
  final OrderType orderType;
  final ValueChanged<OrderType> onOrderTypeChanged;
  final PaymentPanelStage? paymentStage;
  final String? paymentDetail;
  final String amountLabel;
  final String? orderReference;
  final bool isPrinting;
  final ValueChanged<CartEntry> onIncrement;
  final ValueChanged<CartEntry> onDecrement;
  final ValueChanged<CartEntry> onRemoveLine;
  final void Function(CartEntry entry, String note) onNoteChanged;
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
                  orderReference: orderReference,
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
                    OrderTypePills(
                      selected: orderType,
                      onChanged: isBusy ? (_) {} : onOrderTypeChanged,
                    ),
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
                                  isBusy: isBusy,
                                  onIncrement: () => onIncrement(entry),
                                  onDecrement: () => onDecrement(entry),
                                  onRemove: () => onRemoveLine(entry),
                                  onNoteChanged: (note) =>
                                      onNoteChanged(entry, note),
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
                          '${(totalCents / 100).toStringAsFixed(2)} $currency',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: (!isBusy && totalCents > 0)
                            ? onCharge
                            : null,
                        child: Text(
                          'Charge ${(totalCents / 100).toStringAsFixed(2)} $currency',
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
    required this.isBusy,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onNoteChanged,
  });

  final CartEntry entry;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (entry.selectedAddons.isNotEmpty)
                    Text(
                      entry.selectedAddons
                          .map((addon) => addon.name)
                          .join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
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
              (entry.subtotalCents / 100).toStringAsFixed(2),
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
          initialValue: entry.note ?? '',
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

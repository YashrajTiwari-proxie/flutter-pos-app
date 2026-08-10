import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kds_pos/Core/connectivity/connectivity_service.dart';
import 'package:kds_pos/Database/cart_reconciliation.dart';
import 'package:kds_pos/Database/device_identity_service.dart';
import 'package:kds_pos/Database/models/cart_entry.dart';
import 'package:kds_pos/Database/models/menu_category.dart';
import 'package:kds_pos/Database/models/menu_item.dart';
import 'package:kds_pos/Database/models/menu_item_addon.dart';
import 'package:kds_pos/Database/repositories/menu_repository.dart';
import 'package:kds_pos/Database/repositories/order_repository.dart';
import 'package:kds_pos/Widgets/addon_picker_sheet.dart';
import 'package:kds_pos/Widgets/connectivity_banner.dart';
import 'package:kds_pos/Widgets/payment_status_panel.dart';
import 'package:uuid/uuid.dart';

import '../POS/EmployeeTerminal/error_state.dart';
import '../POS/EmployeeTerminal/printer_service.dart';
import '../POS/EmployeeTerminal/softpay_models.dart';
import '../POS/EmployeeTerminal/softpay_service.dart';
import '../POS/EmployeeTerminal/softpay_transaction_mapper.dart';
import 'kiosk_screen.dart';

enum _KioskView { menu, cart }

extension _KioskOrderTypeBackendValue on KioskOrderType {
  String get backendValue =>
      this == KioskOrderType.dineIn ? 'dine_in' : 'takeaway';
}

/// Self-service ordering screen: browse the menu, build a cart, pay, get a receipt - reusing the
/// exact same Convex menu/order data, `SoftPayService`, and `PrinterService` the D3 mini cashier
/// screen (`EmployeeTerminalScreen`) already uses, none of which is device-specific. [orderType]
/// (Dine In/Take Out, chosen on `KioskScreen`) is shown in the header/on the receipt AND now
/// actually sent to the backend as `orders:createDeviceOrder`'s `orderType`.
class KioskMenuScreen extends StatefulWidget {
  const KioskMenuScreen({super.key, required this.orderType});

  final KioskOrderType orderType;

  @override
  State<KioskMenuScreen> createState() => _KioskMenuScreenState();
}

class _KioskMenuScreenState extends State<KioskMenuScreen> {
  // Every restaurant on this backend is Swedish - same as the cashier screen.
  static const _currency = 'SEK';

  // How long this screen (menu/cart) can sit untouched before the "are you still there?" prompt
  // shows, and how long that prompt itself waits for a response before giving up. Deliberately
  // not applied on KioskScreen (the Dine In/Take Out start screen) - that screen already *is*
  // the idle state, there's nothing to time out back to from there.
  static const _idleTimeout = Duration(seconds: 60);
  static const _idlePromptCountdown = Duration(seconds: 10);

  final _menuRepository = MenuRepository.instance;
  final _orders = OrderRepository.instance;
  final _softPay = SoftPayService.instance;
  final _printer = PrinterService.instance;

  List<MenuCategory>? _categories;
  String? _menuError;
  SubscriptionHandle? _menuSubscription;
  final Map<String, CartEntry> _cart = {};
  _KioskView _view = _KioskView.menu;

  StreamSubscription<PaymentStatusUpdate>? _statusSubscription;
  PaymentPanelStage? _paymentStage;
  String? _paymentDetail;
  String? _activeAmountLabel;

  Timer? _idleTimer;
  bool _idlePromptShowing = false;

  // See EmployeeTerminalScreen's identical flag for the full reasoning: _paymentStage alone
  // isn't set until partway through _charge() (after the connectivity check and order-creation
  // await), so a rapid double-tap on Pay during that window could otherwise create two separate
  // orders and fire two real SoftPay charges - even more likely on a kiosk than a staff
  // terminal, since there's no cashier to notice a stuck/duplicate touch event. Set
  // synchronously before any await, so no re-entrant call can slip through.
  bool _isChargeInFlight = false;

  bool get _isCharging => _paymentStage != null || _isChargeInFlight;

  String get _orderTypeLabel =>
      widget.orderType == KioskOrderType.dineIn ? 'Dine In' : 'Take Out';

  @override
  void initState() {
    super.initState();
    _subscribeMenu();
    _resetIdleTimer();
  }

  // Paused while charging (a customer tapping/inserting a card isn't "touching the screen", and
  // a payment mid-flight shouldn't be interrupted by this) or while the prompt itself is already
  // showing (its own countdown is the one that matters at that point).
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_isCharging || _idlePromptShowing) return;
    _idleTimer = Timer(_idleTimeout, _showIdlePrompt);
  }

  Future<void> _showIdlePrompt() async {
    if (!mounted || _isCharging) return;
    setState(() => _idlePromptShowing = true);
    final stillThere = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _AreYouStillThereDialog(countdown: _idlePromptCountdown),
    );
    if (!mounted) return;
    setState(() => _idlePromptShowing = false);
    if (stillThere == true) {
      _resetIdleTimer();
    } else {
      // No response in time - reset for the next customer, same as walking away mid-payment.
      _cart.clear();
      Navigator.of(context).pop();
    }
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${reconciled.removedItemNames.join(', ')} just sold out and ${reconciled.removedItemNames.length == 1 ? 'was' : 'were'} removed from your order.',
                ),
                duration: const Duration(seconds: 6),
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

  int get _itemCount =>
      _cart.values.fold(0, (sum, entry) => sum + entry.quantity);

  Future<void> _addToCart(MenuItem item) async {
    if (_isCharging) return;
    var selectedAddons = const <MenuItemAddon>[];
    if (item.addons.isNotEmpty) {
      final picked = await showAddonPickerSheet(context, item: item);
      if (picked == null) return; // Dismissed without confirming.
      selectedAddons = picked;
    }
    final draft = CartEntry(
      item: item,
      quantity: 1,
      selectedAddons: selectedAddons,
    );
    setState(() {
      final existing = _cart[draft.cartKey];
      _cart[draft.cartKey] = draft.copyWith(
        quantity: (existing?.quantity ?? 0) + 1,
      );
    });
  }

  void _incrementLine(CartEntry entry) {
    if (_isCharging) return;
    setState(
      () => _cart[entry.cartKey] = entry.copyWith(quantity: entry.quantity + 1),
    );
  }

  void _decrementLine(CartEntry entry) {
    if (_isCharging) return;
    setState(() {
      if (entry.quantity <= 1) {
        _cart.remove(entry.cartKey);
      } else {
        _cart[entry.cartKey] = entry.copyWith(quantity: entry.quantity - 1);
      }
    });
  }

  void _removeLine(CartEntry entry) {
    if (_isCharging) return;
    setState(() => _cart.remove(entry.cartKey));
  }

  Future<void> _charge() async {
    if (_totalCents <= 0 || _isCharging) return;
    _isChargeInFlight =
        true; // Set synchronously, before any await - see the flag's doc comment.
    try {
      await _runCharge();
    } finally {
      _isChargeInFlight = false;
    }
  }

  Future<void> _runCharge() async {
    // Same freshness guard as the cashier screen: the continuous ConnectivityService already
    // keeps ConnectivityBanner live, but this forces one more up-to-the-moment check right when
    // the customer taps Pay.
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

    // The idle-timeout prompt has no business interrupting an in-flight payment.
    _idleTimer?.cancel();

    final cartSnapshot = _cart.values.toList();

    // The order must be created (and its server-computed total known) BEFORE charging anything -
    // that server total, never this screen's own cart sum, is what gets passed to
    // SoftPayService.charge() below (see EmployeeTerminalScreen._charge for the full reasoning).
    // No cashier is present at a kiosk to notice a wrong amount, which makes this even more
    // important here than on the staff terminal - if Convex can't be reached, the charge simply
    // does not happen.
    final String orderId;
    final int chargeAmountCents;
    try {
      final result = await _orders.createOrder(
        idempotencyKey: const Uuid().v4(),
        items: cartSnapshot.map((entry) => entry.toDeviceCartItem()).toList(),
        fulfillmentType: 'asap',
        orderType: widget.orderType.backendValue,
        paymentMethod: 'card',
        customerName: 'Kiosk guest',
      );
      orderId = result.orderId;
      chargeAmountCents = result.totalCents;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(e, action: 'starting this order'),
            ),
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
          _paymentDetail =
              update.stage == PaymentStage.processing && update.detail != null
              ? friendlySoftPayProcessingUpdate(update.detail!)
              : update.detail;
        });
      }
    });

    TransactionResult? transaction;
    try {
      transaction = await _softPay.charge(
        amountMinor: chargeAmountCents,
        currency: _currency,
      );
      // Awaited (not fire-and-forget) so the report is durably queued to disk - see
      // OrderEventOutbox - before this screen moves on. No cashier is present at a kiosk to
      // notice a lost report, which makes this even more important here than on the staff
      // terminal.
      await _orders.recordPaymentSuccess(
        orderId: orderId,
        transaction: toTransactionSnapshot(transaction),
      );
      if (mounted) {
        setState(() {
          _paymentStage = PaymentPanelStage.approved;
          _paymentDetail = transaction!.cardScheme == null
              ? amountLabel
              : '${transaction.cardScheme} · $amountLabel';
        });
      }
    } on SoftPayException catch (e) {
      // See EmployeeTerminalScreen._charge for why TRANSACTION_INCOMPLETE gets its own
      // "unconfirmed" state instead of being coerced into failed.
      final isUnconfirmed = e.code == 'TRANSACTION_INCOMPLETE';
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
    } catch (e) {
      // Anything other than a SoftPayException (e.g. a Convex failure while recording the
      // result) must still land on a terminal state - otherwise the kiosk is stuck showing the
      // in-progress animation forever, with no cashier present to intervene.
      await _orders.recordPaymentFailure(
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
    } finally {
      await _statusSubscription?.cancel();
      _statusSubscription = null;
    }

    if (transaction != null) {
      // Auto-print: there's no cashier here to tap a print button. A printer failure is logged,
      // not surfaced - a kiosk customer can't act on it either way.
      try {
        await _printer.printReceipt(
          items: cartSnapshot
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
          orderReference: orderId,
          logoBytes: DeviceIdentityService.instance.logoBytes,
          headerText: DeviceIdentityService.instance.receiptConfig?.headerText,
          footerText: DeviceIdentityService.instance.receiptConfig?.footerText,
        );
      } on PrinterException catch (e) {
        debugPrint('Kiosk receipt not printed: ${e.code} ${e.message}');
      }
    }

    // Leave the settled animation on screen for a moment - same pattern as the customer
    // display's self-reset - then clear the cart and hand the kiosk back to the start screen
    // for the next customer.
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      if (_paymentStage == PaymentPanelStage.approved) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _paymentStage = null;
        _paymentDetail = null;
        _activeAmountLabel = null;
      });
      _resetIdleTimer();
    }
  }

  Future<void> _cancelCharge() => _softPay.cancelCharge();

  @override
  void dispose() {
    _idleTimer?.cancel();
    _statusSubscription?.cancel();
    _menuSubscription?.cancel();
    super.dispose();
  }

  static const _horizontalPadding = EdgeInsets.symmetric(horizontal: 20);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      // Any touch anywhere on this screen resets the idle timer - a dialog shown via showDialog
      // renders in the Overlay, outside this subtree, so its own button explicitly calls
      // _resetIdleTimer() itself rather than relying on this Listener catching it.
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetIdleTimer(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _KioskBrandHeader(),
              Padding(
                padding: _horizontalPadding.copyWith(top: 12),
                child: const ConnectivityBanner(),
              ),
              Expanded(
                child: _isCharging
                    ? Padding(
                        padding: _horizontalPadding,
                        child: _KioskCheckoutPanel(
                          stage: _paymentStage!,
                          amountLabel:
                              _activeAmountLabel ??
                              '${(_totalCents / 100).toStringAsFixed(2)} $_currency',
                          detail: _paymentDetail,
                          onCancel: _cancelCharge,
                        ),
                      )
                    : _view == _KioskView.cart
                    ? Padding(
                        padding: _horizontalPadding,
                        child: _KioskCartView(
                          cart: _cart.values.toList(),
                          totalCents: _totalCents,
                          currency: _currency,
                          onIncrement: _incrementLine,
                          onDecrement: _decrementLine,
                          onRemove: _removeLine,
                          onBackToMenu: () =>
                              setState(() => _view = _KioskView.menu),
                          onPay: _charge,
                        ),
                      )
                    // Deliberately not padded - the banner/category rail inside need to reach
                    // the screen edges; _KioskMenuView pads its own item grid internally instead.
                    : _KioskMenuView(
                        categories: _categories,
                        error: _menuError,
                        cart: _cart,
                        onTap: _addToCart,
                        onRetry: _subscribeMenu,
                        onBack: () => Navigator.of(context).pop(),
                        orderTypeLabel: _orderTypeLabel,
                      ),
              ),
              if (!_isCharging && _view == _KioskView.menu && _itemCount > 0)
                Padding(
                  padding: _horizontalPadding.copyWith(bottom: 16, top: 16),
                  child: _KioskCartBar(
                    cart: _cart.values.toList(),
                    totalCents: _totalCents,
                    currency: _currency,
                    onTap: () => setState(() => _view = _KioskView.cart),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent top brand bar - restaurant logo (same bytes the receipt printer uses, see
/// `DeviceIdentityService.logoBytes`) + name, matching the reference's own top-left
/// logo/wordmark. Shown across every view of this screen (menu/cart/checkout), not just the
/// menu grid, since it's the kiosk's own constant branding, not part of the ordering flow.
class _KioskBrandHeader extends StatelessWidget {
  const _KioskBrandHeader();

  // Fixed footprint for the logo, matching the reference's own strictly-sized logo mark - no
  // restaurant-name text alongside it (a logo image is expected to already read as the brand on
  // its own, the way the reference's own wordmark-baked-into-the-logo does). Height is the hard
  // constraint (matching the reference); width just caps how wide a non-square logo can get
  // rather than forcing one - `BoxFit.cover` previously squashed/stretched any logo that wasn't
  // already a perfect square into this box, which read as broken.
  static const _size = 56.0;
  static const _maxWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      // Left-anchored rather than stretching to the header row's full width (its parent Column
      // uses CrossAxisAlignment.stretch) - the logo should sit on the left only, at its own
      // natural size, not spread across the row.
      child: Align(
        alignment: Alignment.centerLeft,
        // Rebuilds whenever a manager uploads/changes the kiosk's own header logo live - see
        // `DeviceIdentityService.remoteConfigVersion`.
        child: ValueListenableBuilder<int>(
          valueListenable: DeviceIdentityService.instance.remoteConfigVersion,
          builder: (context, _, _) {
            final bytes = DeviceIdentityService.instance.kioskHeaderLogoBytes;
            return ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _maxWidth,
                maxHeight: _size,
              ),
              child: bytes != null
                  ? Image.memory(
                      bytes,
                      height: _size,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.storefront_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: _size,
                      ),
                    )
                  : Icon(
                      Icons.storefront_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: _size,
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Ordering screen layout matching the "Kiosk Design" reference in structure - a persistent left
/// sidebar of category icons (real data now, see `MenuRepository`/`MenuCategory`, unlike the
/// earlier decorative category rail this replaced) floating over a light page background, a bold
/// category title, a big featured "hero" tile paired with two small tiles at the top of whichever
/// category is selected, and a plain borderless grid for the rest - photos/names sit directly on
/// the page background, no card container, matching that reference's own minimal item styling.
/// NorrOne's own accent/branding throughout rather than the reference's (a real, unrelated
/// restaurant chain's) logo/photography.
class _KioskMenuView extends StatefulWidget {
  const _KioskMenuView({
    required this.categories,
    required this.error,
    required this.cart,
    required this.onTap,
    required this.onRetry,
    required this.onBack,
    required this.orderTypeLabel,
  });

  /// Null until the initial `menu:listForDevice` subscription result
  /// arrives; kept live-updated for the whole lifetime of this screen
  /// (see `_KioskMenuScreenState._subscribeMenu`) rather than re-fetched.
  final List<MenuCategory>? categories;
  final String? error;
  final Map<String, CartEntry> cart;
  final ValueChanged<MenuItem> onTap;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final String orderTypeLabel;

  @override
  State<_KioskMenuView> createState() => _KioskMenuViewState();
}

class _KioskMenuViewState extends State<_KioskMenuView> {
  // Null means "All" - every category's items, flattened.
  String? _selectedCategoryId;
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
  }

  // Null-safe lookup - the previously-selected category can vanish from underneath the
  // customer (staff deletes/deactivates it on the dashboard mid-browse, and the live
  // `menu:listForDevice` push no longer includes it), in which case `_selectedCategoryId`
  // itself is now stale. Returns null both when nothing's selected AND when the selected id no
  // longer exists - `build()` resets the stale id back to "All" in the latter case.
  MenuCategory? _selectedCategory(List<MenuCategory> categories) {
    final id = _selectedCategoryId;
    if (id == null) return null;
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    final selectedCategory = categories == null
        ? null
        : _selectedCategory(categories);
    if (categories != null &&
        _selectedCategoryId != null &&
        selectedCategory == null) {
      // The selected category no longer exists - fall back to "All" rather than crashing on
      // the next `firstWhere` below. Scheduled for after this frame since `build()` can't call
      // `setState` synchronously; only fires once, since the mismatch this checks for is gone
      // as soon as `_selectedCategoryId` becomes null.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedCategoryId = null);
      });
    }
    return Container(
      // Follows this restaurant's own configured appearance (kiosk-specific override, or the
      // shared one - see ThemeController/devices:whoAmI) instead of a hardcoded fixed color.
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KioskSidebar(
            categories: categories ?? const [],
            selectedCategoryId: _selectedCategoryId,
            onSelect: (id) => setState(() {
              _selectedCategoryId = id;
              _closeSearch();
            }),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _KioskMenuHeader(
                    title: categories == null
                        ? ''
                        : (selectedCategory?.name ?? 'All'),
                    orderTypeLabel: widget.orderTypeLabel,
                    onBack: widget.onBack,
                    searching: _searching,
                    searchController: _searchController,
                    onSearchToggle: () {
                      if (_searching) {
                        _closeSearch();
                      } else {
                        setState(() => _searching = true);
                      }
                    },
                    onSearchChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _buildBody(context, categories)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<MenuCategory>? categories) {
    if (categories == null) {
      if (widget.error != null) {
        return ErrorState(message: widget.error!, onRetry: widget.onRetry);
      }
      return const Center(child: CircularProgressIndicator());
    }
    final selectedCategory = _selectedCategory(categories);
    var items = selectedCategory == null
        ? categories.expand((category) => category.items).toList()
        : selectedCategory.items;
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      items = items
          .where((item) => item.name.toLowerCase().contains(query))
          .toList();
    }
    if (items.isEmpty) {
      return EmptyState(
        icon: query.isNotEmpty
            ? Icons.search_off_rounded
            : Icons.restaurant_menu,
        message: query.isNotEmpty
            ? 'No items match "$_query"'
            : 'No menu items found',
      );
    }
    // Summed across every addon-combo line for the same item - see the identical
    // comment on the cashier screen's own quantities map. Sold-out items are always
    // kept in this list (never filtered out) - `_KioskItemImage` grays them out and
    // disables the tap target instead, so a customer can see what's temporarily
    // unavailable rather than the menu just silently shrinking.
    final quantities = <String, int>{};
    for (final entry in widget.cart.values) {
      quantities[entry.item.id] =
          (quantities[entry.item.id] ?? 0) + entry.quantity;
    }
    Widget tileFor(MenuItem item) => _KioskGridTile(
      item: item,
      quantityInCart: quantities[item.id] ?? 0,
      onTap: () => widget.onTap(item),
    );
    // The reference's own asymmetric top-of-category layout - two small tiles stacked
    // in the first column beside one big featured tile - only makes sense with a
    // full, unfiltered category (search results and tiny categories fall back to a
    // plain grid instead).
    final showFeatured = query.isEmpty && items.length >= 3;
    final small = showFeatured ? items.sublist(0, 2) : const <MenuItem>[];
    final hero = showFeatured ? items[2] : null;
    final rest = showFeatured ? items.sublist(3) : items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.error != null)
          _MenuErrorBanner(message: widget.error!, onRetry: widget.onRetry),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (hero != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    // The hero card's own vector shape (`_KioskHeroBlobClipper`) has a fixed
                    // aspect ratio (540:836, from the design it was traced from) - rather than
                    // force it into an arbitrary rectangle and crop/stretch it to fit (what
                    // caused the squish/crop before), compute this block's height FROM the
                    // hero's actual rendered width, so the card is always shown at its true
                    // proportions and never needs to crop.
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const heroFlex = 3, smallFlex = 2, gap = 16.0;
                        final heroWidth =
                            (constraints.maxWidth - gap) *
                            heroFlex /
                            (heroFlex + smallFlex);
                        final heroHeight =
                            heroWidth * _KioskHeroTile.heightOverWidth;
                        return SizedBox(
                          height: heroHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: heroFlex,
                                child: _KioskHeroTile(
                                  item: hero,
                                  quantityInCart: quantities[hero.id] ?? 0,
                                  onTap: () => widget.onTap(hero),
                                ),
                              ),
                              const SizedBox(width: gap),
                              Expanded(
                                flex: smallFlex,
                                child: Column(
                                  children: [
                                    Expanded(child: tileFor(small[0])),
                                    const SizedBox(height: 16),
                                    Expanded(child: tileFor(small[1])),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (rest.isNotEmpty)
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => tileFor(rest[index]),
                    childCount: rest.length,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Plain header row - back button, bold category title (or an expanded search field in its
/// place), a subtle order-type chip, and the search toggle. No banner/pill treatment - this
/// design has no top banner at all, just the title sitting directly on the page.
class _KioskMenuHeader extends StatelessWidget {
  const _KioskMenuHeader({
    required this.title,
    required this.orderTypeLabel,
    required this.onBack,
    required this.searching,
    required this.searchController,
    required this.onSearchToggle,
    required this.onSearchChanged,
  });

  final String title;
  final String orderTypeLabel;
  final VoidCallback onBack;
  final bool searching;
  final TextEditingController searchController;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Cancel order',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: searching
              ? TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search menu…',
                    filled: true,
                    fillColor: scheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                )
              : Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        if (!searching)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              orderTypeLabel,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onSearchToggle,
          icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded),
          tooltip: searching ? 'Close search' : 'Search menu',
        ),
      ],
    );
  }
}

/// Persistent left sidebar of category icons, matching the reference's own floating white nav -
/// real `MenuCategory` data now (this replaced a purely decorative horizontal rail that had no
/// backing data to filter by). A synthetic leading "All" entry (no `MenuCategory` behind it)
/// covers what the reference doesn't show a control for.
class _KioskSidebar extends StatelessWidget {
  const _KioskSidebar({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelect,
  });

  final List<MenuCategory> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Matches the real spec's menu column width (156px) exactly - was too narrow before to
      // comfortably fit a 60px icon (per the spec) plus a readable label.
      width: 156,
      margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView(
        children: [
          _SidebarButton(
            emoji: null,
            fallbackIcon: Icons.apps_rounded,
            label: 'All',
            selected: selectedCategoryId == null,
            onTap: () => onSelect(null),
          ),
          for (final category in categories)
            _SidebarButton(
              emoji: _emojiFor(category.icon),
              fallbackIcon: Icons.restaurant_menu_rounded,
              label: category.name,
              selected: selectedCategoryId == category.id,
              onTap: () => onSelect(category.id),
            ),
        ],
      ),
    );
  }

  // Categories carry a free-text `icon` field from the dashboard - in practice a single emoji
  // glyph, not a Material icon name - so render it directly when it's short enough to plausibly
  // be one, falling back to a generic dish icon for anything else (empty, or a longer label).
  String? _emojiFor(String? icon) {
    final trimmed = icon?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.characters.length > 2) {
      return null;
    }
    return trimmed;
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.emoji,
    required this.fallbackIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String? emoji;
  final IconData fallbackIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (selected) const Positioned.fill(child: _KioskSidebarBlob()),
            // Icon (60px) + label sizing matches the real spec's 60x60 icon / 20px label exactly
            // (pulled via get_design_context) - was noticeably undersized before.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  SizedBox(
                    height: 60,
                    child: Center(
                      child: emoji != null
                          ? Text(emoji!, style: const TextStyle(fontSize: 40))
                          : Icon(
                              fallbackIcon,
                              size: 32,
                              color: selected ? color : scheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected ? color : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reference design's own quatrefoil blob shape (`assets/kiosk_sidebar_blob.svg`, a solid
/// silhouette - the gradient itself is applied here, not baked into the SVG), shown behind a
/// selected sidebar category. Tinted with this restaurant's own configured accent color (fading
/// to the card surface) via [ShaderMask], rather than a fixed brand color, so it follows whatever
/// accent the whole app is themed with (see kiosk appearance/`ThemeController`).
class _KioskSidebarBlob extends StatelessWidget {
  const _KioskSidebarBlob();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [scheme.primary, scheme.surface],
      ).createShader(bounds),
      child: SvgPicture.asset(
        'assets/kiosk_sidebar_blob.svg',
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Small "+ price" pill button used on both the hero tile and the plain grid tiles - the
/// reference's own add-to-cart affordance. The whole tile is still the tap target (matching how
/// `DishTile` works on the cashier screen) rather than making this pill a second, separate
/// target - simpler and consistent with the rest of the app.
class _AddToCartPill extends StatelessWidget {
  const _AddToCartPill({required this.priceCents, this.large = false});

  final int priceCents;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = large
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.labelLarge;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 20 : 12,
        vertical: large ? 12 : 6,
      ),
      decoration: BoxDecoration(
        // Matches the real spec: the hero tile's pill is white ("button/main/tertiary/normal"),
        // the small grid tiles' pill is light grey ("button/main/secondary/normal") - not the
        // same color at both sizes. The large pill gets a soft shadow since it otherwise sits on
        // the hero card's own near-white gradient fade and would have no visible edge.
        color: large ? scheme.surface : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        boxShadow: large
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: large ? 20 : 16),
          SizedBox(width: large ? 8 : 4),
          Text(
            '${(priceCents / 100).toStringAsFixed(2)} SEK',
            style: style?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Big featured tile paired with the two small tiles beside it at the top of a category - the
/// reference's own vertical layout: photo overflowing the top of a soft gradient card, name +
/// description + a large "+ price" pill underneath, with a two-shape gradient blob behind the
/// photo.
class _KioskHeroTile extends StatelessWidget {
  const _KioskHeroTile({
    required this.item,
    required this.quantityInCart,
    required this.onTap,
  });

  final MenuItem item;
  final int quantityInCart;
  final VoidCallback onTap;

  /// The design's own fixed proportions (540:836, traced straight from the reference SVG) - the
  /// caller (`_buildBody`) sizes this tile's box to this ratio up front, so it's never squished
  /// or cropped to fit an unrelated rectangle.
  static const heightOverWidth = 836 / 540;

  @override
  Widget build(BuildContext context) {
    final available = item.isInStock;
    // ClipPath wraps the InkWell (rather than the other way around) so the ripple itself is
    // clipped to the design's real silhouette too, not just the static content underneath it.
    return ClipPath(
      clipper: const _KioskHeroBlobClipper(),
      child: InkWell(
        onTap: available ? onTap : null,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _KioskHeroBlob(),
              // Matches the real Figma spec exactly (pulled via get_design_context on the
              // duplicated file): the photo and text sit in plain, non-overflowing box flow
              // inside 48px padding on a 540px-wide card (~8.9%, scaled to whatever width this
              // tile actually renders at) - no absolute positioning/negative-margin overflow
              // trick needed. The photo is a plain square (`AspectRatio(1)`) sized to the
              // padded content width, and the text block below is left-aligned, not centered.
              LayoutBuilder(
                builder: (context, constraints) {
                  final padding = constraints.maxWidth * (48 / 540);
                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: _KioskItemImage(
                            item: item,
                            available: available,
                            quantityInCart: quantityInCart,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (item.description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                item.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: 16),
                            _AddToCartPill(
                              priceCents: item.priceCents,
                              large: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The exact vector outline of `assets/kiosk_hero_blob.svg` (traced by hand from its path data),
/// used both to clip the card's content to the design's real silhouette (not an approximating
/// rounded rectangle - see [_KioskHeroTile]) and as its ink-splash shape. Scales the path's own
/// 540x836 coordinate space uniformly to whatever [Size] it's asked to clip, which is always
/// exactly proportioned (see `_KioskHeroTile.heightOverWidth`) so this never has to stretch.
class _KioskHeroBlobClipper extends CustomClipper<Path> {
  const _KioskHeroBlobClipper();

  static const _designWidth = 540.0;
  static const _designHeight = 836.0;

  @override
  Path getClip(Size size) {
    final sx = size.width / _designWidth;
    final sy = size.height / _designHeight;
    double x(double v) => v * sx;
    double y(double v) => v * sy;
    return Path()
      ..moveTo(x(270), y(135))
      ..cubicTo(x(270), y(60.4416), x(209.558), y(0), x(135), y(0))
      ..cubicTo(x(60.4416), y(0), x(0), y(60.4416), x(0), y(135))
      ..cubicTo(x(0), y(185.913), x(28.1836), y(230.243), x(69.8004), y(253.24))
      ..cubicTo(
        x(47.1121),
        y(267.595),
        x(28.6148),
        y(287.828),
        x(16.349),
        y(311.901),
      )
      ..cubicTo(x(0), y(343.988), x(0), y(385.992), x(0), y(470))
      ..lineTo(x(0), y(740))
      ..cubicTo(x(0), y(773.603), x(0), y(790.405), x(6.53961), y(803.239))
      ..cubicTo(
        x(12.292),
        y(814.529),
        x(21.4708),
        y(823.708),
        x(32.7606),
        y(829.46),
      )
      ..cubicTo(x(45.5953), y(836), x(62.3968), y(836), x(96), y(836))
      ..lineTo(x(444), y(836))
      ..cubicTo(x(477.603), y(836), x(494.405), y(836), x(507.239), y(829.46))
      ..cubicTo(
        x(518.529),
        y(823.708),
        x(527.708),
        y(814.529),
        x(533.46),
        y(803.239),
      )
      ..cubicTo(x(540), y(790.405), x(540), y(773.603), x(540), y(740))
      ..lineTo(x(540), y(470))
      ..cubicTo(x(540), y(385.992), x(540), y(343.988), x(523.651), y(311.901))
      ..cubicTo(
        x(511.385),
        y(287.828),
        x(492.888),
        y(267.595),
        x(470.2),
        y(253.24),
      )
      ..cubicTo(x(511.816), y(230.243), x(540), y(185.913), x(540), y(135))
      ..cubicTo(x(540), y(60.4416), x(479.558), y(0), x(405), y(0))
      ..cubicTo(x(330.442), y(0), x(270), y(60.4416), x(270), y(135))
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// The hero card's own background (`assets/kiosk_hero_blob.svg`, a solid silhouette - same
/// reasoning as `_KioskSidebarBlob`: the gradient is applied here via [ShaderMask], tinted with
/// this restaurant's own configured accent color rather than a fixed brand color). Uses
/// `BoxFit.cover` (crops, never distorts) rather than `BoxFit.fill` - the asset's own aspect
/// ratio (a tall portrait card) doesn't match this hero tile's wide, short one, and stretching it
/// non-uniformly to fill exactly squished the shape.
class _KioskHeroBlob extends StatelessWidget {
  const _KioskHeroBlob();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [scheme.primary, scheme.surface],
      ).createShader(bounds),
      // `fill` is safe here (never distorts) because the tile is always laid out at the design's
      // own 540:836 ratio (see `_KioskHeroTile.heightOverWidth`), and `_KioskHeroBlobClipper`
      // clips to that exact same shape/scale regardless.
      child: SvgPicture.asset('assets/kiosk_hero_blob.svg', fit: BoxFit.fill),
    );
  }
}

/// Plain grid tile - no card/border/background, matching the reference exactly: the photo just
/// sits on the page.
class _KioskGridTile extends StatelessWidget {
  const _KioskGridTile({
    required this.item,
    required this.quantityInCart,
    required this.onTap,
  });

  final MenuItem item;
  final int quantityInCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = item.isInStock;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: available ? onTap : null,
      child: Opacity(
        opacity: available ? 1 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _KioskItemImage(
                item: item,
                available: available,
                quantityInCart: quantityInCart,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            available
                ? _AddToCartPill(priceCents: item.priceCents)
                : const _SoldOutPill(),
          ],
        ),
      ),
    );
  }
}

/// Shared image area for both tile types - the real photo (`item.imageUrl`) when set, same as
/// `DishTile` on the cashier screen, falling back to a placeholder icon otherwise. [blob] draws
/// the reference's two-shape gradient blob behind it (hero tile only); the plain grid tiles have
/// no background at all behind the image, per the design.
class _KioskItemImage extends StatelessWidget {
  const _KioskItemImage({
    required this.item,
    required this.available,
    required this.quantityInCart,
  });

  final MenuItem item;
  final bool available;
  final int quantityInCart;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final imageUrl = item.imageUrl;
    final image = imageUrl != null
        ? Image.network(
            imageUrl,
            fit: BoxFit.contain,
            color: available ? null : Colors.black26,
            colorBlendMode: available ? null : BlendMode.saturation,
            errorBuilder: (context, error, stackTrace) => _fallbackIcon(accent),
          )
        : _fallbackIcon(accent);

    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        image,
        if (quantityInCart > 0)
          Positioned(
            top: 0,
            right: 0,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: accent,
              child: Text(
                '$quantityInCart',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (!available) const Center(child: _SoldOutPill()),
      ],
    );
  }

  Widget _fallbackIcon(Color accent) {
    return Center(
      child: Icon(
        Icons.ramen_dining_rounded,
        color: available ? accent : Colors.black26,
        size: 40,
      ),
    );
  }
}

/// "Sold out" badge - shown centered over a dimmed photo on tiles ([_KioskItemImage]) and in
/// place of the add-to-cart pill on the plain grid tile, so an out-of-stock item stays visible
/// on the menu (never silently hidden) but is unmistakably not tappable.
class _SoldOutPill extends StatelessWidget {
  const _SoldOutPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Sold out',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Colors.white),
      ),
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

/// Bottom cart bar matching the reference exactly: a stack of overlapping circular previews of
/// what's in the cart on the left, a solid-accent pill with a receipt icon + running total on
/// the right that opens the cart view.
class _KioskCartBar extends StatelessWidget {
  const _KioskCartBar({
    required this.cart,
    required this.totalCents,
    required this.currency,
    required this.onTap,
  });

  final List<CartEntry> cart;
  final int totalCents;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = cart.take(3).toList();
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            width: 28.0 + preview.length * 28,
            child: Stack(
              children: [
                for (var i = 0; i < preview.length; i++)
                  Positioned(
                    left: i * 28,
                    child: _CartPreviewAvatar(entry: preview[i]),
                  ),
                if (cart.length > preview.length)
                  Positioned(
                    left: preview.length * 28,
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                      child: Text(
                        '+${cart.length - preview.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Material(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    '${(totalCents / 100).toStringAsFixed(2)} $currency',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartPreviewAvatar extends StatelessWidget {
  const _CartPreviewAvatar({required this.entry});

  final CartEntry entry;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final imageUrl = entry.item.imageUrl;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.ramen_dining_rounded, color: accent),
            )
          : Icon(Icons.ramen_dining_rounded, color: accent),
    );
  }
}

class _KioskCartView extends StatelessWidget {
  const _KioskCartView({
    required this.cart,
    required this.totalCents,
    required this.currency,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onBackToMenu,
    required this.onPay,
  });

  final List<CartEntry> cart;
  final int totalCents;
  final String currency;
  final ValueChanged<CartEntry> onIncrement;
  final ValueChanged<CartEntry> onDecrement;
  final ValueChanged<CartEntry> onRemove;
  final VoidCallback onBackToMenu;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBackToMenu,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back to menu',
            ),
            Text('Confirmation', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: cart.isEmpty
              ? const EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  message: 'Your cart is empty',
                )
              : ListView.separated(
                  itemCount: cart.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final entry = cart[index];
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (entry.selectedAddons.isNotEmpty)
                                Text(
                                  entry.selectedAddons
                                      .map((addon) => addon.name)
                                      .join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              Text(
                                '${(entry.item.priceCents / 100).toStringAsFixed(2)} $currency',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
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
                                onPressed: () => onDecrement(entry),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('${entry.quantity}'),
                              IconButton(
                                onPressed: () => onIncrement(entry),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 72,
                          child: Text(
                            (entry.subtotalCents / 100).toStringAsFixed(2),
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: () => onRemove(entry),
                          icon: Icon(Icons.delete_outline, color: scheme.error),
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
              '${(totalCents / 100).toStringAsFixed(2)} $currency',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 60,
                child: OutlinedButton(
                  onPressed: onBackToMenu,
                  child: const Text('Cancel'),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 60,
                // Proactively disabled while offline (not just rejected with a snackbar at tap
                // time, which was the only guard before) - the kiosk should read as "browse
                // only until connectivity's back", not as a button that mysteriously does
                // nothing when pressed.
                child: ValueListenableBuilder<bool>(
                  valueListenable: ConnectivityService.instance.isOnline,
                  builder: (context, online, _) => FilledButton(
                    onPressed: cart.isEmpty || !online ? null : onPay,
                    child: Text(
                      online
                          ? 'Confirm Payment · ${(totalCents / 100).toStringAsFixed(2)} $currency'
                          : 'Checkout unavailable while offline',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Fixed breathing room below the buttons regardless of system inset - the screen's own
        // outer SafeArea already clears notches/gesture bars, but on a device with no such
        // inset (most tablets) the buttons still sat completely flush against the bottom edge,
        // which read as cramped.
        SizedBox(height: 20 + MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

/// Full-screen, big-touch checkout view - built the same way `CustomerDisplayScreen`'s
/// `_SecondaryPaymentPanel` was: amount/status stacked, a large `StageVisual` for the current
/// stage, no manual "Done" button since this self-resets (see `_charge` above).
class _KioskCheckoutPanel extends StatelessWidget {
  const _KioskCheckoutPanel({
    required this.stage,
    required this.amountLabel,
    required this.detail,
    required this.onCancel,
  });

  final PaymentPanelStage stage;
  final String amountLabel;
  final String? detail;
  final VoidCallback onCancel;

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
    final isConnecting =
        stage == PaymentPanelStage.connecting ||
        stage == PaymentPanelStage.processing;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Pay', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(amountLabel, style: theme.textTheme.displayMedium),
        if (isConnecting) ...[
          const SizedBox(height: 28),
          const _PaymentMethodCard(),
        ],
        const SizedBox(height: 32),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.maxWidth.clamp(160.0, 320.0);
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: StageVisual(
                key: ValueKey(stage),
                stage: stage,
                size: size * 0.6,
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        Text(
          _title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        if (isConnecting) ...[
          const SizedBox(height: 32),
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ],
    );
  }
}

/// Stands in for the reference's "Payment Method" method-selection box - there's only ever one
/// real option here (SoftPay's card-present tap flow, not a manual card-entry form), so this is
/// shown as a single already-selected card rather than a picker.
class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.contactless_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Text(
            'Tap to Pay',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
        ],
      ),
    );
  }
}

/// "Are you still there?" idle prompt (see `_KioskMenuScreenState._showIdlePrompt`) - a
/// non-dismissible dialog with its own countdown, separate from the screen's own idle timer.
/// Pops `true` if the customer taps the button in time, `false` (auto) if the countdown runs out.
class _AreYouStillThereDialog extends StatefulWidget {
  const _AreYouStillThereDialog({required this.countdown});

  final Duration countdown;

  @override
  State<_AreYouStillThereDialog> createState() =>
      _AreYouStillThereDialogState();
}

class _AreYouStillThereDialogState extends State<_AreYouStillThereDialog> {
  late int _secondsLeft = widget.countdown.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop(false);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.timer_outlined, size: 36),
      title: const Text('Are you still there?'),
      content: Text(
        'This order will reset in $_secondsLeft seconds if there\'s no response.',
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, I\'m still here'),
          ),
        ),
      ],
    );
  }
}

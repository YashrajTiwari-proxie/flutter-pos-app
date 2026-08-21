import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../Services/tcs/pos_payments_service.dart';
import '../../Services/tcs/tcs_models.dart';
import '../device_identity_service.dart';
import '../models/device_cart_item.dart';
import '../models/order.dart';
import '../models/transaction_snapshot.dart';
import 'order_event_outbox.dart';

/// Whether this restaurant is currently accepting orders — mirrors the exact guard
/// `orders:createDeviceOrder` itself enforces server-side (`requireOpenForOrders`, shared with
/// the online storefront's `placeOrder`), so the UI can show/disable proactively instead of
/// staff only finding out after building a cart and tapping Charge. [message] is a real,
/// human-readable sentence from the backend (e.g. "Closed today", "Outside business hours",
/// "This restaurant isn't taking orders right now") — never a code to re-translate client-side.
class OrderingStatus {
  const OrderingStatus({required this.isOpen, this.message});

  factory OrderingStatus.fromJson(Map<String, dynamic> json) => OrderingStatus(
    isOpen: json['isOpen'] as bool,
    message: json['message'] as String?,
  );

  final bool isOpen;
  final String? message;
}

/// Result of `orders:createDeviceOrder`. [totalCents] is re-derived server-side from the live
/// menu/addons/coupon/delivery-zone tables — this, not any client-side cart sum, is the amount
/// that must be passed to `SoftPayService.charge()`. Trusting a locally-computed total instead
/// would let a stale cached price, a coupon-math mismatch, or a patched client charge the wrong
/// amount with nothing on the server able to catch it after the fact.
class CreateOrderResult {
  const CreateOrderResult({
    required this.orderId,
    required this.displayId,
    this.dailyOrderNumber,
    required this.alreadyExisted,
    required this.subtotalCents,
    required this.discountCents,
    this.shippingCents,
    required this.totalCents,
  });

  factory CreateOrderResult.fromJson(Map<String, dynamic> json) =>
      CreateOrderResult(
        orderId: json['orderId'] as String,
        displayId: json['displayId'] as String,
        dailyOrderNumber: (json['dailyOrderNumber'] as num?)?.toInt(),
        alreadyExisted: json['alreadyExisted'] as bool,
        // Convex's client always serializes a whole-number float with a
        // decimal point (e.g. "2198.0", not "2198"), which Dart's jsonDecode
        // parses as double — a direct `as int` cast throws on every real
        // call. Cast through `num` first, same as Order.fromJson already
        // does — this file's own cast was the one spot that didn't.
        subtotalCents: (json['subtotalCents'] as num).toInt(),
        discountCents: (json['discountCents'] as num).toInt(),
        shippingCents: (json['shippingCents'] as num?)?.toInt(),
        totalCents: (json['totalCents'] as num).toInt(),
      );

  final String orderId;
  final String displayId;

  /// Cosmetic, resets daily per restaurant — never the fiscal record. See
  /// backend schema.ts's `orders.dailyOrderNumber` doc comment.
  final int? dailyOrderNumber;
  final bool alreadyExisted;
  final int subtotalCents;
  final int discountCents;
  final int? shippingCents;
  final int totalCents;
}

/// Device-facing order calls — every method reads the current pairing
/// token from [DeviceIdentityService] rather than taking one as an
/// argument, so callers never have to thread it through themselves.
class OrderRepository {
  OrderRepository._();

  static final OrderRepository instance = OrderRepository._();

  // Applied to every one-shot query/mutation below (never to subscribeToOrders, which is
  // long-lived by design) - without this, a Convex call that genuinely never responds (not an
  // error, a network black-hole) would leave an `await` here unresolved forever. For createOrder
  // specifically that means _isChargeInFlight/_isBusy staying true permanently - cart edits
  // blocked, Charge disabled, no Cancel button either (that's gated on a payment stage this path
  // never reaches) - with a force-restart as the only recovery. See device_repository.dart's
  // identical constant/reasoning.
  static const _timeout = Duration(seconds: 20);

  String get _deviceToken {
    final token = DeviceIdentityService.instance.token;
    if (token == null) {
      throw StateError(
        'Device is not paired — call DeviceIdentityService.pair() first',
      );
    }
    return token;
  }

  /// Live feed of this restaurant's orders (`orders:listForDevice`) — the
  /// terminal's order/payment management view subscribes to this instead of
  /// polling, same as the old `orders:list` subscription it replaces.
  Future<SubscriptionHandle> subscribeToOrders({
    required void Function(List<Order> orders) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) {
    return ConvexClient.instance.subscribe(
      name: 'orders:listForDevice',
      args: {'deviceToken': _deviceToken},
      onUpdate: (raw) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        onUpdate(
          decoded
              .map((entry) => Order.fromJson(entry as Map<String, dynamic>))
              .toList(),
        );
      },
      onError: onError,
    );
  }

  /// Live feed of whether this restaurant is currently open for orders
  /// (`restaurants:getOrderingStatusBySlug`) — proactive, so the UI can
  /// show a banner and disable Charge before staff ever builds a cart,
  /// instead of only finding out when `createOrder` rejects it. This is
  /// the same public, unauthenticated query the online storefront uses
  /// (no device token involved — restaurantSlug is enough), reused here
  /// rather than adding a device-scoped duplicate.
  Future<SubscriptionHandle> subscribeToOrderingStatus({
    required void Function(OrderingStatus status) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) {
    final restaurantSlug =
        DeviceIdentityService.instance.identity?.restaurantSlug;
    if (restaurantSlug == null) {
      throw StateError(
        'Device is not paired — call DeviceIdentityService.pair() first',
      );
    }
    return ConvexClient.instance.subscribe(
      name: 'restaurants:getOrderingStatusBySlug',
      args: {'restaurantSlug': restaurantSlug},
      onUpdate: (raw) => onUpdate(
        OrderingStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      ),
      onError: onError,
    );
  }

  /// Creates a walk-in order for this device's restaurant. `customerName`
  /// defaults to "Walk-in" server-side when omitted — there's no customer
  /// account behind a POS/kiosk/handheld order.
  Future<CreateOrderResult> createOrder({
    required String idempotencyKey,
    required List<DeviceCartItem> items,
    required String fulfillmentType,
    DateTime? scheduledFor,
    required String orderType,
    String? locationId,
    String? couponCode,
    required String paymentMethod,
    String? deliveryPostalCode,
    String? notes,
    String? customerName,
  }) async {
    final raw = await ConvexClient.instance
        .mutation(
          name: 'orders:createDeviceOrder',
          args: {
            'deviceToken': _deviceToken,
            'idempotencyKey': idempotencyKey,
            'items': items.map((item) => item.toJson()).toList(),
            'fulfillmentType': fulfillmentType,
            if (scheduledFor != null)
              'scheduledFor': scheduledFor.millisecondsSinceEpoch,
            'orderType': orderType,
            if (locationId != null) 'locationId': locationId,
            if (couponCode != null) 'couponCode': couponCode,
            'paymentMethod': paymentMethod,
            if (deliveryPostalCode != null)
              'deliveryPostalCode': deliveryPostalCode,
            if (notes != null) 'notes': notes,
            if (customerName != null) 'customerName': customerName,
          },
        )
        .timeout(_timeout);
    return CreateOrderResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  // A successful charge needs the LIVE fiscal result (to decide whether to print a receipt or
  // trigger an automatic refund), so it can't be pure fire-and-forget like the others below — see
  // reportChargeAndFiscalize's own doc comment. Failure/unconfirmed/cancellation don't fiscalize
  // (posPayments:reportEvent short-circuits for them server-side), so nothing downstream needs
  // their result — they stay fire-and-forget through the outbox, same durability guarantee as
  // before, just targeting the centralized action instead of the old per-outcome mutation.

  /// Reports a successful charge and fiscalizes it in one call. Durable (see
  /// [OrderEventOutbox.enqueueAndTryNow]) — if this returns null, the charge is still safely
  /// queued and will be retried automatically; the caller should show "payment approved,
  /// finalizing…" rather than an error, and must NOT print a receipt yet (no control code to
  /// print) or treat this as a failure (the money already moved).
  Future<PosPaymentReportResult?> reportChargeAndFiscalize({
    required String orderId,
    required int amountCents,
    required TransactionSnapshot transaction,
  }) async {
    final raw = await OrderEventOutbox.instance.enqueueAndTryNow(
      'posPayments:reportEvent',
      {
        'orderId': orderId,
        'type': 'charge',
        'amountCents': amountCents,
        'transaction': transaction.toJson(),
      },
      callType: OutboxCallType.action,
      idempotencyKey: const Uuid().v4(),
    );
    if (raw == null) return null;
    return PosPaymentReportResult.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> recordPaymentFailure({
    required String orderId,
    required String code,
    required String message,
    int? detailedCode,
  }) {
    return OrderEventOutbox.instance.enqueue('posPayments:reportEvent', {
      'orderId': orderId,
      'type': 'failure',
      'failureCode': code,
      'failureMessage': message,
    }, callType: OutboxCallType.action);
  }

  /// The SDK itself could not determine whether the charge went through (e.g. Softpay's
  /// `TRANSACTION_INCOMPLETE`). Recorded as its own distinct state — never coerced into
  /// success or failure — so staff can reconcile it manually instead of risking a silent
  /// double-charge (blind retry) or a silently-lost payment (treating it as failed).
  Future<void> recordPaymentUnconfirmed({
    required String orderId,
    String? code,
    String? message,
    int? detailedCode,
  }) {
    return OrderEventOutbox.instance.enqueue('posPayments:reportEvent', {
      'orderId': orderId,
      'type': 'unconfirmed',
      'failureCode': code ?? 'UNCONFIRMED',
      'failureMessage': message ?? 'Payment outcome could not be confirmed',
    }, callType: OutboxCallType.action);
  }

  /// Reports a refund and fiscalizes it in one call — same durability/live-result reasoning as
  /// [reportChargeAndFiscalize]. `orders:recordRefund` is retired; a refund is now a first-class
  /// `posPayments:reportEvent` outcome with its own `agentRefund`-backed fiscal row, gated by the
  /// same paid/partially_refunded check the old mutation had (now enforced server-side in
  /// posPaymentsInternal.ts's recordEvent).
  Future<PosPaymentReportResult?> reportRefundAndFiscalize({
    required String orderId,
    required int amountCents,
    String? reason,
    TransactionSnapshot? transaction,
  }) async {
    final raw = await OrderEventOutbox.instance.enqueueAndTryNow(
      'posPayments:reportEvent',
      {
        'orderId': orderId,
        'type': 'refund',
        'amountCents': amountCents,
        if (reason != null) 'reason': reason,
        if (transaction != null) 'transaction': transaction.toJson(),
      },
      callType: OutboxCallType.action,
      idempotencyKey: const Uuid().v4(),
    );
    if (raw == null) return null;
    return PosPaymentReportResult.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> recordCancellation({required String orderId}) {
    return OrderEventOutbox.instance.enqueue('posPayments:reportEvent', {
      'orderId': orderId,
      'type': 'cancellation',
    }, callType: OutboxCallType.action);
  }

  /// Requests a real, fiscalized "Kopia" copy of an order's original sale — see
  /// `PosPaymentsService.requestCopy`'s own doc comment. Returns null on failure (network, no
  /// original sale to copy, etc.); the caller must not print anything in that case.
  Future<TcsResult?> requestReceiptCopy({required String orderId}) async {
    try {
      return await PosPaymentsService.instance.requestCopy(
        deviceToken: _deviceToken,
        orderId: orderId,
      );
    } catch (_) {
      return null;
    }
  }
}

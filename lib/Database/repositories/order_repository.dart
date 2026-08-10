import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import '../device_identity_service.dart';
import '../models/device_cart_item.dart';
import '../models/order.dart';
import '../models/transaction_snapshot.dart';
import 'order_event_outbox.dart';

/// Result of `orders:createDeviceOrder`. [totalCents] is re-derived server-side from the live
/// menu/addons/coupon/delivery-zone tables — this, not any client-side cart sum, is the amount
/// that must be passed to `SoftPayService.charge()`. Trusting a locally-computed total instead
/// would let a stale cached price, a coupon-math mismatch, or a patched client charge the wrong
/// amount with nothing on the server able to catch it after the fact.
class CreateOrderResult {
  const CreateOrderResult({
    required this.orderId,
    required this.displayId,
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
        alreadyExisted: json['alreadyExisted'] as bool,
        subtotalCents: json['subtotalCents'] as int,
        discountCents: json['discountCents'] as int,
        shippingCents: json['shippingCents'] as int?,
        totalCents: json['totalCents'] as int,
      );

  final String orderId;
  final String displayId;
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
    final raw = await ConvexClient.instance.mutation(
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
    );
    return CreateOrderResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  // recordPaymentSuccess/recordPaymentFailure/recordPaymentUnconfirmed/recordRefund/
  // recordCancellation all go through OrderEventOutbox rather than calling
  // ConvexClient.instance.mutation directly: these report the real-world outcome of money that
  // may have already moved, and a plain fire-and-forget call would lose that report forever if
  // the app is killed or the network drops between the SoftPay SDK resolving and the mutation
  // reaching Convex. The outbox persists each report to disk before attempting to send it, so a
  // kill mid-flight just means it's retried on the next launch/connectivity restore, not lost.

  Future<void> recordPaymentSuccess({
    required String orderId,
    required TransactionSnapshot transaction,
  }) {
    return OrderEventOutbox.instance.enqueue('orders:recordPaymentResult', {
      'orderId': orderId,
      'outcome': 'success',
      'payment': transaction.toJson(),
    });
  }

  Future<void> recordPaymentFailure({
    required String orderId,
    required String code,
    required String message,
    int? detailedCode,
  }) {
    return OrderEventOutbox.instance.enqueue('orders:recordPaymentResult', {
      'orderId': orderId,
      'outcome': 'failed',
      'failure': {
        'code': code,
        'message': message,
        if (detailedCode != null) 'detailedCode': detailedCode,
      },
    });
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
    return OrderEventOutbox.instance.enqueue('orders:recordPaymentResult', {
      'orderId': orderId,
      'outcome': 'unconfirmed',
      if (code != null || message != null)
        'failure': {
          'code': code ?? 'UNCONFIRMED',
          'message': message ?? 'Payment outcome could not be confirmed',
          if (detailedCode != null) 'detailedCode': detailedCode,
        },
    });
  }

  Future<void> recordRefund({
    required String orderId,
    required int amountMinor,
    String? reason,
    TransactionSnapshot? transaction,
  }) {
    return OrderEventOutbox.instance.enqueue('orders:recordRefund', {
      'orderId': orderId,
      'amountMinor': amountMinor,
      if (reason != null) 'reason': reason,
      if (transaction != null) 'transaction': transaction.toJson(),
    });
  }

  Future<void> recordCancellation({required String orderId}) {
    return OrderEventOutbox.instance.enqueue('orders:recordCancellation', {
      'orderId': orderId,
    });
  }
}

import 'order_item.dart';
import 'order_payment_event.dart';

/// A restaurant order, as returned by `orders:listForDevice`. Two
/// deliberately separate lifecycle fields (matching the backend's
/// schema.ts): [status] is the kitchen workflow
/// (pending/cooking/packing/ready/completed/cancelled), [paymentStatus] is
/// the payment lifecycle — a free-text field by backend convention, not an
/// enum, populated as pending/paid/failed/refunded/partially_refunded by
/// orders.ts's device-facing mutations. A single order can carry more than
/// one [paymentEvents] entry (e.g. two partial refunds), which is why
/// refund/failure detail lives in that list rather than as single fields.
class Order {
  const Order({
    required this.id,
    required this.restaurantId,
    this.locationId,
    required this.orderNumber,
    required this.displayId,
    this.dailyOrderNumber,
    this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    this.couponCode,
    required this.subtotalCents,
    required this.discountCents,
    this.shippingCents,
    required this.totalCents,
    required this.fulfillmentType,
    this.scheduledFor,
    required this.orderType,
    required this.isInKitchen,
    this.kitchenStartedAt,
    this.idempotencyKey,
    required this.placedAt,
    this.pickedUpAt,
    this.notes,
    this.placedByDeviceId,
    required this.items,
    required this.paymentEvents,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    DateTime? millis(String key) {
      final value = json[key] as num?;
      return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    return Order(
      id: json['_id'] as String,
      restaurantId: json['restaurantId'] as String,
      locationId: json['locationId'] as String?,
      orderNumber: (json['orderNumber'] as num).toInt(),
      displayId: json['displayId'] as String,
      dailyOrderNumber: (json['dailyOrderNumber'] as num?)?.toInt(),
      customerId: json['customerId'] as String?,
      customerName: json['customerName'] as String,
      customerEmail: json['customerEmail'] as String?,
      customerPhone: json['customerPhone'] as String?,
      status: json['status'] as String,
      paymentStatus: json['paymentStatus'] as String,
      paymentMethod: json['paymentMethod'] as String,
      couponCode: json['couponCode'] as String?,
      subtotalCents: (json['subtotalCents'] as num).toInt(),
      discountCents: (json['discountCents'] as num).toInt(),
      shippingCents: (json['shippingCents'] as num?)?.toInt(),
      totalCents: (json['totalCents'] as num).toInt(),
      fulfillmentType: json['fulfillmentType'] as String,
      scheduledFor: millis('scheduledFor'),
      orderType: json['orderType'] as String,
      isInKitchen: json['isInKitchen'] as bool? ?? false,
      kitchenStartedAt: millis('kitchenStartedAt'),
      idempotencyKey: json['idempotencyKey'] as String?,
      placedAt: DateTime.fromMillisecondsSinceEpoch((json['placedAt'] as num).toInt()),
      pickedUpAt: millis('pickedUpAt'),
      notes: json['notes'] as String?,
      placedByDeviceId: json['placedByDeviceId'] as String?,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((entry) => OrderItem.fromJson(entry as Map<String, dynamic>))
          .toList(),
      paymentEvents: (json['paymentEvents'] as List<dynamic>? ?? const [])
          .map((entry) => OrderPaymentEvent.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final String restaurantId;
  final String? locationId;
  final int orderNumber;
  final String displayId;
  final int? dailyOrderNumber;
  final String? customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String status;
  final String paymentStatus;
  final String paymentMethod;
  final String? couponCode;
  final int subtotalCents;
  final int discountCents;
  final int? shippingCents;
  final int totalCents;
  final String fulfillmentType;
  final DateTime? scheduledFor;
  final String orderType;
  final bool isInKitchen;
  final DateTime? kitchenStartedAt;
  final String? idempotencyKey;
  final DateTime placedAt;
  final DateTime? pickedUpAt;
  final String? notes;
  final String? placedByDeviceId;
  final List<OrderItem> items;
  final List<OrderPaymentEvent> paymentEvents;

  int get refundedCents => paymentEvents
      .where((event) => event.type == OrderPaymentEventType.refund)
      .fold(0, (sum, event) => sum + (event.amountCents ?? 0));

  int get refundableCents => totalCents - refundedCents;

  bool get canRefund => paymentStatus == 'paid' || paymentStatus == 'partially_refunded';

  OrderPaymentEvent? get latestCharge =>
      paymentEvents.where((event) => event.type == OrderPaymentEventType.charge).lastOrNull;

  OrderPaymentEvent? get latestFailure =>
      paymentEvents.where((event) => event.type == OrderPaymentEventType.failure).lastOrNull;
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

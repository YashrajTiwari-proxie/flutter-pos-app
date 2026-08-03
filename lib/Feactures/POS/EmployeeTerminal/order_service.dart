import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import 'order_models.dart';
import 'softpay_models.dart';

class OrderService {
  OrderService._();

  static final OrderService instance = OrderService._();

  /// Convex's `v.optional(...)` only accepts a missing key, not an explicit `null` - so any
  /// null-valued entries must be dropped before sending, rather than passed through as `null`.
  static Map<String, dynamic> _withoutNulls(Map<String, dynamic> map) =>
      {for (final entry in map.entries) if (entry.value != null) entry.key: entry.value};

  static Map<String, dynamic> _transactionToJson(TransactionResult transaction) => _withoutNulls({
    'requestId': transaction.requestId,
    'state': transaction.state,
    'type': transaction.type,
    'cardScheme': transaction.cardScheme,
    'partialPan': transaction.partialPan,
    'auditNumber': transaction.auditNumber,
    'cvm': transaction.cvm,
    'terminalId': transaction.terminalId,
    'batchNumber': transaction.batchNumber,
    'tipMinor': transaction.tipMinor,
    'surchargeMinor': transaction.surchargeMinor,
    'transactionDate': transaction.transactionDate,
  });

  Future<List<Order>> fetchOrders() async {
    final raw = await ConvexClient.instance.query('orders:list', const {});
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((entry) => Order.fromJson(entry as Map<String, dynamic>)).toList();
  }

  /// Creates an order in `processing` state and returns its id.
  Future<String> createOrder({
    required String currency,
    required int totalMinor,
    required List<OrderItem> items,
  }) async {
    final raw = await ConvexClient.instance.mutation(
      name: 'orders:create',
      args: {
        'currency': currency,
        'totalMinor': totalMinor,
        'items': items.map((item) => item.toJson()).toList(),
      },
    );
    return jsonDecode(raw) as String;
  }

  Future<void> recordPaymentSuccess({required String orderId, required TransactionResult transaction}) {
    return ConvexClient.instance.mutation(
      name: 'orders:recordPaymentResult',
      args: {
        'orderId': orderId,
        'success': true,
        'payment': _transactionToJson(transaction),
      },
    );
  }

  Future<void> recordPaymentFailure({
    required String orderId,
    required String code,
    required String message,
    int? detailedCode,
  }) {
    return ConvexClient.instance.mutation(
      name: 'orders:recordPaymentResult',
      args: {
        'orderId': orderId,
        'success': false,
        'failure': _withoutNulls({'code': code, 'message': message, 'detailedCode': detailedCode}),
      },
    );
  }

  Future<void> recordCancellation({required String orderId}) {
    return ConvexClient.instance.mutation(name: 'orders:recordCancellation', args: {'orderId': orderId});
  }

  Future<void> recordRefund({
    required String orderId,
    required int amountMinor,
    String? reason,
    TransactionResult? transaction,
  }) {
    return ConvexClient.instance.mutation(
      name: 'orders:recordRefund',
      args: _withoutNulls({
        'orderId': orderId,
        'amountMinor': amountMinor,
        'reason': reason,
        'transaction': transaction == null ? null : _transactionToJson(transaction),
      }),
    );
  }
}

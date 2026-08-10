import 'package:flutter/services.dart';

import '../../../Database/models/cart_entry.dart';
import '../../../Database/models/menu_item.dart';
import '../EmployeeTerminal/softpay_models.dart';

sealed class CustomerBridgeEvent {}

class CartUpdated extends CustomerBridgeEvent {
  CartUpdated({required this.cart, required this.currency});

  final List<CartEntry> cart;
  final String currency;
}

class StartChargeRequested extends CustomerBridgeEvent {
  StartChargeRequested({required this.amountMinor, required this.currency});

  final int amountMinor;
  final String currency;
}

class CancelChargeRequested extends CustomerBridgeEvent {}

/// Talks to the native [DisplayBridge] relay (see
/// `android/app/.../dualdisplay/DisplayBridge.kt`) from the customer-display engine: receives
/// cart snapshots and charge/cancel commands from the cashier screen, and reports payment
/// status/results back to it.
class CustomerDisplayBridge {
  CustomerDisplayBridge._();

  static final CustomerDisplayBridge instance = CustomerDisplayBridge._();

  static const _methodChannel = MethodChannel('com.proxiestudio.kds_pos/bridge/customer');
  static const _eventChannel = EventChannel('com.proxiestudio.kds_pos/bridge/customer/events');

  Stream<CustomerBridgeEvent>? _events;

  Stream<CustomerBridgeEvent> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map(_parseEvent)
        .where((event) => event != null)
        .cast<CustomerBridgeEvent>()
        .asBroadcastStream();
  }

  CustomerBridgeEvent? _parseEvent(dynamic event) {
    final map = Map<Object?, Object?>.from(event as Map);
    switch (map['type']) {
      case 'cart':
        final cartMap = Map<Object?, Object?>.from(map['cart'] as Map? ?? const {});
        final currency = cartMap['currency'] as String? ?? '';
        final items = (cartMap['items'] as List<dynamic>? ?? const [])
            .map((raw) {
              final itemMap = Map<String, dynamic>.from(raw as Map);
              final quantity = (itemMap['quantity'] as num).toInt();
              return CartEntry(item: MenuItem.fromJson(itemMap), quantity: quantity);
            })
            .toList();
        return CartUpdated(cart: items, currency: currency);
      case 'startCharge':
        return StartChargeRequested(
          amountMinor: (map['amountMinor'] as num).toInt(),
          currency: map['currency'] as String,
        );
      case 'cancelCharge':
        return CancelChargeRequested();
      default:
        return null;
    }
  }

  Future<void> reportStatus(PaymentStatusUpdate status) {
    return _methodChannel.invokeMethod('reportStatus', {
      'stage': status.stage.name,
      'detail': status.detail,
    });
  }

  Future<void> reportResult(TransactionResult result) {
    return _methodChannel.invokeMethod('reportResult', {
      'requestId': result.requestId,
      'amountMinor': result.amountMinor,
      'currency': result.currency,
      'state': result.state,
      'cardScheme': result.cardScheme,
      'partialPan': result.partialPan,
      'auditNumber': result.auditNumber,
    });
  }

  Future<void> reportError(SoftPayException error) {
    return _methodChannel.invokeMethod('reportError', {
      'code': error.code,
      'message': error.message,
      'detailedCode': error.detailedCode,
    });
  }
}

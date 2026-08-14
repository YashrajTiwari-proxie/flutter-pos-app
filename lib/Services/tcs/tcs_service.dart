import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import 'tcs_models.dart';

/// Calls the 6 TCS-D fiscal Convex actions (agentSale, agentRefund,
/// agentCopy, agentExercise, agentProfo, agentRegisterStatus) — see the
/// fiscal branch's docs/superpowers/specs/2026-08-13-tcs-convex-functions.md
/// for the exact contract each one expects/returns.
///
/// Every action is device-gated server-side (POS devices only) — pass this
/// device's own token (DeviceIdentityService.instance.token), same as every
/// other device-facing call in this app. This service never touches the TCS
/// certificate or Infrasec directly — that stays entirely server-side; all
/// this does is call an already-authorized Convex action, same shape as any
/// other `ConvexClient.instance.mutation(...)` call elsewhere in this app.
class TcsService {
  TcsService._();

  static final TcsService instance = TcsService._();

  // These are real-money/legal-record actions (same reasoning as
  // device_repository.dart's own _timeout) — a hung native/Convex call must
  // never leave a test (or, later, a real checkout) screen stuck forever.
  static const _timeout = Duration(seconds: 20);

  Future<TcsResult> _call(String name, Map<String, dynamic> args) async {
    final raw = await ConvexClient.instance
        .action(name: name, args: args)
        .timeout(_timeout);
    return TcsResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Boot heartbeat — call once when a POS register starts, before any sale.
  Future<TcsResult> agentRegisterStatus({
    required String deviceToken,
    String? requestId,
  }) {
    return _call('agentRegisterStatus:agentRegisterStatus', {
      'deviceToken': deviceToken,
      if (requestId != null) 'requestId': requestId,
    });
  }

  /// Fiscalizes a normal sale. Returns the full 113-char control code.
  Future<TcsResult> agentSale({
    required String deviceToken,
    required String saleAmount,
    required String dateTime,
    String? sequenceNumber,
    String? requestId,
    List<TcsVatBand>? vats,
  }) {
    return _call('agentSale:agentSale', {
      'deviceToken': deviceToken,
      'saleAmount': saleAmount,
      'dateTime': dateTime,
      if (sequenceNumber != null) 'sequenceNumber': sequenceNumber,
      if (requestId != null) 'requestId': requestId,
      if (vats != null) 'vats': vats.map((v) => v.toJson()).toList(),
    });
  }

  /// Fiscalizes a refund (same ReceiptType "normal" as a sale, but the
  /// amount travels as RefundAmount — always positive/absolute).
  Future<TcsResult> agentRefund({
    required String deviceToken,
    required String refundAmount,
    required String dateTime,
    String? sequenceNumber,
    String? requestId,
    List<TcsVatBand>? vats,
  }) {
    return _call('agentRefund:agentRefund', {
      'deviceToken': deviceToken,
      'refundAmount': refundAmount,
      'dateTime': dateTime,
      if (sequenceNumber != null) 'sequenceNumber': sequenceNumber,
      if (requestId != null) 'requestId': requestId,
      if (vats != null) 'vats': vats.map((v) => v.toJson()).toList(),
    });
  }

  /// Fiscalizes a receipt copy (ReceiptType "kopia") — empty control code;
  /// the physical receipt must print "Kopia" (Swedish, exact word).
  Future<TcsResult> agentCopy({
    required String deviceToken,
    required String saleAmount,
    required String copySequenceNumber,
    required String copyDateTime,
    required String dateTime,
    String? sequenceNumber,
    String? requestId,
    List<TcsVatBand>? vats,
  }) {
    return _call('agentCopy:agentCopy', {
      'deviceToken': deviceToken,
      'saleAmount': saleAmount,
      'copySequenceNumber': copySequenceNumber,
      'copyDateTime': copyDateTime,
      'dateTime': dateTime,
      if (sequenceNumber != null) 'sequenceNumber': sequenceNumber,
      if (requestId != null) 'requestId': requestId,
      if (vats != null) 'vats': vats.map((v) => v.toJson()).toList(),
    });
  }

  /// Fiscalizes a practice receipt (ReceiptType "ovning") — empty control
  /// code; the physical receipt must print "Övning" (Swedish, exact word).
  Future<TcsResult> agentExercise({
    required String deviceToken,
    required String saleAmount,
    required String dateTime,
    String? sequenceNumber,
    String? requestId,
    List<TcsVatBand>? vats,
  }) {
    return _call('agentExercise:agentExercise', {
      'deviceToken': deviceToken,
      'saleAmount': saleAmount,
      'dateTime': dateTime,
      if (sequenceNumber != null) 'sequenceNumber': sequenceNumber,
      if (requestId != null) 'requestId': requestId,
      if (vats != null) 'vats': vats.map((v) => v.toJson()).toList(),
    });
  }

  /// Fiscalizes a proforma/quote (ReceiptType "profo") — empty control code;
  /// the physical receipt must print "Ej kvitto" (Swedish, exact phrase).
  Future<TcsResult> agentProfo({
    required String deviceToken,
    required String saleAmount,
    required String dateTime,
    String? sequenceNumber,
    String? requestId,
    List<TcsVatBand>? vats,
  }) {
    return _call('agentProfo:agentProfo', {
      'deviceToken': deviceToken,
      'saleAmount': saleAmount,
      'dateTime': dateTime,
      if (sequenceNumber != null) 'sequenceNumber': sequenceNumber,
      if (requestId != null) 'requestId': requestId,
      if (vats != null) 'vats': vats.map((v) => v.toJson()).toList(),
    });
  }
}

import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import '../../Feactures/POS/Settings/Journal/journal_entry.dart';
import '../device_identity_service.dart';

/// Device-facing live feed of the fiscal journal — mirrors
/// `convex/journal.ts`'s `journalForDevice` query.
class JournalRepository {
  JournalRepository._();

  static final JournalRepository instance = JournalRepository._();

  String get _deviceToken {
    final token = DeviceIdentityService.instance.token;
    if (token == null) {
      throw StateError('Device is not paired — call DeviceIdentityService.pair() first');
    }
    return token;
  }

  Future<SubscriptionHandle> subscribeToJournal({
    required void Function(List<JournalEntry> entries) onUpdate,
    required void Function(String message, dynamic details) onError,
  }) {
    return ConvexClient.instance.subscribe(
      name: 'journal:journalForDevice',
      args: {'deviceToken': _deviceToken},
      onUpdate: (raw) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        onUpdate(decoded.map((e) => JournalEntry.fromJson(e as Map<String, dynamic>)).toList());
      },
      onError: onError,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

/// Turns a raw exception into a short, human-readable sentence for display in the UI, and logs
/// the real error via [debugPrint] so it's still visible in `flutter logs`/adb for diagnosis.
String friendlyErrorMessage(Object error, {required String action}) {
  debugPrint('$action failed: $error');

  if (error is TimeoutException) {
    return 'This is taking longer than expected. Check your connection and try again.';
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Connection') || text.contains('Network')) {
    return "Can't reach the server. Check your network connection and try again.";
  }
  return 'Something went wrong while $action. Please try again.';
}

/// Well-known Softpay failure identifiers that deserve a tailored phrase rather than a plain
/// word-split of the SDK's own SCREAMING_SNAKE_CASE name.
const _knownSoftPayMessages = {
  'TRANSACTION_DECLINED': 'Card declined',
  'TRANSACTION_CANCELLED': 'Cancelled',
  'TRANSACTION_DUPLICATED': 'Duplicate transaction',
  'TRANSACTION_INCOMPLETE': 'Transaction was not completed - please try again',
  'TRANSACTION_TIMEOUT': 'Timed out - please try again',
};

/// Acronyms that should stay upper-case when humanizing a Softpay failure identifier, rather
/// than being title-cased like an ordinary word (e.g. "Nfc" -> "NFC").
const _softPayAcronyms = {'nfc', 'pin', 'emv', 'ble', 'usb', 'sim', 'cvm', 'id'};

final _softPayFailureCodePattern = RegExp(r'([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)\s*\(-?\d+(?:/-?\d+)?\)\s*$');

/// Turns a raw Softpay SDK failure message - e.g.
/// "transaction nfc error: FAILED: NFC_ERROR-NFC_NOT_ENABLED(520/4)" - into a short human
/// sentence like "NFC Not Enabled". The SDK reports failures as a SCREAMING_SNAKE_CASE
/// identifier followed by a `(code/detailedCode)` suffix; known identifiers get a tailored
/// phrase, anything else still gets humanized generically so unseen codes remain readable
/// instead of showing the raw technical string.
String friendlySoftPayMessage(String rawMessage) {
  final known = _knownSoftPayMessages[rawMessage];
  if (known != null) return known;

  final identifier = _softPayFailureCodePattern.firstMatch(rawMessage)?.group(1);
  if (identifier == null) return rawMessage;

  return _knownSoftPayMessages[identifier] ?? _humanizeIdentifier(identifier);
}

/// Turns a raw Softpay SDK processing-phase identifier (e.g. "PROCESSING_KERNEL", emitted via
/// `onProcessing` while a charge is in flight) into a short human phrase (e.g. "Processing
/// Kernel"). Unlike [friendlySoftPayMessage] there's no `(code)` suffix to strip - these are
/// bare SCREAMING_SNAKE_CASE phase names, not failure identifiers - so this only humanizes
/// strings that actually look like one; anything else (already human-readable SDK text) passes
/// through unchanged.
String friendlySoftPayProcessingUpdate(String raw) {
  if (!RegExp(r'^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*$').hasMatch(raw)) return raw;
  return _humanizeIdentifier(raw);
}

String _humanizeIdentifier(String identifier) {
  return identifier
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) {
        if (_softPayAcronyms.contains(word.toLowerCase())) return word.toUpperCase();
        return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
      })
      .join(' ');
}

/// Well-known Sunmi printer `Status` names that deserve a tailored phrase.
const _knownPrinterMessages = {
  'NOT_CONNECTED': 'No printer connected',
  'OFFLINE': 'Printer is offline',
  'COMM': "Can't communicate with the printer",
  'ERR_PAPER_OUT': 'Printer is out of paper',
  'ERR_PAPER_JAM': 'Paper is jammed in the printer',
  'ERR_PAPER_MISMATCH': 'Wrong paper loaded in the printer',
  'ERR_COVER': "Printer's cover is open",
  'ERR_COVER_INCOMPLETE': "Printer's cover isn't fully closed",
  'WARN_THERMAL_PAPER': 'Printer paper is running low',
};

/// Turns a Sunmi printer `Status` name (e.g. `ERR_PAPER_OUT`) into a short human sentence.
/// Returns null for `READY` or any other status that doesn't need to be shown to staff.
String? friendlyPrinterIssue(String status) {
  if (status == 'READY') return null;
  final known = _knownPrinterMessages[status];
  if (known != null) return known;
  if (status.startsWith('ERR_') || status.startsWith('WARN_')) {
    return _humanizeIdentifier(status.substring(status.indexOf('_') + 1));
  }
  return null;
}

/// A centered icon + message + optional retry button, used in place of dumping a raw error
/// object onto the screen.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A centered icon + message for an empty (but not erroring) list/collection.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

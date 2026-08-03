import 'package:sunmi_flutter_plugin_printer/bean/printer.dart';
import 'package:sunmi_flutter_plugin_printer/enum/align.dart';
import 'package:sunmi_flutter_plugin_printer/enum/dividing_line.dart';
import 'package:sunmi_flutter_plugin_printer/listener/printer_listener.dart';
import 'package:sunmi_flutter_plugin_printer/printer_sdk.dart';
import 'package:sunmi_flutter_plugin_printer/style/base_style.dart';
import 'package:sunmi_flutter_plugin_printer/style/text_style.dart';

import 'order_models.dart';

class PrinterException implements Exception {
  const PrinterException({required this.code, this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'PrinterException($code): $message';
}

class _PrinterListenerAdapter extends PrinterListener {
  _PrinterListenerAdapter(this.onPrinter);

  final void Function(Printer printer) onPrinter;

  @override
  void onDefPrinter(Printer var1) => onPrinter(var1);
}

/// Talks to the Sunmi built-in printer via the official `sunmi_flutter_plugin_printer` package
/// (https://pub.dev/packages/sunmi_flutter_plugin_printer), which wraps the same native
/// `com.sunmi:printerx` SDK Sunmi's docs describe.
class PrinterService {
  PrinterService._() {
    PrinterSdk.instance.getPrinter(_PrinterListenerAdapter((printer) => _printer = printer));
  }

  static final PrinterService instance = PrinterService._();

  Printer? _printer;

  /// One of Sunmi's `Status` enum names (e.g. `READY`, `ERR_PAPER_OUT`), or `NOT_CONNECTED`
  /// if no printer has been resolved yet (also returned on devices with no printer at all).
  Future<String> status() async {
    final printer = _printer;
    if (printer == null) return 'NOT_CONNECTED';
    try {
      final status = await printer.queryApi.getStatus();
      return status.name;
    } catch (_) {
      return 'NOT_CONNECTED';
    }
  }

  Future<void> printReceipt({
    required List<OrderItem> items,
    required String currency,
    required int totalMinor,
    String? cardScheme,
    String? partialPan,
    String? orderReference,
  }) async {
    final printer = _printer;
    if (printer == null) {
      throw const PrinterException(code: 'NOT_CONNECTED', message: 'No printer connected');
    }

    try {
      final status = await printer.queryApi.getStatus();
      if (status.name != 'READY' && !status.name.startsWith('WARN_')) {
        throw PrinterException(code: status.name);
      }

      final line = printer.lineApi;

      await line.initLine(BaseStyle.getStyle().setAlign(Align.CENTER));
      await line.printText('KDS POS', TextStyle.getStyle().enableBold(true));
      await line.printDividingLine(DividingLine.EMPTY, 16);
      await line.printDividingLine(DividingLine.DOTTED, 2);
      await line.printDividingLine(DividingLine.EMPTY, 16);

      await line.initLine(BaseStyle.getStyle().setAlign(Align.LEFT));
      await line.printTexts(
        ['Item', 'Qty', 'Amount'],
        [3, 1, 2],
        [
          TextStyle.getStyle().enableBold(true),
          TextStyle.getStyle().enableBold(true),
          TextStyle.getStyle().enableBold(true).setAlign(Align.RIGHT),
        ],
      );
      for (final item in items) {
        await line.printTexts(
          [item.name, '${item.quantity}', _formatMinor(item.subtotalMinor, currency)],
          [3, 1, 2],
          [TextStyle.getStyle(), TextStyle.getStyle(), TextStyle.getStyle().setAlign(Align.RIGHT)],
        );
      }

      await line.printDividingLine(DividingLine.EMPTY, 8);
      await line.printDividingLine(DividingLine.DOTTED, 2);
      await line.printDividingLine(DividingLine.EMPTY, 8);

      await line.printTexts(
        ['Total', _formatMinor(totalMinor, currency)],
        [1, 1],
        [
          TextStyle.getStyle().enableBold(true).setTextSize(32),
          TextStyle.getStyle().enableBold(true).setTextSize(32).setAlign(Align.RIGHT),
        ],
      );

      if (cardScheme != null) {
        await line.initLine(BaseStyle.getStyle().setAlign(Align.LEFT));
        final panSuffix = partialPan != null ? ' •••• $partialPan' : '';
        await line.printText('$cardScheme$panSuffix', TextStyle.getStyle());
      }

      await line.printDividingLine(DividingLine.EMPTY, 16);
      await line.initLine(BaseStyle.getStyle().setAlign(Align.CENTER));
      await line.printText('Thank you!', TextStyle.getStyle());
      if (orderReference != null) {
        await line.printText(orderReference, TextStyle.getStyle().setTextSize(20));
      }
      await line.autoOut();
    } on PrinterException {
      rethrow;
    } catch (e) {
      throw PrinterException(code: 'PRINT_FAILED', message: e.toString());
    }
  }

  String _formatMinor(int minor, String currency) => '${(minor / 100).toStringAsFixed(2)} $currency';
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:sunmi_flutter_plugin_printer/bean/printer.dart';
import 'package:sunmi_flutter_plugin_printer/enum/align.dart';
import 'package:sunmi_flutter_plugin_printer/enum/dividing_line.dart';
import 'package:sunmi_flutter_plugin_printer/enum/image_algorithm.dart';
import 'package:sunmi_flutter_plugin_printer/listener/printer_listener.dart';
import 'package:sunmi_flutter_plugin_printer/printer_sdk.dart';
import 'package:sunmi_flutter_plugin_printer/style/base_style.dart';
import 'package:sunmi_flutter_plugin_printer/style/bitmap_style.dart';
import 'package:sunmi_flutter_plugin_printer/style/text_style.dart';

/// Logo print width in dots, comfortably under the ~384-dot printable width
/// of a 58mm thermal roll (leaves margin either side) — height is derived
/// from this to preserve the source image's aspect ratio.
const int _kLogoPrintWidth = 300;

class PrinterException implements Exception {
  const PrinterException({required this.code, this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'PrinterException($code): $message';
}

/// One printed line item — deliberately not `CartEntry` (which needs a
/// full `MenuItem`, unavailable when printing from an already-placed
/// order's line items in `orders_screen.dart`) or the backend's
/// `OrderItem` (unavailable when printing from an in-progress cart in
/// `employee_terminal_screen.dart` before an order even exists). Both call
/// sites map their own source list into this instead.
class ReceiptLine {
  const ReceiptLine({required this.name, required this.quantity, required this.subtotalCents});

  final String name;
  final int quantity;
  final int subtotalCents;
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
    required List<ReceiptLine> items,
    required String currency,
    required int totalCents,
    String? cardScheme,
    String? partialPan,
    String? orderReference,
    Uint8List? logoBytes,
    String? headerText,
    String? footerText,
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
      if (logoBytes != null) {
        final printHeight = await _scaledLogoHeight(logoBytes);
        await line.printBitmap(
          logoBytes,
          BitmapStyle.getStyle()
              .setAlign(Align.CENTER)
              .setAlgorithm(ImageAlgorithm.DITHERING)
              .setWidth(_kLogoPrintWidth)
              .setHeight(printHeight),
        );
      } else {
        await line.printText('KDS POS', TextStyle.getStyle().enableBold(true));
      }
      if (headerText != null && headerText.isNotEmpty) {
        await line.printText(headerText, TextStyle.getStyle());
      }
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
      for (final receiptLine in items) {
        await line.printTexts(
          [receiptLine.name, '${receiptLine.quantity}', _formatCents(receiptLine.subtotalCents, currency)],
          [3, 1, 2],
          [TextStyle.getStyle(), TextStyle.getStyle(), TextStyle.getStyle().setAlign(Align.RIGHT)],
        );
      }

      await line.printDividingLine(DividingLine.EMPTY, 8);
      await line.printDividingLine(DividingLine.DOTTED, 2);
      await line.printDividingLine(DividingLine.EMPTY, 8);

      await line.printTexts(
        ['Total', _formatCents(totalCents, currency)],
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
      if (footerText != null && footerText.isNotEmpty) {
        await line.printDividingLine(DividingLine.EMPTY, 8);
        await line.printText(footerText, TextStyle.getStyle());
      }
      await line.autoOut();
    } on PrinterException {
      rethrow;
    } catch (e) {
      throw PrinterException(code: 'PRINT_FAILED', message: e.toString());
    }
  }

  String _formatCents(int cents, String currency) => '${(cents / 100).toStringAsFixed(2)} $currency';

  /// Decodes just enough of the logo to read its natural dimensions so the
  /// printed bitmap keeps its aspect ratio at [_kLogoPrintWidth] instead of
  /// being stretched/squashed to a fixed height. Falls back to a square if
  /// decoding fails (e.g. corrupt bytes) rather than failing the print.
  Future<int> _scaledLogoHeight(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final height = (_kLogoPrintWidth * image.height / image.width).round();
      image.dispose();
      return height;
    } catch (_) {
      return _kLogoPrintWidth;
    }
  }
}

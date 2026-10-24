import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../core/dates.dart';
import '../core/errors.dart';
import '../core/money.dart';
import '../core/quantity.dart';
import '../data/models/models.dart';
import '../data/repositories/settings_repository.dart';

/// Thermal ESC/POS output.
///
/// ESC/POS printers use legacy code pages. This builder deliberately emits
/// ASCII only so accented French and Arabic characters never print as garbage.
/// Arabic product names are printed from their French name (always required);
/// when only Arabic is available a readable `?` placeholder is printed.
/// A PDF/share fallback is always offered by the UI.
class EscPosBuilder {
  EscPosBuilder({this.width = 32});

  final int width;

  static List<int> init() => [0x1B, 0x40];

  static List<int> align(int value) => [0x1B, 0x61, value];

  static List<int> doubleSize() => [0x1D, 0x21, 0x11];

  static List<int> normalSize() => [0x1D, 0x21, 0x00];

  static List<int> cut() => [0x1D, 0x56, 0x42, 0x00];

  static List<int> feed([int lines = 2]) => [0x1B, 0x64, lines];

  List<int> sale(Sale sale, Shop shop) {
    final out = <int>[];
    out.addAll(init());
    out.addAll(align(1));
    out.addAll(_text(ascii(shop.name), bold: true, double: true));
    if (shop.phone != null) out.addAll(_text(ascii(shop.phone!)));
    if (shop.address != null) out.addAll(_text(ascii(shop.address!)));
    out.addAll(_text('- ' * (width ~/ 2)));
    out.addAll(align(0));
    out.addAll(_line(left: sale.invoiceNo, right: _time(sale.createdAt)));
    if (sale.customerName != null) {
      out.addAll(_text('Client: ${ascii(sale.customerName!)}'));
    }
    out.addAll(_text('-' * width));
    for (final line in sale.lines) {
      final name = ascii(line.productName);
      for (final chunk in _wrap(name, width)) {
        out.addAll(_text(chunk));
      }
      final unit = line.unitName.isEmpty ? '' : ' ${ascii(line.unitName)}';
      final left =
          '${Qty.format(line.displayQtyMilli)}$unit x ${Money.format(line.displayUnitPriceCentimes)}';
      final right = Money.format(line.lineTotalCentimes);
      out.addAll(_line(left: left, right: right));
    }
    out.addAll(_text('-' * width));
    if (sale.subtotalCentimes != sale.totalCentimes) {
      out.addAll(
        _line(left: 'Sous-total', right: Money.format(sale.subtotalCentimes)),
      );
    }
    if (sale.discountCentimes > 0) {
      out.addAll(
        _line(left: 'Remise', right: '-${Money.format(sale.discountCentimes)}'),
      );
    }
    out.addAll(
      _line(left: 'TOTAL', right: Money.format(sale.totalCentimes), bold: true),
    );
    out.addAll(_line(left: 'Paye', right: Money.format(sale.paidCentimes)));
    if (sale.dueCentimes > 0) {
      out.addAll(_line(left: 'Reste', right: Money.format(sale.dueCentimes)));
    }
    if (sale.returnedCentimes > 0) {
      out.addAll(
        _line(
          left: 'Retours',
          right: '-${Money.format(sale.returnedCentimes)}',
        ),
      );
    }
    out.addAll(_text('-' * width));
    out.addAll(align(1));
    out.addAll(_text(ascii(shop.footer ?? 'Merci de votre visite')));
    out.addAll(_text('Hydra POS', small: true));
    out.addAll(align(0));
    out.addAll(feed());
    out.addAll(cut());
    return out;
  }

  List<int> test() {
    final out = <int>[...init(), ...align(1)];
    out.addAll(_text('HYDRA POS', bold: true, double: true));
    out.addAll(_text('Test imprimante OK'));
    out.addAll(_text(Dates.formatDateTime(DateTime.now())));
    out.addAll(feed(3));
    out.addAll(cut());
    return out;
  }

  List<int> _line({
    required String left,
    required String right,
    bool bold = false,
  }) {
    var l = left;
    var r = right;
    if (l.length + r.length >= width) {
      l = l.substring(0, (width - r.length - 1).clamp(0, l.length));
    }
    final spaces = width - l.length - r.length;
    return _text('$l${' ' * spaces.clamp(0, width)}$r', bold: bold);
  }

  List<int> _text(
    String value, {
    bool bold = false,
    bool double = false,
    bool small = false,
  }) {
    final bytes = <int>[];
    if (bold) bytes.addAll([0x1B, 0x45, 1]);
    if (double) bytes.addAll([0x1D, 0x21, 0x11]);
    if (small) bytes.addAll([0x1B, 0x4D, 1]);
    bytes.addAll(value.codeUnits.map((c) => c > 126 ? 63 : c));
    bytes.add(0x0A);
    if (small) bytes.addAll([0x1B, 0x4D, 0]);
    if (double) bytes.addAll(normalSize());
    if (bold) bytes.addAll([0x1B, 0x45, 0]);
    return bytes;
  }

  List<String> _wrap(String value, int length) {
    if (value.isEmpty) return [''];
    final result = <String>[];
    var remaining = value;
    while (remaining.length > length) {
      var cut = remaining.lastIndexOf(' ', length);
      if (cut <= 0) cut = length;
      result.add(remaining.substring(0, cut).trimRight());
      remaining = remaining.substring(cut).trimLeft();
    }
    if (remaining.isNotEmpty) result.add(remaining);
    return result;
  }

  String _time(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${Dates.formatDate(d)} ${Dates.formatTime(d)}';
  }

  /// Removes accents and non-ASCII characters for legacy printers.
  static String ascii(String input) {
    const map = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ã': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ó': 'o',
      'õ': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ÿ': 'y',
      'ñ': 'n',
      'œ': 'oe',
      'æ': 'ae',
      'À': 'A',
      'Â': 'A',
      'Ä': 'A',
      'Á': 'A',
      'Ã': 'A',
      'Ç': 'C',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Î': 'I',
      'Ï': 'I',
      'Í': 'I',
      'Ô': 'O',
      'Ö': 'O',
      'Ó': 'O',
      'Õ': 'O',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ú': 'U',
      'Ÿ': 'Y',
      'Ñ': 'N',
      'Œ': 'OE',
      'Æ': 'AE',
      '°': 'o',
    };
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(map[char] ?? (rune >= 32 && rune <= 126 ? char : '?'));
    }
    return buffer.toString();
  }
}

class PrintService {
  PrintService(this.settings);
  final SettingsRepository settings;

  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<List<BluetoothInfo>> pairedPrinters() async {
    if (!supported) {
      throw AppError(
        'printer_platform',
        'L\'impression Bluetooth est disponible sur Android.',
      );
    }
    await _requestPermissions();
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      throw AppError('printer_off', 'Activez le Bluetooth puis réessayez.');
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  /// Asks the printer plugin to request BLUETOOTH_CONNECT/SCAN at runtime.
  ///
  /// The plugin owns the Android permission request, so the app does not need
  /// a second permission plugin (and its newer compileSdk requirement).
  Future<void> _requestPermissions() async {
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted) {
      throw AppError(
        'printer_permission',
        'Autorisez l\'accès Bluetooth pour utiliser l\'imprimante.',
      );
    }
  }

  Future<void> connect(String mac) async {
    if (!supported) {
      throw AppError(
        'printer_platform',
        'L\'impression Bluetooth est disponible sur Android.',
      );
    }
    await _requestPermissions();
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!ok) {
      throw AppError('printer_connect', 'Connexion à l\'imprimante échouée.');
    }
  }

  Future<void> printSale(Sale sale, Shop shop) async {
    if (!supported) {
      throw AppError(
        'printer_platform',
        'L\'impression Bluetooth est disponible sur Android.',
      );
    }
    final connected = await PrintBluetoothThermal.connectionStatus;
    final mac = await settings.printerMac();
    if (!connected && mac.isNotEmpty) {
      await connect(mac);
    }
    if (!await PrintBluetoothThermal.connectionStatus) {
      throw AppError('printer_connect', 'Imprimante non connectée.');
    }
    final width = (await settings.paperWidth()) == 80 ? 48 : 32;
    final bytes = EscPosBuilder(width: width).sale(sale, shop);
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      throw AppError('printer_write', 'Écriture vers l\'imprimante échouée.');
    }
  }

  Future<void> testPrinter() async {
    final mac = await settings.printerMac();
    if (mac.isEmpty) {
      throw AppError('printer_config', 'Sélectionnez une imprimante.');
    }
    await connect(mac);
    final width = (await settings.paperWidth()) == 80 ? 48 : 32;
    final ok = await PrintBluetoothThermal.writeBytes(
      EscPosBuilder(width: width).test(),
    );
    if (!ok) {
      throw AppError('printer_write', 'Écriture vers l\'imprimante échouée.');
    }
  }
}

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/dates.dart';
import '../core/money.dart';
import '../core/quantity.dart';
import '../data/models/models.dart';

/// Builds invoices and receipts with the `pdf` package.
///
/// Arabic text needs the Arabic shaping algorithm of the pdf package. Build
/// Android releases with `--dart-define=use_arabic=true` so Arabic names are
/// rendered with joined letters. Latin-only builds still produce a correct
/// French document.
class InvoicePdfService {
  pw.Font? _latin;
  pw.Font? _latinBold;
  pw.Font? _arabic;

  Future<void> _loadFonts() async {
    if (_latin != null) return;
    _latin = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    _latinBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    _arabic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
  }

  pw.ThemeData get _theme => pw.ThemeData.withFont(
    base: _latin,
    bold: _latinBold,
    fontFallback: [_arabic!],
  );

  /// Full-page invoice (A4) or a narrow receipt.
  Future<Uint8List> saleDocument({
    required Sale sale,
    required Shop shop,
    required bool arabic,
    bool receipt = false,
    double paperWidthMm = 58,
  }) async {
    await _loadFonts();
    final doc = pw.Document(
      title: sale.invoiceNo,
      author: shop.name,
      creator: 'Hydra POS',
    );
    final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAt);
    final pageFormat = receipt
        ? PdfPageFormat(
            paperWidthMm * PdfPageFormat.mm,
            220 * PdfPageFormat.mm,
            marginAll: 4 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        theme: _theme,
        build: (context) => receipt
            ? _receiptContent(sale, shop, arabic, date)
            : _invoiceContent(sale, shop, arabic, date),
        footer: receipt
            ? null
            : (context) => pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${shop.name} — ${Dates.formatDateTime(date)}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
      ),
    );
    return doc.save();
  }

  /// A4 purchase document. Purchases are not customer invoices, so the title
  /// and supplier block are explicit to avoid confusing the two records.
  Future<Uint8List> purchaseDocument({
    required Purchase purchase,
    required Shop shop,
    required bool arabic,
  }) async {
    await _loadFonts();
    final doc = pw.Document(
      title: purchase.refNo,
      author: shop.name,
      creator: 'Hydra POS',
    );
    final date = DateTime.fromMillisecondsSinceEpoch(purchase.createdAt);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        build: (context) => _purchaseContent(purchase, shop, arabic, date),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${shop.name} — ${Dates.formatDateTime(date)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );
    return doc.save();
  }

  List<pw.Widget> _purchaseContent(
    Purchase purchase,
    Shop shop,
    bool arabic,
    DateTime date,
  ) {
    pw.Widget text(String value, {bool bold = false, double size = 10}) =>
        _t(value, arabic: arabic, bold: bold, size: size);
    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                shop.name,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (shop.nameAr != null && shop.nameAr!.trim().isNotEmpty)
                _t(shop.nameAr!, arabic: true, size: 13),
              if (shop.address != null) text(shop.address!, size: 9),
              if (shop.phone != null) text(shop.phone!, size: 9),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              text('BON D\'ACHAT', bold: true, size: 20),
              pw.SizedBox(height: 6),
              text(purchase.refNo, bold: true, size: 12),
              text(Dates.formatDateTime(date), size: 9),
              if (purchase.isVoided)
                pw.Text(
                  'ANNULÉ',
                  style: pw.TextStyle(
                    color: PdfColors.red,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Divider(color: PdfColors.grey400),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              text('Fournisseur', bold: true, size: 10),
              text(purchase.supplierName ?? '—', size: 11),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              text(
                'Paiement : ${_methodLabel(purchase.paymentMethod)}',
                size: 9,
              ),
              text(purchase.isVoided ? 'Annulé' : 'Réceptionné', size: 9),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.TableHelper.fromTextArray(
        headers: ['Article', 'Qté', 'P.U. achat', 'Total'],
        data: [
          for (final line in purchase.lines)
            [
              line.productName +
                  (line.unitName.isEmpty ? '' : ' (${line.unitName})'),
              Qty.format(_purchaseQty(line)),
              Money.format(_purchaseUnitCost(line)),
              Money.format(line.lineTotalCentimes),
            ],
        ],
        border: pw.TableBorder.symmetric(
          inside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerRight,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
        },
        columnWidths: {
          0: const pw.FlexColumnWidth(4),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1.6),
        },
      ),
      pw.SizedBox(height: 12),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                _totalRow('Sous-total', purchase.subtotalCentimes),
                if (purchase.discountCentimes > 0)
                  _totalRow('Remise', -purchase.discountCentimes),
                pw.Divider(),
                _totalRow('Total', purchase.totalCentimes, bold: true),
                _totalRow('Payé', purchase.paidCentimes),
                if (purchase.dueCentimes > 0)
                  _totalRow('Reste à payer', purchase.dueCentimes),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 20),
      if (purchase.note != null && purchase.note!.trim().isNotEmpty)
        text('Note : ${purchase.note}', size: 9),
      pw.SizedBox(height: 10),
      pw.Divider(color: PdfColors.grey400),
      pw.SizedBox(height: 6),
      pw.Center(child: text(shop.footer ?? 'Merci de votre visite', size: 9)),
      pw.Center(
        child: pw.Text(
          'Hydra POS — ${shop.phone ?? ''}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
      ),
    ];
  }

  static int _purchaseQty(PurchaseLine line) => line.factorMilli > 0
      ? (line.qtyMilli * Qty.milliPerUnit) ~/ line.factorMilli
      : line.qtyMilli;

  static int _purchaseUnitCost(PurchaseLine line) {
    if (line.qtyMilli <= 0) return line.unitCostCentimes;
    return (line.lineTotalCentimes * line.factorMilli + line.qtyMilli ~/ 2) ~/
        line.qtyMilli;
  }

  List<pw.Widget> _invoiceContent(
    Sale sale,
    Shop shop,
    bool arabic,
    DateTime date,
  ) {
    pw.Widget text(String value, {bool bold = false, double size = 10}) =>
        _t(value, arabic: arabic, bold: bold, size: size);
    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                shop.name,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (shop.nameAr != null && shop.nameAr!.trim().isNotEmpty)
                _t(shop.nameAr!, arabic: true, size: 13),
              if (shop.address != null) text(shop.address!, size: 9),
              if (shop.phone != null) text(shop.phone!, size: 9),
              if (shop.taxId != null) text('ICE: ${shop.taxId}', size: 9),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              text('FACTURE', bold: true, size: 22),
              pw.SizedBox(height: 6),
              text(sale.invoiceNo, bold: true, size: 12),
              text(Dates.formatDateTime(date), size: 9),
              if (sale.isVoided)
                pw.Text(
                  'ANNULÉE',
                  style: pw.TextStyle(
                    color: PdfColors.red,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Divider(color: PdfColors.grey400),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              text('Client', bold: true, size: 10),
              text(sale.customerName ?? 'Client de passage', size: 11),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              text('Paiement : ${_methodLabel(sale.paymentMethod)}', size: 9),
              text(sale.status == 'completed' ? 'Payée' : 'Annulée', size: 9),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.TableHelper.fromTextArray(
        headers: ['Article', 'Qté', 'P.U.', 'Total'],
        data: [
          for (final line in sale.lines)
            [
              line.productName +
                  (line.unitName.isEmpty ? '' : ' (${line.unitName})'),
              Qty.format(line.displayQtyMilli),
              Money.format(line.displayUnitPriceCentimes),
              Money.format(line.lineTotalCentimes),
            ],
        ],
        border: pw.TableBorder.symmetric(
          inside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerRight,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
        },
        columnWidths: {
          0: const pw.FlexColumnWidth(4),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1.6),
        },
      ),
      pw.SizedBox(height: 12),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                _totalRow('Sous-total', sale.subtotalCentimes),
                if (sale.discountCentimes > 0)
                  _totalRow('Remise', -sale.discountCentimes),
                pw.Divider(),
                _totalRow('Total', sale.totalCentimes, bold: true),
                _totalRow('Payé', sale.paidCentimes),
                if (sale.dueCentimes > 0)
                  _totalRow('Reste à payer', sale.dueCentimes),
                if (sale.returnedCentimes > 0)
                  _totalRow('Retours', -sale.returnedCentimes),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 20),
      if (sale.note != null && sale.note!.trim().isNotEmpty)
        text('Note : ${sale.note}', size: 9),
      pw.SizedBox(height: 10),
      pw.Divider(color: PdfColors.grey400),
      pw.SizedBox(height: 6),
      pw.Center(child: text(shop.footer ?? 'Merci de votre visite', size: 9)),
      pw.Center(
        child: pw.Text(
          'Hydra POS — ${shop.phone ?? ''}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
      ),
    ];
  }

  List<pw.Widget> _receiptContent(
    Sale sale,
    Shop shop,
    bool arabic,
    DateTime date,
  ) {
    String money(int? c) => c == null ? '' : Money.format(c);
    return [
      pw.Center(
        child: pw.Text(
          shop.name,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ),
      if (shop.nameAr != null && shop.nameAr!.trim().isNotEmpty)
        pw.Center(child: _t(shop.nameAr!, arabic: true, size: 11)),
      if (shop.address != null)
        pw.Center(child: _t(shop.address!, arabic: arabic, size: 7)),
      if (shop.phone != null)
        pw.Center(
          child: pw.Text(shop.phone!, style: const pw.TextStyle(fontSize: 7)),
        ),
      pw.SizedBox(height: 4),
      pw.Divider(borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey600),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(sale.invoiceNo, style: const pw.TextStyle(fontSize: 7)),
          pw.Text(
            Dates.formatDateTime(date),
            style: const pw.TextStyle(fontSize: 7),
          ),
        ],
      ),
      if (sale.customerName != null)
        pw.Text(
          'Client: ${sale.customerName}',
          style: const pw.TextStyle(fontSize: 7),
        ),
      pw.Divider(borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey600),
      for (final line in sale.lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _t(line.productName, arabic: arabic, size: 7.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${Qty.format(line.displayQtyMilli)}'
                    '${line.unitName.isEmpty ? '' : ' ${line.unitName}'}'
                    ' x ${money(line.displayUnitPriceCentimes)}',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                  pw.Text(
                    money(line.lineTotalCentimes),
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      pw.Divider(borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey600),
      if (sale.discountCentimes > 0)
        _receiptRow('Remise', money(-sale.discountCentimes)),
      _receiptRow('TOTAL', money(sale.totalCentimes), bold: true, size: 9),
      _receiptRow('Payé', money(sale.paidCentimes)),
      if (sale.dueCentimes > 0) _receiptRow('Reste', money(sale.dueCentimes)),
      if (sale.returnedCentimes > 0)
        _receiptRow('Retours', money(-sale.returnedCentimes)),
      pw.Divider(borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey600),
      pw.Center(
        child: _t(
          shop.footer ?? 'Merci de votre visite',
          arabic: arabic,
          size: 7.5,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          'Hydra POS',
          style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey500),
        ),
      ),
    ];
  }

  pw.Widget _totalRow(String label, int value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            Money.format(value),
            style: pw.TextStyle(
              fontSize: bold ? 11 : 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _receiptRow(
    String label,
    String value, {
    bool bold = false,
    double size = 7.5,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  pw.Widget _t(
    String value, {
    required bool arabic,
    bool bold = false,
    double size = 10,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    final text = pw.Text(
      value,
      textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      textAlign: arabic ? pw.TextAlign.right : align,
      style: pw.TextStyle(
        font: arabic ? _arabic : _latin,
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
    return arabic
        ? pw.Directionality(textDirection: pw.TextDirection.rtl, child: text)
        : text;
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Espèces';
      case 'card':
        return 'Carte';
      case 'credit':
        return 'Crédit';
      case 'cheque':
        return 'Chèque';
      case 'transfer':
        return 'Virement';
      default:
        return method;
    }
  }
}

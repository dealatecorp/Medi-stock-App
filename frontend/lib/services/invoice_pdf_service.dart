import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum InvoicePaperSize { a4, a5, a6, thermal }

extension InvoicePaperSizeDetails on InvoicePaperSize {
  String get label => switch (this) {
    InvoicePaperSize.a4 => 'A4',
    InvoicePaperSize.a5 => 'A5',
    InvoicePaperSize.a6 => 'A6',
    InvoicePaperSize.thermal => 'Thermal 80 mm',
  };

  bool get isCompact =>
      this == InvoicePaperSize.a6 || this == InvoicePaperSize.thermal;

  PdfPageFormat get format => switch (this) {
    InvoicePaperSize.a4 => PdfPageFormat.a4,
    InvoicePaperSize.a5 => PdfPageFormat.a5,
    InvoicePaperSize.a6 => PdfPageFormat.a6,
    InvoicePaperSize.thermal => PdfPageFormat(
      80 * PdfPageFormat.mm,
      297 * PdfPageFormat.mm,
      marginAll: 5 * PdfPageFormat.mm,
    ),
  };
}

/// Builds, prints, and shares immutable invoice snapshots.
class InvoicePdfService {
  InvoicePdfService._();

  static final PdfColor _brand = PdfColor.fromHex('#176B4D');
  static final PdfColor _brandDark = PdfColor.fromHex('#103D30');
  static final PdfColor _brandLight = PdfColor.fromHex('#E8F4EF');
  static final PdfColor _ink = PdfColor.fromHex('#17231F');
  static final PdfColor _muted = PdfColor.fromHex('#63716C');
  static final PdfColor _line = PdfColor.fromHex('#DDE6E2');
  static final PdfColor _surface = PdfColor.fromHex('#F7FAF8');

  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs. ',
    decimalDigits: 2,
  );

  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _date = DateFormat('dd MMM yyyy');

  /// Generates a multi-page PDF for [invoice] and the chosen printer format.
  static Future<Uint8List> generate(
    InvoiceRecord invoice, {
    InvoicePaperSize paperSize = InvoicePaperSize.a4,
    String upiId = '',
  }) async {
    final compact = paperSize.isCompact;
    final document = pw.Document(
      title: 'MediStock invoice ${invoice.number}',
      author: 'MediStock',
      subject: 'Pharmacy invoice for ${invoice.customerName}',
      creator: 'MediStock Mobile',
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: paperSize.format,
          margin: compact
              ? const pw.EdgeInsets.fromLTRB(12, 14, 12, 14)
              : paperSize == InvoicePaperSize.a5
              ? const pw.EdgeInsets.fromLTRB(28, 26, 28, 26)
              : const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        footer: _buildFooter,
        build: (context) => <pw.Widget>[
          _buildHeader(invoice, compact: compact),
          pw.SizedBox(height: compact ? 14 : 20),
          pw.Inseparable(child: _buildCustomerCard(invoice, compact: compact)),
          if (paperSize == InvoicePaperSize.a6) pw.NewPage(freeSpace: 150),
          pw.SizedBox(height: compact ? 17 : 24),
          pw.Text(
            'Bill items',
            style: pw.TextStyle(
              color: _brandDark,
              fontSize: compact ? 11 : 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: compact ? 6 : 9),
          _buildItemsTable(invoice.items, compact: compact),
          pw.SizedBox(height: compact ? 15 : 22),
          _buildTotals(invoice, compact: compact),
          if (upiId.trim().isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: compact ? 14 : 18),
            _buildUpiPayment(invoice, upiId.trim(), compact: compact),
          ],
          pw.SizedBox(height: compact ? 16 : 24),
          pw.Inseparable(
            child: pw.Container(
              width: double.infinity,
              padding: pw.EdgeInsets.symmetric(
                horizontal: compact ? 10 : 16,
                vertical: compact ? 9 : 13,
              ),
              decoration: pw.BoxDecoration(
                color: _brandLight,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    'Thank you for choosing MediStock.',
                    style: pw.TextStyle(
                      color: _brandDark,
                      fontSize: compact ? 9 : 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Please retain this invoice for your records.',
                    style: pw.TextStyle(
                      color: _muted,
                      fontSize: compact ? 7.5 : 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  /// Opens the platform print dialog for [invoice].
  static Future<bool> printInvoice(
    InvoiceRecord invoice, {
    InvoicePaperSize paperSize = InvoicePaperSize.a4,
    String upiId = '',
  }) async {
    final bytes = await generate(invoice, paperSize: paperSize, upiId: upiId);
    return Printing.layoutPdf(
      name: _fileName(invoice),
      format: paperSize.format,
      onLayout: (_) async => bytes,
    );
  }

  /// Opens the native share sheet with the generated invoice PDF attached.
  static Future<bool> shareInvoice(
    InvoiceRecord invoice, {
    InvoicePaperSize paperSize = InvoicePaperSize.a4,
    String upiId = '',
  }) async {
    final bytes = await generate(invoice, paperSize: paperSize, upiId: upiId);
    return Printing.sharePdf(
      bytes: bytes,
      filename: _fileName(invoice),
      subject: 'MediStock invoice ${invoice.number}',
      body:
          'MediStock invoice ${invoice.number} for '
          '${_money(invoice.totalPaise)}.',
    );
  }

  static pw.Widget _buildHeader(
    InvoiceRecord invoice, {
    required bool compact,
  }) {
    final brand = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        pw.Container(
          width: compact ? 32 : 38,
          height: compact ? 32 : 38,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: _brand,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            'M',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: compact ? 18 : 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              'MediStock',
              style: pw.TextStyle(
                color: _brandDark,
                fontSize: compact ? 18 : 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Pharmacy inventory and billing',
              style: pw.TextStyle(color: _muted, fontSize: compact ? 7 : 8.5),
            ),
          ],
        ),
      ],
    );
    final number = pw.Column(
      crossAxisAlignment: compact
          ? pw.CrossAxisAlignment.start
          : pw.CrossAxisAlignment.end,
      children: <pw.Widget>[
        pw.Text(
          'INVOICE',
          style: pw.TextStyle(
            color: _brand,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          invoice.number,
          style: pw.TextStyle(
            color: _ink,
            fontSize: compact ? 11 : 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          _dateTime.format(invoice.createdAt.toLocal()),
          style: pw.TextStyle(color: _muted, fontSize: compact ? 7.5 : 8.5),
        ),
      ],
    );

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 14),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 1.5)),
      ),
      child: compact
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[brand, pw.SizedBox(height: 12), number],
            )
          : pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[brand, number],
            ),
    );
  }

  static pw.Widget _buildCustomerCard(
    InvoiceRecord invoice, {
    required bool compact,
  }) {
    final customerName = invoice.customerName.trim().isEmpty
        ? 'Walk-in patient'
        : invoice.customerName.trim();
    final phone = invoice.customerPhone.trim().isEmpty
        ? 'Not provided'
        : invoice.customerPhone.trim();
    final doctor = invoice.doctorName.trim();
    final paymentMethod = invoice.paymentMethod.trim().isEmpty
        ? 'Cash'
        : invoice.paymentMethod.trim();
    final refillDate = invoice.nextRefillDate;

    final primaryDetails = <pw.Widget>[
      _detail('PATIENT', customerName, compact: compact),
      _detail('PHONE', phone, compact: compact),
      _detail(
        'DATE',
        _date.format(invoice.createdAt.toLocal()),
        compact: compact,
      ),
    ];
    final saleDetails = <pw.Widget>[
      if (doctor.isNotEmpty) _detail('DOCTOR', doctor, compact: compact),
      _detail('PAYMENT', paymentMethod, compact: compact),
      if (refillDate != null)
        _detail(
          'NEXT REFILL',
          _date.format(refillDate.toLocal()),
          compact: compact,
        ),
    ];
    final allDetails = <pw.Widget>[...primaryDetails, ...saleDetails];

    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(compact ? 11 : 16),
      decoration: pw.BoxDecoration(
        color: _surface,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: compact
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                for (var index = 0; index < allDetails.length; index++) ...[
                  if (index > 0) pw.SizedBox(height: 8),
                  allDetails[index],
                ],
              ],
            )
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: <pw.Widget>[
                _detailRow(primaryDetails),
                if (saleDetails.isNotEmpty) ...<pw.Widget>[
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 12),
                    child: pw.Divider(color: _line, height: 1),
                  ),
                  _detailRow(saleDetails),
                ],
              ],
            ),
    );
  }

  static pw.Widget _detailRow(List<pw.Widget> details) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        for (var index = 0; index < details.length; index++) ...<pw.Widget>[
          if (index > 0) ...<pw.Widget>[
            pw.SizedBox(width: 18),
            pw.Container(width: 1, height: 35, color: _line),
            pw.SizedBox(width: 18),
          ],
          pw.Expanded(child: details[index]),
        ],
      ],
    );
  }

  static pw.Widget _detail(
    String label,
    String value, {
    required bool compact,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          label,
          style: pw.TextStyle(
            color: _brand,
            fontSize: compact ? 6.8 : 7.5,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        pw.SizedBox(height: compact ? 3 : 5),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: _ink,
            fontSize: compact ? 8.5 : 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildItemsTable(
    List<InvoiceItem> items, {
    required bool compact,
  }) {
    if (items.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(18),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Text(
          'No bill items.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(color: _muted, fontSize: 10),
        ),
      );
    }

    final headers = compact
        ? const <String>['Item', 'Qty / rate', 'Amount']
        : const <String>['Medicine / batch', 'Qty', 'Rate', 'Disc.', 'Amount'];
    final data = items
        .map((item) {
          final description = item.sku.trim().isEmpty
              ? item.medicineName
              : '${item.medicineName}\n${item.sku.trim()}';
          final discount = item.discountPercent > 0
              ? '${_percentage(item.discountPercent)} off'
              : '-';
          if (compact) {
            return <String>[
              description,
              '${item.quantity} x\n${_money(item.unitPricePaise)}'
                  '${item.discountPercent > 0 ? '\n$discount' : ''}',
              _money(item.lineTotalPaise),
            ];
          }
          return <String>[
            description,
            item.quantity.toString(),
            _money(item.unitPricePaise),
            discount,
            _money(item.lineTotalPaise),
          ];
        })
        .toList(growable: false);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder(
        top: pw.BorderSide(color: _line),
        bottom: pw.BorderSide(color: _line),
        horizontalInside: pw.BorderSide(color: _line, width: 0.5),
      ),
      headerDecoration: pw.BoxDecoration(color: _brand),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: compact ? 7.2 : 9,
        fontWeight: pw.FontWeight.bold,
      ),
      headerAlignment: pw.Alignment.centerLeft,
      headerAlignments: compact
          ? const <int, pw.AlignmentGeometry>{
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
            }
          : const <int, pw.AlignmentGeometry>{
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
      headerPadding: pw.EdgeInsets.symmetric(
        horizontal: compact ? 5 : 6,
        vertical: compact ? 6 : 8,
      ),
      cellStyle: pw.TextStyle(color: _ink, fontSize: compact ? 7.2 : 9),
      oddRowDecoration: pw.BoxDecoration(color: _surface),
      cellAlignments: compact
          ? const <int, pw.AlignmentGeometry>{
              1: pw.Alignment.topCenter,
              2: pw.Alignment.topRight,
            }
          : const <int, pw.AlignmentGeometry>{
              1: pw.Alignment.topCenter,
              2: pw.Alignment.topRight,
              3: pw.Alignment.topRight,
              4: pw.Alignment.topRight,
            },
      cellPadding: pw.EdgeInsets.symmetric(
        horizontal: compact ? 5 : 6,
        vertical: compact ? 6 : 8,
      ),
      columnWidths: compact
          ? const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(1.15),
              2: pw.FlexColumnWidth(1.25),
            }
          : const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(4.1),
              1: pw.FlexColumnWidth(0.75),
              2: pw.FlexColumnWidth(1.55),
              3: pw.FlexColumnWidth(1.15),
              4: pw.FlexColumnWidth(1.7),
            },
    );
  }

  static pw.Widget _buildTotals(
    InvoiceRecord invoice, {
    required bool compact,
  }) {
    return pw.Inseparable(
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: compact ? double.infinity : 245,
          padding: pw.EdgeInsets.all(compact ? 10 : 14),
          decoration: pw.BoxDecoration(
            color: _surface,
            border: pw.Border.all(color: _line),
            borderRadius: pw.BorderRadius.circular(7),
          ),
          child: pw.Column(
            children: <pw.Widget>[
              _totalRow('Subtotal', invoice.subtotalPaise, compact: compact),
              pw.SizedBox(height: compact ? 6 : 8),
              _totalRow('Tax', invoice.taxPaise, compact: compact),
              pw.SizedBox(height: compact ? 6 : 8),
              _totalRow(
                'Discount',
                invoice.discountPaise,
                compact: compact,
                deduction: true,
              ),
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(vertical: compact ? 8 : 10),
                child: pw.Divider(color: _line, height: 1),
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Text(
                    'Total',
                    style: pw.TextStyle(
                      color: _brandDark,
                      fontSize: compact ? 10.5 : 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _money(invoice.totalPaise),
                    style: pw.TextStyle(
                      color: _brand,
                      fontSize: compact ? 11 : 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildUpiPayment(
    InvoiceRecord invoice,
    String upiId, {
    required bool compact,
  }) {
    final paymentUri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: <String, String>{
        'pa': upiId,
        'pn': 'MediStock Pharmacy',
        'am': (invoice.totalPaise / 100).toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'Invoice ${invoice.number}',
      },
    ).toString();
    final qr = pw.BarcodeWidget(
      barcode: pw.Barcode.qrCode(),
      data: paymentUri,
      width: compact ? 76 : 82,
      height: compact ? 76 : 82,
    );
    final details = pw.Column(
      crossAxisAlignment: compact
          ? pw.CrossAxisAlignment.center
          : pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'SCAN TO PAY',
          style: pw.TextStyle(
            color: _brand,
            fontSize: compact ? 7 : 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _money(invoice.totalPaise),
          style: pw.TextStyle(
            color: _brandDark,
            fontSize: compact ? 11 : 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          upiId,
          textAlign: compact ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(color: _muted, fontSize: compact ? 7 : 8),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Payment is verified at the counter.',
          textAlign: compact ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(color: _muted, fontSize: compact ? 6.5 : 7.5),
        ),
      ],
    );

    return pw.Inseparable(
      child: pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.all(compact ? 10 : 12),
        decoration: pw.BoxDecoration(
          color: _surface,
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(7),
        ),
        child: compact
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: <pw.Widget>[qr, pw.SizedBox(height: 8), details],
              )
            : pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: <pw.Widget>[
                  qr,
                  pw.SizedBox(width: 14),
                  pw.Expanded(child: details),
                ],
              ),
      ),
    );
  }

  static pw.Widget _totalRow(
    String label,
    int valuePaise, {
    required bool compact,
    bool deduction = false,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(
          label,
          style: pw.TextStyle(color: _muted, fontSize: compact ? 8 : 9.5),
        ),
        pw.Text(
          deduction && valuePaise > 0
              ? '- ${_money(valuePaise)}'
              : _money(valuePaise),
          style: pw.TextStyle(
            color: _ink,
            fontSize: compact ? 8 : 9.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 9),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'Generated by MediStock Mobile',
            style: pw.TextStyle(color: _muted, fontSize: 7.5),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(color: _muted, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  static String _money(int valuePaise) => _currency.format(valuePaise / 100);

  static String _percentage(double value) {
    final decimals = value == value.roundToDouble() ? 0 : 2;
    return '${value.toStringAsFixed(decimals)}%';
  }

  static String _fileName(InvoiceRecord invoice) {
    final safeNumber = invoice.number.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    return '${safeNumber.isEmpty ? 'MediStock-invoice' : safeNumber}.pdf';
  }
}

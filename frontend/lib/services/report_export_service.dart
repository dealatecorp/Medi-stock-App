import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Builds CSV report snapshots locally and opens the device share sheet.
///
/// No report data is uploaded by this service. Temporary files are written to
/// the app cache and leave the device only when the user selects a share target.
class ReportExportService {
  ReportExportService._();

  static final DateFormat _date = DateFormat('yyyy-MM-dd');

  static Future<ShareResult> shareSales({
    required List<InvoiceRecord> invoices,
    required String periodLabel,
  }) {
    final rows = <List<dynamic>>[
      <dynamic>[
        'Date',
        'Invoice',
        'Customer',
        'Payment method',
        'Items sold',
        'Revenue (excl. GST)',
        'COGS',
        'Gross profit',
        'Margin %',
        'GST collected',
        'Discount',
        'Invoice total',
      ],
      for (final invoice in invoices)
        <dynamic>[
          _date.format(invoice.createdAt.toLocal()),
          invoice.number,
          invoice.customerName,
          invoice.paymentMethod,
          invoice.totalQuantity,
          _rupees(_salesRevenue(invoice)),
          _rupees(_invoiceCogs(invoice)),
          _rupees(_invoiceProfit(invoice)),
          _marginPercent(invoice).toStringAsFixed(2),
          _rupees(invoice.taxPaise),
          _rupees(invoice.discountPaise),
          _rupees(invoice.totalPaise),
        ],
    ];
    return _writeAndShare(
      slug: 'sales-ledger',
      title: 'MediStock sales ledger · $periodLabel',
      rows: rows,
    );
  }

  static Future<ShareResult> sharePurchases({
    required List<PurchaseRecord> purchases,
    required String periodLabel,
  }) {
    final rows = <List<dynamic>>[
      <dynamic>[
        'Invoice date',
        'Supplier invoice',
        'Supplier',
        'Branch',
        'Status',
        'Line items',
        'Units received',
        'COGS / subtotal',
        'Input GST',
        'Supplier payable',
      ],
      for (final purchase in purchases)
        <dynamic>[
          _date.format(purchase.invoiceDate.toLocal()),
          purchase.invoiceNumber,
          purchase.supplierName,
          purchase.branch,
          purchase.status,
          purchase.lines.length,
          purchase.lines.fold<int>(
            0,
            (sum, line) => sum + line.receivedQuantity,
          ),
          _rupees(purchase.subtotalPaise),
          _rupees(purchase.gstPaise),
          _rupees(purchase.totalPaise),
        ],
    ];
    return _writeAndShare(
      slug: 'purchase-ledger',
      title: 'MediStock purchase ledger · $periodLabel',
      rows: rows,
    );
  }

  static Future<ShareResult> shareGst({
    required List<InvoiceRecord> invoices,
    required List<PurchaseRecord> purchases,
    required String periodLabel,
  }) {
    final outputGst = invoices.fold<int>(
      0,
      (sum, invoice) => sum + invoice.taxPaise,
    );
    final completedPurchases = purchases.where(
      (purchase) => purchase.status == 'completed',
    );
    final inputGst = completedPurchases.fold<int>(
      0,
      (sum, purchase) => sum + purchase.gstPaise,
    );
    final rows = <List<dynamic>>[
      <dynamic>['GST summary', periodLabel],
      <dynamic>['Output GST collected', _rupees(outputGst)],
      <dynamic>['Input GST paid', _rupees(inputGst)],
      <dynamic>['Estimated net GST', _rupees(outputGst - inputGst)],
      <dynamic>[],
      <dynamic>['Type', 'Date', 'Reference', 'Party', 'GST amount'],
      for (final invoice in invoices)
        <dynamic>[
          'Sale',
          _date.format(invoice.createdAt.toLocal()),
          invoice.number,
          invoice.customerName,
          _rupees(invoice.taxPaise),
        ],
      for (final purchase in completedPurchases)
        <dynamic>[
          'Purchase',
          _date.format(purchase.invoiceDate.toLocal()),
          purchase.invoiceNumber,
          purchase.supplierName,
          _rupees(purchase.gstPaise),
        ],
    ];
    return _writeAndShare(
      slug: 'gst-summary',
      title: 'MediStock GST summary · $periodLabel',
      rows: rows,
    );
  }

  static Future<ShareResult> shareExpiry({required List<Medicine> medicines}) {
    final now = DateTime.now();
    final rows = <List<dynamic>>[
      <dynamic>[
        'Medicine',
        'Batch / SKU',
        'Branch',
        'Expiry date',
        'Expiry state',
        'Stock',
        'Unit cost',
        'Stock value',
      ],
      for (final medicine in medicines)
        if (medicine.expiryDate != null)
          <dynamic>[
            medicine.name,
            medicine.sku,
            medicine.branch,
            _date.format(medicine.expiryDate!.toLocal()),
            _expiryState(medicine.expiryDate!, now),
            medicine.stock,
            _rupees(medicine.costPaise),
            _rupees(medicine.stockValuePaise),
          ],
    ];
    return _writeAndShare(
      slug: 'expiry-audit',
      title: 'MediStock stock expiry audit',
      rows: rows,
    );
  }

  static Future<ShareResult> _writeAndShare({
    required String slug,
    required String title,
    required List<List<dynamic>> rows,
  }) async {
    final directory = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File('${directory.path}/medistock-$slug-$stamp.csv');
    final contents = '\ufeff${csv.encode(rows)}';
    await file.writeAsString(contents, flush: true);
    return SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
        subject: title,
        text: '$title. Generated locally on this device.',
      ),
    );
  }

  static int _invoiceCogs(InvoiceRecord invoice) => invoice.items.fold<int>(
    0,
    (sum, item) => sum + (item.costPaise * item.quantity),
  );

  static int _salesRevenue(InvoiceRecord invoice) =>
      (invoice.subtotalPaise - invoice.discountPaise).clamp(0, 1 << 62).toInt();

  static int _invoiceProfit(InvoiceRecord invoice) =>
      _salesRevenue(invoice) - _invoiceCogs(invoice);

  static double _marginPercent(InvoiceRecord invoice) {
    final revenue = _salesRevenue(invoice);
    if (revenue <= 0) return 0;
    return _invoiceProfit(invoice) * 100 / revenue;
  }

  static String _expiryState(DateTime expiry, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final value = DateTime(expiry.year, expiry.month, expiry.day);
    if (value.isBefore(day)) return 'Expired';
    if (value.isBefore(_addMonths(day, 3))) return 'Under 3 months';
    if (value.isBefore(_addMonths(day, 6))) return '3–6 months';
    return 'Beyond 6 months';
  }

  static DateTime _addMonths(DateTime value, int months) {
    final targetMonth = value.month + months;
    final year = value.year + (targetMonth - 1) ~/ 12;
    final month = (targetMonth - 1) % 12 + 1;
    final finalDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, value.day.clamp(1, finalDay));
  }

  static String _rupees(int paise) => (paise / 100).toStringAsFixed(2);
}

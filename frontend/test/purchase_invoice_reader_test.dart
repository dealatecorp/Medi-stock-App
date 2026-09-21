import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_mobile/services/purchase_invoice_reader.dart';

void main() {
  group('PurchaseInvoiceNumberParser', () {
    test('reads a labelled supplier invoice number', () {
      expect(
        PurchaseInvoiceNumberParser.extract(
          'Supplier: ABC Pharma\nTax Invoice No: INV/2026/0042\n'
          'Date: 21/09/2026\nTotal: 135000.00',
        ),
        'INV/2026/0042',
      );
    });

    test('reads OCR label and value on separate lines', () {
      expect(
        PurchaseInvoiceNumberParser.extract('Inv. No:\nAB-1234\nGSTIN: 123'),
        'AB-1234',
      );
    });

    test('accepts a repeated same number', () {
      expect(
        PurchaseInvoiceNumberParser.extract(
          'Invoice # AB-123\nInvoice Number: AB-123',
        ),
        'AB-123',
      );
    });

    test('preserves supplier casing while comparing repeats case-insensitively', () {
      expect(
        PurchaseInvoiceNumberParser.extract(
          'Invoice No: ph-007\nInvoice Number: PH-007',
        ),
        'ph-007',
      );
    });

    test('does not guess from totals, dates, or unlabelled IDs', () {
      expect(
        PurchaseInvoiceNumberParser.extract(
          'Tax Invoice\nDate: 21/09/2026\nGSTIN: 29ABCDE1234F1Z5\n'
          'Grand Total: 135000',
        ),
        isNull,
      );
      expect(
        PurchaseInvoiceNumberParser.extract('Invoice No: 2026-09-21'),
        isNull,
      );
    });

    test('does not propose a number when labels conflict', () {
      expect(
        PurchaseInvoiceNumberParser.extract(
          'Invoice No: A-100\nBill No: B-200',
        ),
        isNull,
      );
    });

    test('does not treat a missing value as the next field', () {
      expect(
        PurchaseInvoiceNumberParser.extract('Invoice No:\nDate: 21/09/2026'),
        isNull,
      );
    });
  });
}

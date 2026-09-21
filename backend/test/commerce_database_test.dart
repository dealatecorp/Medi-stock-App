import 'dart:io';

import 'package:medistock_backend/medistock_backend.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'medistock_commerce_test_',
    );
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'autosaves drafts, fuzzy matches, completes once, and keeps history',
    () async {
      final database = AppDatabase.instance;
      final supplier = await database.saveSupplier(
        const Supplier(
          name: '  Healthline Distributors  ',
          phone: '9876543210',
          email: 'ORDERS@HEALTHLINE.TEST',
          gstNumber: '29abc123',
        ),
      );
      expect(supplier.name, 'Healthline Distributors');
      expect(supplier.email, 'orders@healthline.test');

      final medicine = await database.saveMedicine(
        const Medicine(
          name: 'Paracetamol 500mg Tablets',
          genericName: 'Paracetamol',
          composition: 'Paracetamol IP 500mg',
          scheduleCategory: 'Schedule H',
          dosageForm: 'Tablet',
          sku: 'PCM-OLD-BATCH',
          branch: 'Main Branch',
          stock: 10,
          reorderThreshold: 3,
          costPaise: 125,
          pricePaise: 250,
        ),
      );

      final matches = await database.findMedicineCandidates('Paracetmol 500mg');
      expect(matches, isNotEmpty);
      expect(matches.first.medicine.id, medicine.id);
      expect(matches.first.score, greaterThan(0.7));

      final draft = await database.savePurchase(
        PurchaseRecord(
          supplierId: supplier.id!,
          invoiceNumber: 'HL-2026-77',
          invoiceDate: DateTime(2026, 9, 18),
          branch: 'Main Branch',
          lines: <PurchaseLine>[
            PurchaseLine(
              medicineId: medicine.id,
              productName: 'Paracetmol 500 mg',
              batchNumber: 'PCM-NEW-BATCH',
              expiryDate: DateTime(2028, 6, 30),
              billedQuantity: 2,
              freeQuantity: 1,
              mrpPaise: 325,
              purchaseRatePaise: 180,
              gstPercent: 5,
              matchState: 'partial',
              matchScore: 0.88,
            ),
          ],
        ),
      );
      expect(draft.isDraft, isTrue);
      expect(draft.supplierName, supplier.name);
      expect(draft.subtotalPaise, 360);
      expect(draft.gstPaise, 18);
      expect(draft.totalPaise, 378);

      final autosaved = await database.savePurchase(
        draft.copyWith(
          lines: <PurchaseLine>[
            draft.lines.single.copyWith(billedQuantity: 4, freeQuantity: 2),
          ],
        ),
      );
      expect(autosaved.lines, hasLength(1));
      expect(autosaved.lines.single.receivedQuantity, 6);
      expect(await database.listPurchases(search: 'healthline'), hasLength(1));
      expect(await database.listPurchases(status: 'draft'), hasLength(1));
      expect(await database.getLastPurchaseInfo(medicine.id!), isNull);

      final completed = await database.completePurchase(autosaved.id!);
      expect(completed.isCompleted, isTrue);
      final updatedMedicine = await database.getMedicine(medicine.id!);
      expect(updatedMedicine?.stock, 16);
      expect(updatedMedicine?.costPaise, 180);
      expect(updatedMedicine?.pricePaise, 325);
      expect(updatedMedicine?.expiryDate, DateTime(2028, 6, 30));

      final history = await database.getLastPurchaseInfo(medicine.id!);
      expect(history?.purchaseRatePaise, 180);
      expect(history?.supplierName, supplier.name);
      expect(history?.invoiceDate, DateTime(2026, 9, 18));

      await expectLater(
        database.completePurchase(completed.id!),
        throwsA(isA<StateError>()),
      );
      expect((await database.getMedicine(medicine.id!))?.stock, 16);
      await expectLater(
        database.deletePurchase(completed.id!),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        database.deleteSupplier(supplier.id!),
        throwsA(isA<StateError>()),
      );

      await database.clearAllData();
      expect(await database.listPurchases(), isEmpty);
      expect(await database.listSuppliers(), isEmpty);
      expect(await database.listMedicines(), isEmpty);
    },
  );

  test('completion rejects medicine mappings from another branch', () async {
    final database = AppDatabase.instance;
    final supplier = await database.saveSupplier(
      const Supplier(name: 'Cross-branch supplier'),
    );
    final medicine = await database.saveMedicine(
      const Medicine(
        name: 'Paracetamol',
        sku: 'PCM-MAIN',
        branch: 'Main Branch',
        stock: 5,
        reorderThreshold: 2,
        costPaise: 100,
        pricePaise: 200,
      ),
    );
    final purchase = await database.savePurchase(
      PurchaseRecord(
        supplierId: supplier.id!,
        invoiceNumber: 'CITY-FOREIGN-1',
        invoiceDate: DateTime(2026, 9, 21),
        branch: 'City Branch',
        lines: <PurchaseLine>[
          PurchaseLine(
            medicineId: medicine.id,
            productName: 'Paracetamol',
            billedQuantity: 3,
            purchaseRatePaise: 100,
            mrpPaise: 200,
          ),
        ],
      ),
    );

    await expectLater(
      database.completePurchase(purchase.id!),
      throwsStateError,
    );
    expect((await database.getMedicine(medicine.id!))?.stock, 5);
    expect((await database.getPurchase(purchase.id!))?.isDraft, isTrue);
  });

  test('completion rejects unmapped lines without changing stock', () async {
    final database = AppDatabase.instance;
    final supplier = await database.saveSupplier(
      const Supplier(name: 'Offline Supplier'),
    );
    final medicine = await database.saveMedicine(
      const Medicine(
        name: 'Cetirizine',
        sku: 'CTZ-1',
        branch: 'City Branch',
        stock: 7,
        reorderThreshold: 2,
        costPaise: 50,
        pricePaise: 100,
      ),
    );
    final draft = await database.savePurchase(
      PurchaseRecord(
        supplierId: supplier.id!,
        invoiceNumber: 'OFF-1',
        invoiceDate: DateTime(2026, 9, 18),
        branch: 'City Branch',
        lines: const <PurchaseLine>[
          PurchaseLine(productName: 'Unknown item', billedQuantity: 2),
        ],
      ),
    );

    await expectLater(
      database.completePurchase(draft.id!),
      throwsA(isA<StateError>()),
    );
    expect((await database.getMedicine(medicine.id!))?.stock, 7);
    expect((await database.getPurchase(draft.id!))?.isDraft, isTrue);
  });

  test('stores enhanced invoice snapshots and combines discounts', () async {
    final database = AppDatabase.instance;
    final medicine = await database.saveMedicine(
      const Medicine(
        name: 'Amoxicillin',
        sku: 'AMX-1',
        branch: 'Main Branch',
        stock: 10,
        reorderThreshold: 2,
        costPaise: 400,
        pricePaise: 1000,
      ),
    );
    final refill = DateTime(2026, 10, 18);
    final invoice = await database.createInvoice(
      cartItems: <CartItem>[
        CartItem.fromMedicine(
          medicine,
          quantity: 2,
        ).copyWith(discountPercent: 10),
      ],
      customerName: 'Anita',
      customerPhone: '9000000000',
      doctorName: 'Dr Mehta',
      paymentMethod: 'UPI',
      nextRefillDate: refill,
      taxPercent: 5,
      discountPercent: 5,
    );

    expect(invoice.subtotalPaise, 2000);
    expect(invoice.taxPaise, 100);
    expect(invoice.discountPaise, 300);
    expect(invoice.totalPaise, 1800);
    expect(invoice.doctorName, 'Dr Mehta');
    expect(invoice.paymentMethod, 'UPI');
    expect(invoice.nextRefillDate, refill);
    expect(invoice.items.single.discountPercent, 10);
    expect(invoice.items.single.costPaise, 400);
    expect(invoice.items.single.lineTotalPaise, 1800);

    final reloaded = await database.getInvoice(invoice.id!);
    expect(reloaded?.doctorName, 'Dr Mehta');
    expect(reloaded?.paymentMethod, 'UPI');
    expect(reloaded?.nextRefillDate, refill);
    expect(reloaded?.items.single.costPaise, 400);
    expect((await database.getMedicine(medicine.id!))?.stock, 8);
  });

  test(
    'upgrades a version 2 database with commerce columns and tables',
    () async {
      final legacy = await databaseFactory.openDatabase(
        path.join(temporaryDirectory.path, 'medistock.db'),
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (database, _) async {
            await database.execute('''
            CREATE TABLE medicines (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              barcode TEXT NOT NULL DEFAULT '',
              barcode_digits TEXT NOT NULL DEFAULT '',
              name TEXT NOT NULL,
              generic_name TEXT NOT NULL DEFAULT '',
              brand_name TEXT NOT NULL DEFAULT '',
              composition TEXT NOT NULL DEFAULT '',
              sku TEXT NOT NULL,
              manufacturer TEXT NOT NULL DEFAULT '',
              mfg_date TEXT,
              expiry_date TEXT,
              branch TEXT NOT NULL,
              stock INTEGER NOT NULL DEFAULT 0,
              threshold_qty INTEGER NOT NULL DEFAULT 0,
              cost_paise INTEGER NOT NULL DEFAULT 0,
              price_paise INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE invoices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_number TEXT NOT NULL UNIQUE,
              customer_name TEXT NOT NULL DEFAULT '',
              customer_phone TEXT NOT NULL DEFAULT '',
              subtotal_paise INTEGER NOT NULL DEFAULT 0,
              tax_paise INTEGER NOT NULL DEFAULT 0,
              discount_paise INTEGER NOT NULL DEFAULT 0,
              total_paise INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE invoice_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_id INTEGER NOT NULL,
              medicine_id INTEGER,
              medicine_name TEXT NOT NULL,
              sku TEXT NOT NULL DEFAULT '',
              qty INTEGER NOT NULL,
              price_paise INTEGER NOT NULL DEFAULT 0,
              line_total_paise INTEGER NOT NULL DEFAULT 0
            )
          ''');
            await database.execute('''
            CREATE TABLE branches (
              name TEXT PRIMARY KEY COLLATE NOCASE,
              is_active INTEGER NOT NULL DEFAULT 1,
              display_order INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
            final now = DateTime(2026, 1, 1).toIso8601String();
            for (final entry in medistockBranches.indexed) {
              await database.insert('branches', <String, Object?>{
                'name': entry.$2,
                'is_active': 1,
                'display_order': entry.$1,
                'created_at': now,
                'updated_at': now,
              });
            }
          },
        ),
      );
      await legacy.close();

      final upgraded = await AppDatabase.instance.database;
      expect(await upgraded.getVersion(), 5);
      final medicineColumns = await upgraded.rawQuery(
        'PRAGMA table_info(medicines)',
      );
      expect(
        medicineColumns.map((column) => column['name']),
        containsAll(<String>['schedule_category', 'dosage_form']),
      );
      final invoiceColumns = await upgraded.rawQuery(
        'PRAGMA table_info(invoices)',
      );
      expect(
        invoiceColumns.map((column) => column['name']),
        containsAll(<String>[
          'doctor_name',
          'payment_method',
          'next_refill_date',
        ]),
      );
      final tables = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        tables.map((table) => table['name']),
        containsAll(<String>['suppliers', 'purchases', 'purchase_lines']),
      );
    },
  );
}

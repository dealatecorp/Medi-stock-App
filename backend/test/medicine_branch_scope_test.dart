import 'dart:io';

import 'package:medistock_backend/medistock_backend.dart';
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
      'medistock_branch_scope_test_',
    );
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'staff medicine reads, writes, and stock totals stay in branch',
    () async {
      final database = AppDatabase.instance;
      const mainMedicine = Medicine(
        barcode: '8901234560001',
        name: 'Main pain relief',
        sku: 'PAIN-01',
        branch: 'Main Branch',
        stock: 10,
        reorderThreshold: 2,
        costPaise: 100,
        pricePaise: 200,
      );
      const cityMedicine = Medicine(
        barcode: '8901234560002',
        name: 'City pain relief',
        sku: 'PAIN-01',
        branch: 'City Branch',
        stock: 3,
        reorderThreshold: 5,
        costPaise: 300,
        pricePaise: 400,
      );
      final main = await database.saveMedicine(mainMedicine);
      final city = await database.saveMedicine(cityMedicine);

      expect(await database.listMedicines(), hasLength(2));
      expect(
        (await database.listMedicines(branch: 'main branch')).single.id,
        main.id,
      );
      expect(
        await database.searchMedicines('city', branch: 'Main Branch'),
        isEmpty,
      );
      expect(
        (await database.lookupMedicineByBarcode(
          main.barcode,
          branch: 'Main Branch',
        ))?.id,
        main.id,
      );
      expect(
        await database.lookupMedicineByBarcode(
          city.barcode,
          branch: 'Main Branch',
        ),
        isNull,
      );
      expect(
        await database.getMedicine(city.id!, branch: 'Main Branch'),
        isNull,
      );
      expect(
        await database.getBranchAvailability(main.id!, branch: 'Main Branch'),
        hasLength(1),
      );
      expect(
        await database.getBranchAvailability(city.id!, branch: 'Main Branch'),
        isEmpty,
      );
      expect(
        (await database.findMedicineCandidates(
          'pain relief',
          branch: 'Main Branch',
        )).map((match) => match.medicine.id),
        <int?>[main.id],
      );

      final stats = await database.getDashboardStats(branch: 'Main Branch');
      expect(stats.totalMedicines, 1);
      expect(stats.stockValuePaise, 1000);
      expect(stats.lowStockCount, 0);

      await expectLater(
        database.saveMedicine(city.copyWith(stock: 0), branch: 'Main Branch'),
        throwsStateError,
      );
      await expectLater(
        database.saveMedicine(
          main.copyWith(branch: 'City Branch'),
          branch: 'Main Branch',
        ),
        throwsStateError,
      );
      await expectLater(
        database.saveMedicine(cityMedicine, branch: 'Main Branch'),
        throwsStateError,
      );
      await expectLater(
        database.createInvoice(
          cartItems: <CartItem>[CartItem.fromMedicine(city)],
          customerPhone: '9876543210',
          branch: 'Main Branch',
        ),
        throwsStateError,
      );
      expect(
        await database.deleteMedicine(city.id!, branch: 'Main Branch'),
        isFalse,
      );
      expect((await database.getMedicine(city.id!))?.stock, 3);

      final updated = await database.saveMedicine(
        main.copyWith(stock: 8),
        branch: 'Main Branch',
      );
      expect(updated.stock, 8);
      expect(
        await database.deleteMedicine(main.id!, branch: 'Main Branch'),
        isTrue,
      );
      expect(await database.listMedicines(), hasLength(1));
    },
  );
}

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
      'medistock_branch_order_test_',
    );
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('request, dispatch, and receive move stock exactly once', () async {
    final database = AppDatabase.instance;
    final source = await database.saveMedicine(
      const Medicine(
        name: 'Paracetamol 500 mg',
        genericName: 'Paracetamol',
        sku: 'PCM-500',
        branch: 'Main Branch',
        stock: 5,
        reorderThreshold: 2,
        costPaise: 100,
        pricePaise: 150,
      ),
    );
    final target = await database.saveMedicine(
      const Medicine(
        name: 'Paracetamol 500 mg',
        sku: 'PCM-500',
        branch: 'City Branch',
        stock: 0,
        reorderThreshold: 2,
        costPaise: 100,
        pricePaise: 150,
      ),
    );

    await expectLater(
      database.createBranchOrder(
        sourceMedicineId: source.id!,
        destinationBranch: 'City Branch',
        quantity: 3,
        requestedBy: 'City clerk',
        requestingBranch: 'North Branch',
      ),
      throwsStateError,
    );
    final requested = await database.createBranchOrder(
      sourceMedicineId: source.id!,
      destinationBranch: 'City Branch',
      quantity: 3,
      requestedBy: 'City clerk',
      requestingBranch: 'City Branch',
    );
    expect(requested.isRequested, isTrue);
    expect(
      await database.listBranchOrders(branch: 'City Branch'),
      hasLength(1),
    );
    expect(await database.listBranchOrders(branch: 'North Branch'), isEmpty);
    expect((await database.getMedicine(source.id!))?.stock, 5);

    await expectLater(database.deleteMedicine(source.id!), throwsStateError);
    await expectLater(
      database.dispatchBranchOrder(requested.id, actorBranch: 'City Branch'),
      throwsStateError,
    );
    final dispatched = await database.dispatchBranchOrder(
      requested.id,
      actorBranch: 'Main Branch',
    );
    expect(dispatched.isDispatched, isTrue);
    expect((await database.getMedicine(source.id!))?.stock, 2);
    await expectLater(
      database.dispatchBranchOrder(requested.id),
      throwsStateError,
    );

    await expectLater(
      database.receiveBranchOrder(requested.id, actorBranch: 'Main Branch'),
      throwsStateError,
    );
    final received = await database.receiveBranchOrder(
      requested.id,
      actorBranch: 'City Branch',
    );
    expect(received.isReceived, isTrue);
    expect((await database.getMedicine(target.id!))?.stock, 3);
    await expectLater(
      database.receiveBranchOrder(requested.id),
      throwsStateError,
    );
    expect((await database.getMedicine(target.id!))?.stock, 3);
  });

  test('receipt creates missing destination medicine; cancellation changes no stock', () async {
    final database = AppDatabase.instance;
    final source = await database.saveMedicine(
      const Medicine(
        name: 'Amoxicillin 250 mg',
        sku: 'AMX-250',
        branch: 'Main Branch',
        stock: 6,
        reorderThreshold: 1,
        costPaise: 300,
        pricePaise: 450,
      ),
    );
    final cancelled = await database.createBranchOrder(
      sourceMedicineId: source.id!,
      destinationBranch: 'South Branch',
      quantity: 2,
      requestedBy: 'South clerk',
    );
    expect(
      (await database.cancelBranchOrder(
        cancelled.id,
        actorBranch: 'South Branch',
      )).isCancelled,
      isTrue,
    );
    await expectLater(
      database.dispatchBranchOrder(cancelled.id),
      throwsStateError,
    );
    expect((await database.getMedicine(source.id!))?.stock, 6);

    final order = await database.createBranchOrder(
      sourceMedicineId: source.id!,
      destinationBranch: 'South Branch',
      quantity: 4,
      requestedBy: 'South clerk',
    );
    await database.dispatchBranchOrder(order.id);
    await database.receiveBranchOrder(order.id);
    final target = (await database.listMedicines(branch: 'South Branch'))
        .single;
    expect(target.sku, source.sku);
    expect(target.stock, 4);
    expect(target.pricePaise, source.pricePaise);
    expect((await database.getMedicine(source.id!))?.stock, 2);
  });

  test('dispatch fails safely if source stock falls after request', () async {
    final database = AppDatabase.instance;
    final source = await database.saveMedicine(
      const Medicine(
        name: 'Cough syrup',
        sku: 'COUGH-1',
        branch: 'Main Branch',
        stock: 3,
        reorderThreshold: 1,
        costPaise: 200,
        pricePaise: 300,
      ),
    );
    final order = await database.createBranchOrder(
      sourceMedicineId: source.id!,
      destinationBranch: 'City Branch',
      quantity: 3,
      requestedBy: 'City clerk',
    );
    await database.saveMedicine(source.copyWith(stock: 2));
    await expectLater(database.dispatchBranchOrder(order.id), throwsStateError);
    expect((await database.getMedicine(source.id!))?.stock, 2);
    expect((await database.getBranchOrder(order.id))?.isRequested, isTrue);
  });

  test(
    'version 4 databases gain orders without losing medicine stock',
    () async {
      final database = AppDatabase.instance;
      final medicine = await database.saveMedicine(
        const Medicine(
          name: 'Existing stock',
          sku: 'EXISTING-1',
          branch: 'Main Branch',
          stock: 9,
          reorderThreshold: 2,
          costPaise: 100,
          pricePaise: 150,
        ),
      );
      final raw = await database.database;
      await raw.execute('DROP TABLE branch_orders');
      await raw.execute('PRAGMA user_version = 4');
      await database.close();

      expect((await database.getMedicine(medicine.id!))?.stock, 9);
      expect(await database.listBranchOrders(), isEmpty);
      final order = await database.createBranchOrder(
        sourceMedicineId: medicine.id!,
        destinationBranch: 'City Branch',
        quantity: 2,
        requestedBy: 'City clerk',
      );
      expect(order.isRequested, isTrue);
    },
  );
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:medistock_mobile/core/app_theme.dart';
import 'package:medistock_mobile/screens/inventory_screen.dart';
import 'package:medistock_mobile/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'medistock_staff_inventory_test_',
    );
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  testWidgets('staff sees all branches but can edit only its own branch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final database = AppDatabase.instance;
    late AppController controller;
    const ownMedicine = Medicine(
      name: 'Own branch tablets',
      sku: 'OWN-1',
      barcode: '8901234560012',
      branch: 'City Branch',
      stock: 10,
      reorderThreshold: 2,
      costPaise: 100,
      pricePaise: 150,
    );
    const foreignMedicine = Medicine(
      name: 'Other branch tablets',
      sku: 'OTHER-1',
      barcode: '8901234560013',
      branch: 'Main Branch',
      stock: 10,
      reorderThreshold: 2,
      costPaise: 100,
      pricePaise: 150,
    );
    await tester.runAsync(() async {
      await database.saveMedicine(ownMedicine);
      final foreign = await database.saveMedicine(foreignMedicine);
      await database.saveStaff(
        const StaffMember(
          name: 'City clerk',
          email: 'city@example.com',
          role: 'Pharmacist',
          branch: 'City Branch',
        ),
        pin: '1234',
      );
      controller = AppController(
        database: database,
        preferences: await SharedPreferences.getInstance(),
      );
      expect(await controller.loginStaff('city@example.com', '1234'), isTrue);
      expect(controller.staffBranch, 'City Branch');
      expect(
        controller.medicines.map((medicine) => medicine.name),
        containsAll(<String>['Own branch tablets', 'Other branch tablets']),
      );
      expect(await controller.lookupBarcode(foreignMedicine.barcode), isNull);
      expect(() => controller.addToCart(foreign, 1), throwsStateError);
      await expectLater(
        controller.saveMedicine(foreign.copyWith(stock: 0)),
        throwsStateError,
      );
      expect((await database.getMedicine(foreign.id!))?.stock, 10);
    });
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: InventoryScreen(controller: controller)),
      ),
    );
    expect(find.text('Own branch tablets'), findsOneWidget);
    expect(find.text('Other branch tablets'), findsOneWidget);
    final foreignCard = find
        .ancestor(
          of: find.text('Other branch tablets'),
          matching: find.byType(Card),
        )
        .first;
    expect(
      find.descendant(of: foreignCard, matching: find.byTooltip('Edit')),
      findsNothing,
    );
    expect(
      find.descendant(of: foreignCard, matching: find.byTooltip('Delete')),
      findsNothing,
    );
    unawaited(
      showMedicineFormSheet(
        tester.element(find.byType(InventoryScreen)),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Assigned branch'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Assigned branch'), findsOneWidget);
    expect(find.text('City Branch'), findsWidgets);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });
}

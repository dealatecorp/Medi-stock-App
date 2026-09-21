import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:medistock_mobile/core/app_theme.dart';
import 'package:medistock_mobile/screens/purchases_screen.dart';
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
      'medistock_purchase_ui_test_',
    );
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<PurchaseRecord> seedPurchase(String branch, String number) async {
    final database = AppDatabase.instance;
    final supplier = await database.saveSupplier(
      Supplier(name: 'Supplier $number'),
    );
    return database.savePurchase(
      PurchaseRecord(
        supplierId: supplier.id!,
        invoiceNumber: number,
        invoiceDate: DateTime(2026, 9, 21),
        branch: branch,
      ),
    );
  }

  testWidgets('purchase history displays saved records with a visible action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = (await tester.runAsync(() async {
      await seedPurchase('Main Branch', 'MAIN-100');
      final controller = AppController(
        database: AppDatabase.instance,
        preferences: await SharedPreferences.getInstance(),
      );
      await controller.login(
        AppController.validEmail,
        AppController.validPassword,
      );
      return controller;
    }))!;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: PurchasesScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Purchase history · 1'), findsOneWidget);
    expect(find.text('MAIN-100'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'staff purchase history and receiving branch stay in their branch',
    (tester) async {
      tester.view.physicalSize = const Size(393, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = (await tester.runAsync(() async {
        final otherBranchPurchase = await seedPurchase(
          'Main Branch',
          'MAIN-100',
        );
        await seedPurchase('City Branch', 'CITY-200');
        await AppDatabase.instance.saveStaff(
          const StaffMember(
            name: 'Asha Rao',
            email: 'asha@example.com',
            role: 'Pharmacist',
            branch: 'City Branch',
          ),
          pin: '4826',
        );
        final controller = AppController(
          database: AppDatabase.instance,
          preferences: await SharedPreferences.getInstance(),
        );
        expect(await controller.loginStaff('asha@example.com', '4826'), isTrue);
        await expectLater(
          controller.savePurchase(otherBranchPurchase),
          throwsStateError,
        );
        await expectLater(
          controller.deletePurchase(otherBranchPurchase.id!),
          throwsStateError,
        );
        return controller;
      }))!;
      addTearDown(controller.dispose);

      expect(
        controller.purchases.map((purchase) => purchase.invoiceNumber),
        <String>['CITY-200'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: PurchasesScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CITY-200'), findsOneWidget);
      expect(find.text('MAIN-100'), findsNothing);

      await tester.tap(find.text('Add purchase').first);
      await tester.pumpAndSettle();
      expect(find.text('City Branch'), findsWidgets);
      expect(
        find.text('Assigned automatically from your staff profile'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

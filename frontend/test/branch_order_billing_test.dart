import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:medistock_mobile/core/app_theme.dart';
import 'package:medistock_mobile/screens/billing_screen.dart';
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
      'medistock_billing_order_test_',
    );
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  testWidgets(
    'out-of-stock billing shows source branch and requests an order',
    (tester) async {
      tester.view.physicalSize = const Size(393, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late AppController controller;
      await tester.runAsync(() async {
        final database = AppDatabase.instance;
        await database.saveMedicine(
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
        await database.saveMedicine(
          const Medicine(
            name: 'Paracetamol 500 mg',
            sku: 'PCM-500',
            branch: 'Main Branch',
            stock: 5,
            reorderThreshold: 2,
            costPaise: 100,
            pricePaise: 150,
          ),
        );
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
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: BillingScreen(controller: controller)),
        ),
      );

      // The freshest item is at Main Branch; choose the City record explicitly.
      final dropdown = find.byType(DropdownButton<int>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('City Branch').last);
      await tester.pumpAndSettle();

      expect(find.text('Need 1 more at City Branch'), findsOneWidget);
      expect(find.text('Main Branch · 5 available'), findsOneWidget);
      await tester.ensureVisible(find.text('Order').first);
      await tester.tap(find.text('Order').first);
      await tester.pumpAndSettle();
      expect(find.text('Request branch stock'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Request'));
      await tester.pump();
      await tester.runAsync(() async {
        for (
          var attempt = 0;
          attempt < 40 && controller.branchOrders.isEmpty;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.branchOrders, hasLength(1));
      expect(controller.branchOrders.single.destinationBranch, 'City Branch');
      expect(controller.branchOrders.single.sourceBranch, 'Main Branch');
      expect(controller.branchOrders.single.isRequested, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

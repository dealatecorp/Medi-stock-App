import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:medistock_mobile/core/app_theme.dart';
import 'package:medistock_mobile/screens/invoices_screen.dart';
import 'package:medistock_mobile/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InvoiceController extends AppController {
  _InvoiceController(SharedPreferences preferences)
    : super(database: AppDatabase.instance, preferences: preferences);

  @override
  UnmodifiableListView<InvoiceRecord> get invoices => UnmodifiableListView([
    InvoiceRecord(
      id: 1,
      number: 'INV-2026-0042',
      customerName: 'Riya Shah',
      customerPhone: '9876543210',
      subtotalPaise: 12500,
      taxPaise: 0,
      discountPaise: 0,
      totalPaise: 12500,
      createdAt: DateTime(2026, 9, 21),
    ),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved invoices render without a hidden loading transition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = _InvoiceController(
      await SharedPreferences.getInstance(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: InvoicesScreen(controller: controller)),
      ),
    );

    expect(find.text('Invoice history'), findsOneWidget);
    expect(find.text('INV-2026-0042'), findsOneWidget);
    expect(find.text('No invoices yet'), findsNothing);
    expect(find.text('INV-2026-0042').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:medistock_mobile/core/app_theme.dart';
import 'package:medistock_mobile/screens/sales_screen.dart';
import 'package:medistock_mobile/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sales tabs show one page and preserve the billing draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppController(
      database: AppDatabase.instance,
      preferences: await SharedPreferences.getInstance(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SalesScreen(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('Patient & prescription'), findsOneWidget);
    expect(find.text('Invoice history'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Ada Lovelace');

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice history'), findsOneWidget);
    expect(find.text('Patient & prescription'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('New sale'));
    await tester.pumpAndSettle();
    expect(find.text('Patient & prescription'), findsOneWidget);
    expect(find.text('Invoice history'), findsNothing);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

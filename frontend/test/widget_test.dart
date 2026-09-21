import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medistock_mobile/core/app_theme.dart';
import 'package:medistock_mobile/screens/login_screen.dart';
import 'package:medistock_mobile/state/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login offers administrator and staff access', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      database: AppDatabase.instance,
      preferences: preferences,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LoginScreen(controller: controller),
      ),
    );

    expect(find.text('MediStock'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);

    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();

    expect(find.text('STAFF CHECK-IN'), findsOneWidget);
    expect(find.text('Staff PIN'), findsOneWidget);
    expect(find.text('Check in & continue'), findsOneWidget);
  });
}

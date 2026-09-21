import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medistock_mobile/core/app_theme.dart';
import 'package:medistock_mobile/screens/startup_screen.dart';

Widget _host(Widget child, {bool reduceMotion = false, double textScale = 1}) {
  return MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: child,
  );
}

void main() {
  testWidgets('startup animates and releases its ticker when dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const StartupScreen()));
    expect(find.text('MediStock'), findsOneWidget);
    expect(find.text('Preparing your workspace'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion remains still and large text can scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(const StartupScreen(), reduceMotion: true, textScale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Preparing your workspace'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup error stops animation and retry is actionable', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(_host(const StartupScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(
      _host(
        StartupScreen(
          error: StateError('Workspace unavailable'),
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Preparing your workspace'), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });
}

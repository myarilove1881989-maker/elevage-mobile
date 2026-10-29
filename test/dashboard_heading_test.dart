import 'package:app_elevage/main.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ux_9a1_test.dart' show DisplayApiFake;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'username': 'pilot-operator'});
    ApiService.token = 'widget-test-only';
    AppSettings.instance.languageCode = 'fr';
  });
  tearDown(() => ApiService.token = null);
  testWidgets(
    'compact dashboard stays bounded with keyboard and restores heading',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 48);
      addTearDown(tester.view.reset);
      final api = DisplayApiFake();
      addTearDown(api.close);
      await tester.pumpWidget(ElevageApp(apiService: api));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.menu).hitTestable(), findsOneWidget);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('dashboardHeading')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dashboard heading stays below toolbar after scrolling content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    final api = DisplayApiFake();
    addTearDown(api.close);
    await tester.pumpWidget(ElevageApp(apiService: api));
    await tester.pumpAndSettle();
    final heading = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().startsWith('Tableau de bord'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(heading).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
    );
    expect(heading.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

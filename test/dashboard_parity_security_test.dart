import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/android_consumables_kpi.dart';
import 'android120_stock_test.dart' show Stocks, session;

void main() {
  setUpAll(tz.initializeTimeZones);
  setUp(() => ApiService.token = 'synthetic-parity');
  tearDown(() => ApiService.token = null);
  Widget app(
    Stocks api, {
    bool authorized = true,
    int? species,
    int? lot,
    int revision = 1,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        height: 190,
        child: AndroidConsumablesKpi(
          api: api,
          session: authorized ? session() : null,
          sessionIdentity: ApiService.sessionIdentity,
          species: species,
          lot: lot,
          revision: revision,
        ),
      ),
    ),
  );
  testWidgets('no authorized session means no stock read', (tester) async {
    final api = Stocks();
    await tester.pumpWidget(app(api, authorized: false));
    await tester.pumpAndSettle();
    expect(api.reads, isEmpty);
    expect(find.byTooltip('Aliments : Stock à actualiser'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('foreign farm and late account response remain neutral', (
    tester,
  ) async {
    final api = Stocks()..farm = 2;
    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aliments : Stock à actualiser'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.farm = 1;
    api.gate = Completer<void>();
    await tester.pumpWidget(app(api));
    ApiService.token = 'another-account';
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aliments : Stock satisfaisant'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'filtered subset never inherits whole product alert and scope refreshes',
    (tester) async {
      final api = Stocks();
      await tester.pumpWidget(app(api, species: 4, lot: 10));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Aliments : Niveau à vérifier'), findsOneWidget);
      expect(api.reads.length, 2);
      await tester.pumpWidget(app(api, species: 4, lot: 11));
      await tester.pumpAndSettle();
      expect(api.reads.length, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/screens/egg_production_screen.dart';
import 'package:app_elevage/services/api_service.dart';

class EggApiFake extends ApiService {
  int loads = 0;
  int collectionsCreated = 0;
  int? linkedExpense;
  @override
  Future<Map<String, dynamic>> getEggStatistics(
    int lotId, {
    DateTime? start,
    DateTime? end,
  }) async {
    loads++;
    return {
      'nombre_poules_vivantes': 100,
      'oeufs_collectes': 90,
      'stock_oeufs': 30,
    };
  }

  @override
  Future<List<dynamic>> getEggCollections(
    int lotId, {
    DateTime? start,
    DateTime? end,
  }) async => [];
  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async => {
    'depenses': [
      {'id': 42, 'montant': 1000},
    ],
  };
  @override
  Future<Map<String, dynamic>> createEggCollection({
    required int lotId,
    required DateTime collectedAt,
    required int total,
    int broken = 0,
    int downgraded = 0,
    int consumedOrDonated = 0,
    String note = '',
  }) async {
    collectionsCreated++;
    return {'id': 1};
  }

  @override
  Future<Map<String, dynamic>> createFeedConsumption({
    required int lotId,
    required double quantityKg,
    double? pricePerKg,
    int? expenseId,
    DateTime? date,
    String note = '',
  }) async {
    linkedExpense = expenseId;
    return {'id': 1};
  }
}

void main() {
  testWidgets('Affiche les indicateurs et recharge après une collecte', (
    tester,
  ) async {
    final api = EggApiFake();
    await tester.pumpWidget(
      MaterialApp(
        home: EggProductionScreen(apiService: api, lotId: 1, lotName: 'Ponte'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Poules vivantes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Nouvelle collecte'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nouvelle collecte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '20');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.collectionsCreated, 1);
    expect(api.loads, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Lie une dépense existante à la consommation', (tester) async {
    final api = EggApiFake();
    await tester.pumpWidget(
      MaterialApp(
        home: EggProductionScreen(apiService: api, lotId: 1, lotName: 'Ponte'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Alimentation'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Alimentation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('#42').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.linkedExpense, 42);
    expect(tester.takeException(), isNull);
  });
}

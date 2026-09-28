import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'package:app_elevage/screens/production_tracking_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class FeedApiFake extends ApiService {
  final List<Map<String, dynamic>> saved = [];
  bool failRead = false;
  bool failSave = false;

  @override
  Future<List<dynamic>> getEspeces() async => [
        {'id': 1, 'nom': 'Poulet'},
      ];

  @override
  Future<List<dynamic>> getLots() async => [
        {'id': 1, 'nom': 'Poulets chair', 'espece': 1, 'type_production': 'CHAIR'},
        {'id': 2, 'nom': 'Pondeuses', 'espece': 1, 'type_production': 'OEUFS'},
      ];

  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async => {
        'depenses': <dynamic>[],
      };

  @override
  Future<List<dynamic>> getFeedDistributions(int lotId) async {
    if (failRead) throw Exception('Erreur API');
    return saved.where((entry) => entry['lot'] == lotId).toList();
  }

  @override
  Future<Map<String, dynamic>> createFeedDistribution({
    required int lotId,
    required DateTime distributedAt,
    required String feedName,
    required double quantityKg,
    double? pricePerKg,
    int? expenseId,
    String note = '',
  }) async {
    if (failSave) throw Exception('Erreur API');
    final entry = <String, dynamic>{
      'id': saved.length + 1,
      'lot': lotId,
      'aliment': feedName,
      'quantite_kg': quantityKg,
      'distribution_at': distributedAt.toUtc().toIso8601String(),
      'note': note,
    };
    saved.add(entry);
    return entry;
  }
}

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

Future<void> _choose(WidgetTester tester, String key, String value) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('CHAIR et OEUFS ouvrent le même suivi de distribution', (tester) async {
    final api = FeedApiFake();
    await tester.pumpWidget(_app(ProductionTrackingScreen(apiService: api)));
    await tester.pumpAndSettle();
    await _choose(tester, 'productionSpeciesDropdown', 'Poulet');
    await _choose(tester, 'productionLotDropdown', 'Poulets chair');
    expect(find.byKey(const Key('openEggTrackingButton')), findsNothing);
    await tester.tap(find.byKey(const Key('openFeedTrackingButton')));
    await tester.pumpAndSettle();
    expect(find.byType(FeedDistributionScreen), findsOneWidget);
    expect(find.text('Aucune distribution enregistrée pour ce lot.'), findsOneWidget);

    // The route can be popped even when its AppBar has no BackButton widget.
    Navigator.of(tester.element(find.byType(FeedDistributionScreen))).pop();
    await tester.pumpAndSettle();
    await _choose(tester, 'productionLotDropdown', 'Pondeuses');
    expect(find.byKey(const Key('openEggTrackingButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('openFeedTrackingButton')));
    await tester.pumpAndSettle();
    expect(find.byType(FeedDistributionScreen), findsOneWidget);
  });

  testWidgets('Formulaire refuse zéro et négatif, puis affiche deux distributions et le total', (tester) async {
    final api = FeedApiFake();
    await tester.pumpWidget(_app(FeedDistributionScreen(
      apiService: api, lotId: 1, lotName: 'Poulets chair',
    )));
    await tester.pumpAndSettle();

    Future<void> add(String quantity) async {
      await tester.tap(find.byKey(const Key('addFeedDistribution')));
      await tester.pumpAndSettle();
      expect(find.text('Poulets chair'), findsOneWidget);
      expect(find.textContaining('kg'), findsWidgets);
      await tester.enterText(find.byKey(const Key('feedNameField')), 'Croissance');
      await tester.enterText(find.byKey(const Key('feedQuantityField')), quantity);
      await tester.scrollUntilVisible(
        find.byKey(const Key('saveFeedDistribution')), 200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('saveFeedDistribution')));
      await tester.pumpAndSettle();
    }

    await add('0');
    expect(find.text('Saisissez une quantité supérieure à zéro.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('feedQuantityField')), '-4');
    await tester.tap(find.byKey(const Key('saveFeedDistribution')));
    await tester.pumpAndSettle();
    expect(api.saved, isEmpty);
    await tester.enterText(find.byKey(const Key('feedQuantityField')), '25');
    await tester.tap(find.byKey(const Key('saveFeedDistribution')));
    await tester.pumpAndSettle();
    expect(api.saved.length, 1);
    expect(find.text('25 kg'), findsWidgets);

    await add('10');
    expect(api.saved.length, 2);
    expect(find.byKey(const Key('feedDailyTotal')), findsOneWidget);
    expect(find.text('35 kg'), findsOneWidget);
    expect(find.text('Croissance'), findsNWidgets(2));
  });

  testWidgets('Historique vide et erreurs API sont lisibles', (tester) async {
    final api = FeedApiFake()..failRead = true;
    await tester.pumpWidget(_app(FeedDistributionScreen(
      apiService: api, lotId: 1, lotName: 'Poulets chair',
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedHistoryError')), findsOneWidget);
    api.failRead = false;
    await tester.tap(find.text('Actualiser'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune distribution enregistrée pour ce lot.'), findsOneWidget);

    api.failSave = true;
    await tester.tap(find.byKey(const Key('addFeedDistribution')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feedNameField')), 'Maïs');
    await tester.enterText(find.byKey(const Key('feedQuantityField')), '3');
    await tester.scrollUntilVisible(
      find.byKey(const Key('saveFeedDistribution')), 200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('saveFeedDistribution')));
    await tester.pumpAndSettle();
    expect(find.text('Impossible d’enregistrer la distribution.'), findsOneWidget);
    expect(api.saved, isEmpty);
  });
}

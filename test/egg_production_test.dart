import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app_elevage/screens/egg_production_screen.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'package:app_elevage/services/api_service.dart';

class EggApiFake extends ApiService {
  int loads = 0;
  int collectionsCreated = 0;
  int? lastTrays;
  int? lastRemainder;
  DateTime? lastCollectedAt;
  List<dynamic> sampleCollections = [];
  Map<String, dynamic>? sampleStock;
  bool stockFails = false;
  int stockLoads = 0;
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
  }) async => sampleCollections;

  @override
  Future<Map<String, dynamic>> getDatedEggStock(int lotId) async {
    stockLoads++;
    if (stockFails) throw Exception('Stock indisponible');
    return sampleStock ?? {
      'stock_global': 30,
      'origines_completes': true,
      'sorties_non_attribuees': 0,
      'entrees_hors_collecte': 0,
      'collectes': [],
    };
  }
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
    int? total,
    int? fullTrays,
    int? remainingEggs,
    int broken = 0,
    int downgraded = 0,
    int consumedOrDonated = 0,
    String note = '',
  }) async {
    collectionsCreated++;
    lastTrays = fullTrays;
    lastRemainder = remainingEggs;
    lastCollectedAt = collectedAt;
    return {'id': 1};
  }

  @override
  Future<List<dynamic>> getFeedDistributions(int lotId) async => [];

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
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
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
    await tester.enterText(find.byKey(const Key('eggFullTrays')), '61');
    await tester.enterText(find.byKey(const Key('eggRemaining')), '17');
    await tester.pumpAndSettle();
    expect(find.text('Total collecté: 1847'), findsOneWidget);
    await tester.tap(find.text('Enregistrer la collecte'));
    await tester.pumpAndSettle();
    expect(api.collectionsCreated, 1);
    expect(api.lastTrays, 61);
    expect(api.lastRemainder, 17);
    expect(api.lastCollectedAt, isNotNull);
    expect(api.loads, 2);
    expect(api.stockLoads, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Refuse 30 œufs restants avant l’envoi', (tester) async {
    final api = EggApiFake();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: EggProductionScreen(apiService: api, lotId: 1, lotName: 'Ponte'),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Nouvelle collecte'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Nouvelle collecte'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('eggCollectionDate')), findsOneWidget);
    expect(find.byKey(const Key('eggCollectionTime')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('eggFullTrays')), '1');
    await tester.enterText(find.byKey(const Key('eggRemaining')), '30');
    await tester.tap(find.text('Enregistrer la collecte'));
    await tester.pumpAndSettle();
    expect(api.collectionsCreated, 0);
    expect(find.byKey(const Key('eggFullTrays')), findsOneWidget);
  });
  testWidgets('Affiche les anciennes collectes en alvéoles et le total du jour', (tester) async {
    final api = EggApiFake();
    final day = DateTime.now();
    api.sampleCollections = [
      {
        'collecte_at': DateTime(day.year, day.month, day.day, 13, 30).toIso8601String(),
        'nombre_collecte': 70, 'nombre_commercialisable': 68,
        'nombre_casses': 2, 'nombre_declasses': 0, 'nombre_consommes_donnes': 0,
      },
      {
        'collecte_at': DateTime(day.year, day.month, day.day, 8, 10).toIso8601String(),
        'nombre_collecte': 30, 'nombre_commercialisable': 30,
        'nombre_casses': 0, 'nombre_declasses': 0, 'nombre_consommes_donnes': 0,
      },
    ];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: EggProductionScreen(apiService: api, lotId: 1, lotName: 'Ponte'),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('2 alvéoles + 10 œufs'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('2 alvéoles + 10 œufs'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Total du jour: 100'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Total du jour: 100'), findsOneWidget);
  });
  testWidgets('Lie une dépense existante à la consommation', (tester) async {
    final api = EggApiFake();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
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
    await tester.tap(find.byKey(const Key('addFeedDistribution')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feedNameField')), 'Aliment pondeuse');
    await tester.enterText(find.byKey(const Key('feedQuantityField')), '10');
    final formScroll = find.descendant(
      of: find.byType(FeedDistributionFormScreen),
      matching: find.byType(Scrollable),
    ).first;
    await tester.scrollUntilVisible(
      find.text('Coût facultatif'), 200,
      scrollable: formScroll,
    );
    await tester.tap(find.text('Coût facultatif'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('feedExpenseDropdown')), 200,
      scrollable: formScroll,
    );
    await tester.tap(find.byKey(const Key('feedExpenseDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('#42').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('saveFeedDistribution')), 200,
      scrollable: formScroll,
    );
    await tester.tap(find.byKey(const Key('saveFeedDistribution')));
    await tester.pumpAndSettle();
    expect(api.linkedExpense, 42);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Affiche le stock daté et une collecte épuisée', (tester) async {
    final api = EggApiFake();
    api.sampleStock = {
      'stock_global': 2080,
      'origines_completes': true,
      'sorties_non_attribuees': 0,
      'entrees_hors_collecte': 0,
      'collectes': [
        {
          'id': 2, 'collecte_at': '2026-09-28T17:30:00',
          'nombre_collecte': 900, 'nombre_commercialisable': 880,
          'sorties_affectees': 0, 'restant': 880,
        },
        {
          'id': 1, 'collecte_at': '2026-09-28T08:15:00',
          'nombre_collecte': 1500, 'nombre_commercialisable': 1500,
          'sorties_affectees': 300, 'restant': 1200,
        },
        {
          'id': 3, 'collecte_at': '2026-09-27T16:20:00',
          'nombre_collecte': 500, 'nombre_commercialisable': 500,
          'sorties_affectees': 500, 'restant': 0,
        },
      ],
    };
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: EggProductionScreen(apiService: api, lotId: 1, lotName: 'Ponte'),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('eggDatedGlobalStock')),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('2080 œufs'), findsOneWidget);
    expect(find.text('69 alvéoles + 10 œufs'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('eggStockCollection-2')),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('17:30'), findsOneWidget);
    expect(find.text('29 alvéoles + 10 œufs'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('eggStockCollection-1')),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('08:15'), findsOneWidget);
    expect(find.text('Restants : 1200'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('eggStockCollection-3')),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Épuisée'), findsOneWidget);
  });

  testWidgets('Rend explicite l origine inconnue des ventes', (tester) async {
    final api = EggApiFake();
    api.sampleStock = {
      'stock_global': 600,
      'origines_completes': false,
      'sorties_non_attribuees': 600,
      'entrees_hors_collecte': 0,
      'collectes': [
        {
          'id': 1, 'collecte_at': '2026-09-26T08:00:00',
          'nombre_collecte': 500, 'nombre_commercialisable': 500,
          'sorties_affectees': 0, 'restant': null,
        },
      ],
    };
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: EggProductionScreen(apiService: api, lotId: 1, lotName: 'Ponte'),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('eggStockUnknown')),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Stock disponible : 600 œufs'), findsOneWidget);
    expect(find.text('Sorties sans origine : 600'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('eggStockCollection-1')),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Restant indéterminé'), findsOneWidget);
  });

  testWidgets('Montre une liste vide et une erreur API après rafraîchissement',
      (tester) async {
    final api = EggApiFake();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: EggProductionScreen(apiService: api, lotId: 1, lotName: 'Ponte'),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Aucune collecte enregistrée pour ce lot.'),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Aucune collecte enregistrée pour ce lot.'), findsOneWidget);
    api.stockFails = true;
    await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('eggStockLoadError')),
        250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Impossible de charger le stock par collecte.'), findsOneWidget);
    expect(api.stockLoads, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });
}

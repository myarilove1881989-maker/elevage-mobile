import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/egg_production_screen.dart';
import 'package:app_elevage/screens/growth_tracking_screen.dart';
import 'package:app_elevage/screens/production_tracking_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class ProductionTrackingApiFake extends ApiService {
  @override
  Future<List<dynamic>> getEspeces() async => [
    {'id': 1, 'nom': 'Poulet'},
    {'id': 2, 'nom': 'Canard'},
    {'id': 3, 'nom': 'Dinde'},
  ];

  @override
  Future<List<dynamic>> getLots() async => [
    {
      'id': 10,
      'nom': 'Pondeuses',
      'espece': 1,
      'espece_nom': 'Poulet',
      'stock': 100,
      'type_production': 'OEUFS',
    },
    {
      'id': 11,
      'nom': 'Poulets de chair',
      'espece': 1,
      'espece_nom': 'Poulet',
      'stock': 80,
      'type_production': 'CHAIR',
    },
    {
      'id': 12,
      'nom': 'Canards reproducteurs',
      'espece': 2,
      'espece_nom': 'Canard',
      'stock': 30,
      'type_production': 'REPRODUCTION',
    },
    {
      'id': 13,
      'nom': 'Dindes autres',
      'espece': 3,
      'espece_nom': 'Dinde',
      'stock': 20,
      'type_production': 'AUTRE',
    },
  ];

  @override
  Future<Map<String, dynamic>> getDashboard({int? especeId}) async => {
    'kpis': <String, dynamic>{},
  };

  @override
  Future<List<dynamic>> getTasks() async => [];

  @override
  Future<double> getTotalDettes() async => 0;

  @override
  Future<Map<String, dynamic>> getEggStatistics(
    int lotId, {
    DateTime? start,
    DateTime? end,
  }) async => {
    'nombre_poules_vivantes': 100,
    'oeufs_collectes': 0,
    'taux_ponte': 0,
    'stock_oeufs': 0,
    'equivalent_plateaux': 0,
    'oeufs_vendus': 0,
    'chiffre_affaires_oeufs': 0,
    'marge_oeufs': 0,
    'oeufs_commercialisables': 0,
    'oeufs_casses': 0,
    'oeufs_declasses': 0,
    'consommation_aliment_kg': 0,
    'cout_par_oeuf': 0,
  };

  @override
  Future<List<dynamic>> getEggCollections(
    int lotId, {
    DateTime? start,
    DateTime? end,
  }) async => [];

  @override
  Future<Map<String, dynamic>> getProductionWeights(int lotId) async => {
    'lot': lotId,
    'lot_nom': 'Poulets de chair',
    'effectif_actuel': 80,
    'dernier_poids_moyen_kg': null,
    'biomasse_estimee_kg': null,
    'gmq_g_par_jour': null,
    'pesees': <dynamic>[],
  };
}

Widget testApp(Widget home) => MaterialApp(
  locale: const Locale('fr'),
  supportedLocales: const [Locale('fr'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

Future<void> selectDropdown(
  WidgetTester tester,
  Key dropdownKey,
  String value,
) async {
  await tester.tap(find.byKey(dropdownKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Le menu ouvre le Suivi de production', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = ProductionTrackingApiFake();
    await tester.pumpWidget(testApp(DashboardScreen(apiService: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    expect(find.text('Suivi de production'), findsOneWidget);

    await tester.tap(find.text('Suivi de production'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductionTrackingScreen), findsOneWidget);
  });

  testWidgets('Filtre les lots et ouvre le suivi existant pour OEUFS', (
    tester,
  ) async {
    final api = ProductionTrackingApiFake();
    await tester.pumpWidget(
      testApp(ProductionTrackingScreen(apiService: api)),
    );
    await tester.pumpAndSettle();

    await selectDropdown(
      tester,
      const Key('productionSpeciesDropdown'),
      'Poulet',
    );

    await tester.tap(find.byKey(const Key('productionLotDropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Pondeuses'), findsWidgets);
    expect(find.text('Canards reproducteurs'), findsNothing);
    await tester.tap(find.text('Pondeuses').last);
    await tester.pumpAndSettle();
    expect(find.text('Œufs'), findsOneWidget);
    expect(find.byKey(const Key('openEggTrackingButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('openEggTrackingButton')));
    await tester.pumpAndSettle();
    expect(find.byType(EggProductionScreen), findsOneWidget);
  });

  testWidgets('Ouvre le suivi de croissance pour CHAIR', (tester) async {
    final api = ProductionTrackingApiFake();
    await tester.pumpWidget(
      testApp(ProductionTrackingScreen(apiService: api)),
    );
    await tester.pumpAndSettle();
    await selectDropdown(
      tester,
      const Key('productionSpeciesDropdown'),
      'Poulet',
    );
    await selectDropdown(
      tester,
      const Key('productionLotDropdown'),
      'Poulets de chair',
    );

    expect(find.text('Suivi de croissance'), findsOneWidget);
    expect(find.byKey(const Key('openEggTrackingButton')), findsNothing);
    expect(find.byKey(const Key('openGrowthTrackingButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('openGrowthTrackingButton')));
    await tester.pumpAndSettle();
    expect(find.byType(GrowthTrackingScreen), findsOneWidget);
    expect(find.text('Effectif actuel'), findsOneWidget);
  });

  testWidgets('Affiche les états neutres REPRODUCTION et AUTRE', (
    tester,
  ) async {
    final api = ProductionTrackingApiFake();
    await tester.pumpWidget(
      testApp(ProductionTrackingScreen(apiService: api)),
    );
    await tester.pumpAndSettle();

    await selectDropdown(
      tester,
      const Key('productionSpeciesDropdown'),
      'Canard',
    );
    await selectDropdown(
      tester,
      const Key('productionLotDropdown'),
      'Canards reproducteurs',
    );
    expect(find.text('Suivi de reproduction'), findsOneWidget);

    await selectDropdown(
      tester,
      const Key('productionSpeciesDropdown'),
      'Dinde',
    );
    await selectDropdown(
      tester,
      const Key('productionLotDropdown'),
      'Dindes autres',
    );
    expect(
      find.text(
        "Aucun suivi de production spécialisé n'est disponible pour ce type de lot.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('Indique clairement une espèce sans lot', (tester) async {
    await tester.pumpWidget(
      testApp(ProductionTrackingScreen(apiService: _EmptySpeciesLotApiFake())),
    );
    await tester.pumpAndSettle();
    await selectDropdown(
      tester,
      const Key('productionSpeciesDropdown'),
      'Lapin',
    );
    expect(
      find.text('Aucun lot disponible pour cette espèce.'),
      findsOneWidget,
    );
  });
}

class _EmptySpeciesLotApiFake extends ApiService {
  @override
  Future<List<dynamic>> getEspeces() async => [
    {'id': 4, 'nom': 'Lapin'},
  ];

  @override
  Future<List<dynamic>> getLots() async => [];
}

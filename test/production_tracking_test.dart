import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/egg_production_screen.dart';
import 'package:app_elevage/screens/growth_tracking_screen.dart';
import 'package:app_elevage/screens/production_tracking_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<Map<String, dynamic>> getDatedEggStock(int lotId) async => {
    'stock_global': 0,
    'origines_completes': true,
    'sorties_non_attribuees': 0,
    'entrees_hors_collecte': 0,
    'collectes': <dynamic>[],
  };

  @override
  Future<Map<String, dynamic>> getEggKpis(int lotId, {
    DateTime? start,
    DateTime? end,
  }) async => {
    'date': '2026-09-28',
    'effectif_actuel': 100,
    'collectes_enregistrees': false,
    'production_jour': null,
    'commercialisable_jour': null,
    'taux_ponte': null,
    'taux_casse': null,
    'stock_disponible': 0,
    'aliment_enregistre': false,
    'aliment_jour_kg': null,
    'consommation_par_poule_g': null,
    'evolution': <dynamic>[],
  };

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

Widget testApp(Widget home, {Locale locale = const Locale('fr')}) => MaterialApp(
  locale: locale,
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final viaTopBar in [false, true]) {
    for (final eggLot in [false, true]) {
      final entry = viaTopBar ? 'barre supérieure' : 'menu latéral';
      final type = eggLot ? 'OEUFS' : 'CHAIR';
      testWidgets('$entry ouvre le suivi existant $type', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final api = ProductionTrackingApiFake();
        await tester.pumpWidget(testApp(DashboardScreen(apiService: api)));
        await tester.pumpAndSettle();

        if (viaTopBar) {
          await tester.tap(find.byKey(const Key('topProductionTrackingButton')));
        } else {
          await tester.tap(find.byTooltip('Ouvrir le menu'));
          await tester.pumpAndSettle();
          final drawerEntry = find.descendant(
            of: find.byType(Drawer),
            matching: find.text('Suivi de production'),
          );
          expect(drawerEntry, findsOneWidget);
          await tester.tap(drawerEntry);
        }
        await tester.pumpAndSettle();
        expect(find.byType(ProductionTrackingScreen), findsOneWidget);
        expect(
          tester.widget<ProductionTrackingScreen>(
            find.byType(ProductionTrackingScreen),
          ).apiService,
          same(api),
        );
        await selectDropdown(
          tester, const Key('productionSpeciesDropdown'), 'Poulet',
        );
        await selectDropdown(
          tester, const Key('productionLotDropdown'),
          eggLot ? 'Pondeuses' : 'Poulets de chair',
        );
        expect(find.byKey(const Key('openFeedTrackingButton')), findsOneWidget);

        final openButton = find.byKey(Key(
          eggLot ? 'openEggTrackingButton' : 'openGrowthTrackingButton',
        ));
        await tester.ensureVisible(openButton);
        await tester.tap(openButton);
        await tester.pumpAndSettle();
        if (eggLot) {
          final screen = tester.widget<EggProductionScreen>(
            find.byType(EggProductionScreen),
          );
          expect(screen.apiService, same(api));
          expect(screen.lotId, 10);
          expect(find.byKey(const Key('layingCount')), findsOneWidget);
          final collectButton = find.text('Nouvelle collecte');
          await tester.ensureVisible(collectButton);
          expect(collectButton.hitTestable(), findsOneWidget);
          expect(find.text('Alimentation'), findsOneWidget);
          final stock = find.byKey(const Key('eggDatedGlobalStock'));
          await tester.scrollUntilVisible(stock, 300);
          expect(stock, findsOneWidget);
        } else {
          final screen = tester.widget<GrowthTrackingScreen>(
            find.byType(GrowthTrackingScreen),
          );
          expect(screen.apiService, same(api));
          expect(screen.lotId, 11);
          expect(find.text('Effectif actuel'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final language in ['fr', 'en']) {
    testWidgets('Navigation responsive et traduction $language', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final label = language == 'fr'
          ? 'Suivi de production' : 'Production tracking';
      final menuLabel = language == 'fr' ? 'Ouvrir le menu' : 'Open menu';

      for (final width in [1920.0, 1100.0, 1000.0, 800.0]) {
        tester.view.physicalSize = Size(width, 1080);
        await tester.pumpWidget(testApp(
          DashboardScreen(apiService: ProductionTrackingApiFake()),
          locale: Locale(language),
        ));
        await tester.pumpAndSettle();
        final top = find.byKey(const Key('topProductionTrackingButton'));
        if (width >= 1100) {
          expect(top.hitTestable(), findsOneWidget);
          expect(find.descendant(of: top, matching: find.text(label)), findsOneWidget);
          final buttonRect = tester.getRect(top);
          expect(buttonRect.left, greaterThanOrEqualTo(0));
          expect(buttonRect.right, lessThanOrEqualTo(width));
        } else {
          expect(top, findsNothing);
        }
        expect(tester.takeException(), isNull,
            reason: 'Dashboard $language à ${width.toInt()} px');
        await tester.tap(find.byTooltip(menuLabel));
        await tester.pumpAndSettle();
        final drawerEntry = find.descendant(
          of: find.byType(Drawer), matching: find.text(label),
        );
        expect(drawerEntry.hitTestable(), findsOneWidget);
        await tester.tap(drawerEntry);
        await tester.pumpAndSettle();
        expect(find.byType(ProductionTrackingScreen), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: 'Suivi de production $language à ${width.toInt()} px');
        final backTooltip = MaterialLocalizations.of(
          tester.element(find.byType(ProductionTrackingScreen)),
        ).backButtonTooltip;
        await tester.tap(find.byTooltip(backTooltip));
        await tester.pumpAndSettle();
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.byType(ProductionTrackingScreen), findsNothing);
        expect(tester.takeException(), isNull,
            reason: 'Retour au Dashboard $language à ${width.toInt()} px');
      }
    });
  }

  for (final noSpecies in [false, true]) {
    testWidgets('Accès supérieur sans ${noSpecies ? 'espèce' : 'lot'}', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = noSpecies ? _EmptyProductionApiFake() : _EmptySpeciesLotApiFake();
      await tester.pumpWidget(testApp(DashboardScreen(apiService: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topProductionTrackingButton')));
      await tester.pumpAndSettle();
      expect(find.byType(ProductionTrackingScreen), findsOneWidget);
      if (!noSpecies) {
        await selectDropdown(tester, const Key('productionSpeciesDropdown'), 'Lapin');
        expect(find.text('Aucun lot disponible pour cette espèce.'), findsOneWidget);
      }
      final lotDropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const Key('productionLotDropdown')),
      );
      expect(lotDropdown.onChanged, isNull);
      expect(find.byKey(const Key('openEggTrackingButton')), findsNothing);
      expect(find.byKey(const Key('openGrowthTrackingButton')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

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

class _EmptySpeciesLotApiFake extends ProductionTrackingApiFake {
  @override
  Future<List<dynamic>> getEspeces() async => [
    {'id': 4, 'nom': 'Lapin'},
  ];

  @override
  Future<List<dynamic>> getLots() async => [];
}

class _EmptyProductionApiFake extends _EmptySpeciesLotApiFake {
  @override
  Future<List<dynamic>> getEspeces() async => [];
}

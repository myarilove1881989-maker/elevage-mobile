import 'package:app_elevage/screens/add_achat_screen.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/add_mouvement_screen.dart';
import 'package:app_elevage/screens/client_detail_screen.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/depense_detail_screen.dart';
import 'package:app_elevage/screens/egg_production_screen.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'package:app_elevage/screens/growth_tracking_screen.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/screens/production_tracking_screen.dart';
import 'package:app_elevage/screens/register_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'production_tracking_test.dart' show ProductionTrackingApiFake, testApp;

class MobileApiFake extends ProductionTrackingApiFake {
  bool offline = false;
  @override
  Future<Map<String, dynamic>> getProductionWeights(int lotId) async => {
    'lot': lotId,
    'lot_nom': 'Poulets de chair',
    'effectif_actuel': 80,
    'dernier_poids_moyen_kg': 2.0,
    'biomasse_estimee_kg': 160.0,
    'gmq_g_par_jour': 20.0,
    'pesees': [
      {
        'pesee_at': '2026-10-06T08:00:00',
        'poids_moyen_kg': 2.0,
        'nombre_animaux_peses': 10,
        'poids_total_kg': 20.0,
        'note': 'Contrôle mobile',
      },
    ],
  };
  @override
  Future<List<dynamic>> getEggCollections(
    int lotId, {
    DateTime? start,
    DateTime? end,
  }) async => [
    {
      'id': 1,
      'collecte_at': '2026-10-06T08:00:00Z',
      'nombre_collecte': 100,
      'nombre_casses': 2,
      'nombre_declasses': 1,
      'nombre_commercialisable': 97,
      'nombre_consommes_donnes': 0,
    },
  ];
  @override
  Future<Map<String, dynamic>> getDatedEggStock(int lotId) async => {
    'stock_global': 97,
    'origines_completes': true,
    'sorties_non_attribuees': 0,
    'entrees_hors_collecte': 0,
    'collectes': [
      {
        'id': 1,
        'collecte_at': '2026-10-06T08:00:00Z',
        'nombre_collecte': 100,
        'nombre_commercialisable': 97,
        'restant': 97,
        'sorties_affectees': 0,
      },
    ],
  };
  @override
  Future<List<dynamic>> getCategoriesDepense() async => [
    {'id': 1, 'nom': 'Alimentation'},
  ];
  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async => {
    'id': lotId,
    'nom': 'Poulets de chair',
    'espece_nom': 'Poulet',
    'type_production': 'CHAIR',
    'stock': 80,
    'depenses': <dynamic>[],
  };
  @override
  Future<List<dynamic>> getClients() async => [
    {'id': 1, 'nom': 'Client de test', 'telephone': '0000000000'},
  ];
  @override
  Future<Map<String, dynamic>> getClientBalance(int clientId) async {
    if (offline) throw const ApiConnectionException();
    return {'balance': 60};
  }

  @override
  Future<List<dynamic>> getClientVentes(int clientId) async => [
    {
      'id': 42,
      'date': '2026-10-06',
      'produit_vendu': 'OEUFS',
      'lot_nom': 'Lot œufs',
      'quantite': 1,
      'nombre_oeufs': 100,
      'montant_total': 100,
      'montant_paye': 40,
      'reste': 60,
    },
  ];
  @override
  Future<dynamic> get(String endpoint) async => <dynamic>[];
  @override
  Future<List<dynamic>> getDepenses(int lotId) async => [];
  @override
  Future<List<dynamic>> getFeedDistributions(int lotId) async => [];
}

void testOnAndroid(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(
    name,
    body,
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.languageCode = 'fr';
    AppSettings.instance.currencyCode = 'XAF';
    AppSettings.instance.countryCode = 'CF';
  });
  final screens = <String, Widget Function(MobileApiFake)>{
    'Dashboard': (api) => DashboardScreen(apiService: api),
    'Achats': (api) => AddAchatScreen(apiService: api),
    'Dépenses': (api) => AddDepenseScreen(apiService: api),
    'Mouvements': (api) => AddMouvementScreen(apiService: api),
    'Facturation et historique': (api) => ClientDetailScreen(
      apiService: api,
      clientId: 1,
      nom: 'Client de test',
      telephone: '0000000000',
    ),
    'Paramètres avec pays long': (_) => const SettingsScreen(),
    'Suivi de production': (api) => ProductionTrackingScreen(apiService: api),
    'CHAIR': (api) => GrowthTrackingScreen(
      apiService: api,
      lotId: 11,
      lotName: 'Poulets de chair',
    ),
    'OEUFS': (api) =>
        EggProductionScreen(apiService: api, lotId: 10, lotName: 'Pondeuses'),
    'Alimentation': (api) => FeedDistributionFormScreen(
      apiService: api,
      lotId: 11,
      lotName: 'Poulets de chair',
    ),
    'Détail dépenses': (api) =>
        DepenseDetailScreenX(apiService: api, lotId: 11),
  };
  for (final width in [320.0, 360.0, 430.0]) {
    for (final entry in screens.entries) {
      testOnAndroid('${entry.key} reste utilisable à ${width.toInt()} px', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, width == 430 ? 800 : 640);
        tester.view.padding = FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(testApp(entry.value(MobileApiFake())));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          await tester.drag(scroll.first, const Offset(0, -700));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final entry in <String, Widget Function(MobileApiFake)>{
    'Connexion': (api) => LoginScreen(apiService: api),
    'Inscription': (api) => RegisterScreen(apiService: api),
    'Achat': (api) => AddAchatScreen(apiService: api),
    'Dépense': (api) => AddDepenseScreen(apiService: api),
    'Alimentation': (api) => FeedDistributionFormScreen(
      apiService: api,
      lotId: 11,
      lotName: 'Poulets',
    ),
  }.entries) {
    testOnAndroid('${entry.key}: le clavier laisse les champs accessibles', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.viewInsets = FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(entry.value(MobileApiFake())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final fields = find.byType(EditableText);
      expect(fields, findsWidgets);
      await tester.ensureVisible(fields.last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final bounds = tester.getRect(fields.last);
      expect(bounds.bottom, lessThanOrEqualTo(360));
    });
  }
  testOnAndroid(
    'Une panne client ne transforme pas les montants en faux zéros et permet un nouvel essai',
    (tester) async {
      final api = MobileApiFake()..offline = true;
      await tester.pumpWidget(
        testApp(
          ClientDetailScreen(
            apiService: api,
            clientId: 1,
            nom: 'Client de test',
            telephone: '0000000000',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Impossible de joindre le serveur'),
        findsOneWidget,
      );
      expect(find.text('FACTURÉ'), findsNothing);
      api.offline = false;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.text('FACTURÉ'), findsOneWidget);
      expect(
        find.textContaining('Impossible de joindre le serveur'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

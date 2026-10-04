import 'package:app_elevage/screens/add_mouvement_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class SaleApiFake extends ApiService {
  int? animalLot;
  String? movementType;
  int? animalQuantity;
  double? animalPrice;
  int? eggLot;
  int? eggTrays;
  int? eggExtra;
  String? eggTotal;
  int eggStock = 1000;
  bool eggOriginsComplete = true;
  bool stockFails = false;
  int stockLoads = 0;
  String? clientCountry;
  String? clientCity;

  @override
  Future<List<dynamic>> getLots() async => [
    {'id': 1, 'nom': 'Chair A', 'stock': 100, 'type_production': 'CHAIR'},
    {'id': 2, 'nom': 'Pondeuses A', 'stock': 100, 'type_production': 'OEUFS'},
    {'id': 3, 'nom': 'Reproduction', 'stock': 50, 'type_production': 'REPRODUCTION'},
  ];

  @override
  Future<List<dynamic>> getClients() async => [
    {'id': 7, 'nom': 'Restaurant'},
  ];

  @override
  Future<Map<String, dynamic>> getDatedEggStock(int lotId) async {
    stockLoads++;
    if (stockFails) throw Exception('Stock indisponible');
    return {
      'stock_global': eggStock,
      'origines_completes': eggOriginsComplete,
      'collectes': <dynamic>[],
    };
  }

  @override
  Future<bool> createMouvement({
    required int lotId,
    required String type,
    required int quantite,
    required double prixUnitaire,
    required DateTime date,
    int? clientId,
  }) async {
    animalLot = lotId;
    movementType = type;
    animalQuantity = quantite;
    animalPrice = prixUnitaire;
    return true;
  }

  @override
  Future<Map<String, dynamic>> createMixedEggSale({
    required int lotId,
    required int clientId,
    required int fullTrays,
    required int extraEggs,
    required String totalPrice,
    required DateTime date,
  }) async {
    eggLot = lotId;
    eggTrays = fullTrays;
    eggExtra = extraEggs;
    eggTotal = totalPrice;
    return {'id': 1};
  }

  @override
  Future<void> createClient(
    String nom, String telephone, {String pays = '', String ville = ''}
  ) async {
    clientCountry = pays;
    clientCity = ville;
  }
}

Widget saleApp(SaleApiFake api) => MaterialApp(
  locale: const Locale('fr'),
  supportedLocales: const [Locale('fr'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: AddMouvementScreen(apiService: api),
);

Future<void> pick(WidgetTester tester, Key key, String label) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> chooseEggs(WidgetTester tester) async {
  await pick(tester, const Key('saleProductDropdown'), 'Œufs');
  await pick(tester, const Key('movementLotDropdown'), 'Pondeuses A');
  await pick(tester, const Key('movementClientDropdown'), 'Restaurant');
}

void main() {
  testWidgets('Vente animaux conserve quantité et prix unitaire', (tester) async {
    final api = SaleApiFake();
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saleProductDropdown')), findsOneWidget);
    await pick(tester, const Key('movementLotDropdown'), 'Chair A');
    await pick(tester, const Key('movementClientDropdown'), 'Restaurant');
    await tester.ensureVisible(find.byKey(const Key('animalSaleQuantity')));
    await tester.enterText(find.byKey(const Key('animalSaleQuantity')), '10');
    await tester.enterText(find.byKey(const Key('animalSalePrice')), '5000');
    await tester.ensureVisible(find.byKey(const Key('saveMovement')));
    await tester.tap(find.byKey(const Key('saveMovement')));
    await tester.pumpAndSettle();
    expect(api.animalLot, 1);
    expect(api.movementType, 'VENTE');
    expect(api.animalQuantity, 10);
    expect(api.animalPrice, 5000);
    expect(api.eggLot, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vente œufs filtre les lots et envoie 20 alvéoles plus 8 œufs',
      (tester) async {
    final api = SaleApiFake();
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    await pick(tester, const Key('saleProductDropdown'), 'Œufs');
    await tester.tap(find.byKey(const Key('movementLotDropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Chair A'), findsNothing);
    expect(find.text('Reproduction'), findsNothing);
    await tester.tap(find.text('Pondeuses A').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('eggSaleStock')), findsOneWidget);
    await pick(tester, const Key('movementClientDropdown'), 'Restaurant');
    await tester.ensureVisible(find.byKey(const Key('eggSaleTrays')));
    await tester.enterText(find.byKey(const Key('eggSaleTrays')), '20');
    await tester.enterText(find.byKey(const Key('eggSaleExtra')), '8');
    await tester.pump();
    final totalEggs = find.byKey(const Key('eggSaleTotalEggs'));
    expect(totalEggs, findsOneWidget);
    expect(tester.widget<Text>(totalEggs).data, contains('608'));
    await tester.enterText(find.byKey(const Key('eggSaleTotalPrice')), '60800');
    await tester.ensureVisible(find.byKey(const Key('saveMovement')));
    await tester.tap(find.byKey(const Key('saveMovement')));
    await tester.pumpAndSettle();
    expect(api.eggLot, 2);
    expect(api.eggTrays, 20);
    expect(api.eggExtra, 8);
    expect(api.eggTotal, '60800');
    expect(api.animalLot, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stock insuffisant et valeurs incohérentes bloquent la vente',
      (tester) async {
    final api = SaleApiFake()..eggStock = 500;
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    await chooseEggs(tester);
    await tester.ensureVisible(find.byKey(const Key('eggSaleTrays')));
    await tester.enterText(find.byKey(const Key('eggSaleTrays')), '20');
    await tester.enterText(find.byKey(const Key('eggSaleExtra')), '8');
    await tester.enterText(find.byKey(const Key('eggSaleTotalPrice')), '60800');
    await tester.ensureVisible(find.byKey(const Key('saveMovement')));
    await tester.tap(find.byKey(const Key('saveMovement')));
    await tester.pump();
    expect(find.textContaining('Stock d’œufs insuffisant'), findsOneWidget);
    expect(api.eggLot, isNull);
    await tester.enterText(find.byKey(const Key('eggSaleExtra')), '30');
    await tester.tap(find.byKey(const Key('saveMovement')));
    await tester.pump();
    expect(api.eggLot, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Permet de recharger le stock après une erreur', (tester) async {
    final api = SaleApiFake()..stockFails = true;
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    await pick(tester, const Key('saleProductDropdown'), 'Œufs');
    await pick(tester, const Key('movementLotDropdown'), 'Pondeuses A');
    expect(find.byKey(const Key('eggStockRetry')), findsOneWidget);
    api.stockFails = false;
    await tester.tap(find.byKey(const Key('eggStockRetry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('eggSaleStock')), findsOneWidget);
    expect(api.stockLoads, 2);
  });

  testWidgets('Bloque une vente si l’origine du stock reste indéterminée',
      (tester) async {
    final api = SaleApiFake()..eggOriginsComplete = false;
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    await chooseEggs(tester);
    expect(find.byKey(const Key('eggSaleOriginsIncomplete')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('eggSaleTrays')));
    await tester.enterText(find.byKey(const Key('eggSaleTrays')), '2');
    await tester.enterText(find.byKey(const Key('eggSaleTotalPrice')), '5000');
    await tester.ensureVisible(find.byKey(const Key('saveMovement')));
    await tester.tap(find.byKey(const Key('saveMovement')));
    await tester.pump();
    expect(api.eggLot, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Le bouton nouveau client conserve le pays et la ville',
      (tester) async {
    final api = SaleApiFake();
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    await chooseEggs(tester);
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(of: dialog, matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Marché central');
    await tester.enterText(fields.at(1), '01020304');
    await tester.enterText(fields.at(2), 'Cotonou');
    final country = find.descendant(
      of: dialog, matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.tap(country);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bénin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ajouter'));
    await tester.pumpAndSettle();
    expect(api.clientCountry, 'BJ');
    expect(api.clientCity, 'Cotonou');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Les mouvements non commerciaux gardent leur flux animal',
      (tester) async {
    final api = SaleApiFake();
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    await pick(tester, const Key('movementTypeDropdown'), 'Mortalité');
    expect(find.byKey(const Key('saleProductDropdown')), findsNothing);
    await pick(tester, const Key('movementLotDropdown'), 'Chair A');
    await tester.ensureVisible(find.byKey(const Key('animalSaleQuantity')));
    await tester.enterText(find.byKey(const Key('animalSaleQuantity')), '2');
    await tester.enterText(find.byKey(const Key('animalSalePrice')), '0.1');
    await tester.ensureVisible(find.byKey(const Key('saveMovement')));
    await tester.tap(find.byKey(const Key('saveMovement')));
    await tester.pumpAndSettle();
    expect(api.movementType, 'MORTALITE');
    expect(api.animalQuantity, 2);
    expect(api.eggLot, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Le formulaire reste accessible sur une largeur étroite',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = SaleApiFake();
    await tester.pumpWidget(saleApp(api));
    await tester.pumpAndSettle();
    await chooseEggs(tester);
    await tester.ensureVisible(find.byKey(const Key('saveMovement')));
    expect(find.byKey(const Key('saveMovement')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

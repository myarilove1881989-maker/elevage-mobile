import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/commerce_panel.dart';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/invoice_pdf_service.dart';
import 'package:app_elevage/screens/client_detail_screen.dart';
import 'client_payment_recovery_test.dart' show CashApi;
import 'aquatic_phase1_test.dart' show FakeAquatic, installations, cohorts;
import 'package:flutter_localizations/flutter_localizations.dart';

Widget testApp(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('fr'),
  supportedLocales: const [Locale('fr'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(backgroundColor: const Color(0xFFFCF7FF), body: home),
);

const harvestId = '85000000-0000-4000-8000-000000000001';
Map<String, dynamic> stock() => {
  'id': harvestId,
  'cohort': cohorts.first['id'],
  'installation': installations.first['id'],
  'species': 42,
  'species_name': 'Tilapia',
  'cohort_name': 'Cohorte Nord',
  'installation_name': 'Bassin Nord',
  'occurred_at': '2026-11-13T10:00:00Z',
  'destination': 'STOCK',
  'stock_unit': 'KG',
  'mass_kg': '100.000000',
  'mass_quality': 'MEASURED',
  'live_count': 100,
  'storage_place': 'Glacière déclarée',
  'storage_mode': 'Conservation déclarée',
  'conservation_note': 'Information utilisateur',
  'balance': {
    'status': 'AVAILABLE',
    'available_quantity': '25.000000',
    'available_mass_kg': '25.000000',
    'available_count': null,
  },
};
Map<String, dynamic> invoice() => {
  'id': 123,
  'invoice_reference': 'FAC-2026-00123',
  'client': 5,
  'client_name': 'Client test',
  'client_phone': '010203',
  'date': '2026-11-13',
  'produit_vendu': 'POISSONS',
  'espece': 'Tilapia',
  'lot_nom': 'Récolte piscicole',
  'price_unit': 'KG',
  'priced_quantity': '30.000000',
  'quantite': '30.000000',
  'prix_unitaire': '2.50',
  'montant_total': '75.00',
  'montant_paye': '20.00',
  'reste': '55.00',
  'statut': 'PARTIEL',
  'exploitation_nom': 'Ferme fictive',
  'exploitation_id': 1,
  'payments': [
    {'id': 9, 'amount': '20.00', 'date': '2026-11-13'},
  ],
};
final customers = <Map<String, dynamic>>[
  {'id': 5, 'nom': 'Client test', 'telephone': '010203'},
];

class FishClientApi extends CashApi {
  @override
  Future<List<dynamic>> getClientVentes(int id) async => [
    {
      ...invoice(),
      'quantite': null,
      'montant_total': 75.0,
      'montant_paye': 20.0,
      'reste': 55.0,
    },
  ];
}

class FakeCommerce extends FakeAquatic {
  bool blocked = false, unknown = true, interrupt = false;
  int reads = 0;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> read(String path) async {
    paths.add(path);
    reads++;
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('commerce-check/')) {
      return {
        'health_token': 'signed-synthetic',
        'blocked': blocked,
        'sale_authorized': null,
        'verification_required': true,
        'notice': 'Vérification humaine requise.',
        'matches': [
          {
            'scope_match': 'TRACEABILITY_REQUIRED',
            'treatment': {
              'product_name': 'Produit fictif de qualification',
              'occurred_at': '2026-11-12T10:00:00Z',
              'quantity': '1.000000',
              'unit': 'dose',
              'ongoing': false,
            },
            'precaution': {
              'status': blocked
                  ? 'ACTIVE'
                  : unknown
                  ? 'UNKNOWN'
                  : 'ELAPSED_RECORDED',
              'message': unknown
                  ? 'Délai avant commercialisation non renseigné — vérification nécessaire'
                  : blocked
                  ? 'Délai documenté en cours'
                  : 'Délai documenté écoulé — vérification nécessaire',
              'source': unknown ? null : 'Document fictif de test',
              'until': null,
            },
          },
        ],
      };
    }
    if (path.startsWith('harvests/$harvestId/')) {
      return {
        ...stock(),
        'movements': [
          {
            'id': 'move',
            'kind': 'SALE',
            'occurred_at': '2026-11-13T11:00:00Z',
            'quantity': '30.000000',
            'invoice': invoice(),
          },
        ],
      };
    }
    return super.read(path);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    paths.add(path);
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('harvests/')) return [stock()];
    if (path.startsWith('commerce-clients/')) return customers;
    if (path.startsWith('commerce-history/')) {
      return [
        {
          'id': 'move',
          'kind': 'SALE',
          'occurred_at': '2026-11-13T11:00:00Z',
          'quantity': '30.000000',
          'unit': 'KG',
          'actor_name': 'Éleveur fictif',
          'cohort_name': 'Cohorte Nord',
          'installation_name': 'Bassin Nord',
          'species_name': 'Tilapia',
          'invoice': invoice(),
        },
      ];
    }
    return super.list(path);
  }

  @override
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> command,
  ) async {
    paths.add(path);
    writes.add(Map<String, dynamic>.from(command));
    if (interrupt) throw const ApiConnectionException();
    return {'id': 'accepted'};
  }
}

Future<void> size(
  WidgetTester t,
  double width,
  double scale, {
  double height = 1100,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget editor(FakeCommerce f, String mode, {double scale = 1}) => testApp(
  Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: CommerceEditor(
        service: f,
        mode: mode,
        installations: installations,
        cohorts: cohorts,
        harvests: [stock()],
        clients: customers,
        row: mode == 'PAYMENT'
            ? invoice()
            : mode == 'SALE' ||
                  mode == 'LOSS' ||
                  mode == 'VOID' ||
                  mode == 'CORRECTION'
            ? stock()
            : null,
        initialInstallation: '${installations.first['id']}',
        initialCohort: '${cohorts.first['id']}',
      ),
    ),
  ),
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> fill(WidgetTester t, String label, String value) async {
  final f = field(label);
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> click(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, String label, String text) async {
  final f = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == label,
  );
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Future<void> health(WidgetTester t) async {
  await click(t, 'Vérifier les précautions sanitaires');
  await click(
    t,
    'J’ai vérifié les informations et sources applicables à cette population',
  );
  await fill(
    t,
    'Justification de la vérification humaine',
    'Vérification documentaire fictive',
  );
}

Future<void> capture(WidgetTester t, String name) async {
  final dir = Platform.environment['ELEVAGE_PHASE3C_CAPTURES'];
  if (dir == null) return;
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final im = await boundary.toImage(pixelRatio: 1);
    final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    im.dispose();
  });
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    for (final pair in [
      ['Roboto', 'Roboto-Regular.ttf'],
      ['MaterialIcons', 'MaterialIcons-Regular.otf'],
    ]) {
      final loader = FontLoader(pair[0])
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '$root/bin/cache/artifacts/material_fonts/${pair[1]}',
              ).readAsBytes(),
            ),
          ),
        );
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'workspace retains explicit existing client and payment permissions',
    (t) async {
      final f = FakeCommerce();
      await t.pumpWidget(
        testApp(
          AquaticWorkspace(
            service: f,
            capabilities: const {
              'can_enable': false,
              'read': ['aquatic.read'],
              'write': ['aquatic.harvest.create'],
              'commerce_write': ['cash.create', 'clients.create'],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      t
          .state<AquaticWorkspaceState>(find.byType(AquaticWorkspace))
          .showPage('commerce');
      await t.pumpAndSettle();
      final panel = t.widget<CommercePanel>(find.byType(CommercePanel));
      expect(panel.rights, containsAll(['cash.create', 'clients.create']));
      expect(panel.owner, false);
      expect(t.takeException(), isNull);
      f.api.close();
    },
  );
  for (final kind in ['cohort', 'installation']) {
    testWidgets('harvest origin prefilled from $kind', (t) async {
      final f = FakeCommerce();
      await t.pumpWidget(
        testApp(
          AquaticWorkspace(
            service: f,
            capabilities: const {
              'can_enable': true,
              'write': ['aquatic.harvest.create'],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      t
          .state<AquaticWorkspaceState>(find.byType(AquaticWorkspace))
          .showPage(kind == 'cohort' ? 'cohorts' : 'installations');
      await t.pumpAndSettle();
      final row = kind == 'cohort' ? cohorts.first : installations.first;
      await click(t, '${row['name']} · ${row['code']}');
      await click(t, 'Récolter');
      expect(find.text('Enregistrer une récolte'), findsOneWidget);
      final selected = t.widget<DropdownButtonFormField<String>>(
        find.descendant(
          of: find.byType(CommerceEditor),
          matching: find.widgetWithText(
            DropdownButtonFormField<String>,
            kind == 'cohort' ? 'Cohorte d’origine' : 'Installation d’origine',
          ),
        ),
      );
      expect(selected.initialValue, row['id']);
      expect(f.writes, isEmpty);
      expect(t.takeException(), isNull);
      f.api.close();
    });
  }
  testWidgets('measured optional fish count in kg sale stays explicit', (
    t,
  ) async {
    final f = FakeCommerce();
    await t.pumpWidget(editor(f, 'SALE'));
    await t.pumpAndSettle();
    await choose(t, 'Client', 'Client test');
    await fill(t, 'Quantité (kg)', '10');
    await fill(t, 'Prix par kg (XAF)', '2.00');
    await click(t, 'Mesure secondaire (facultative)');
    await fill(t, 'Poissons réellement comptés (facultatif)', '12');
    await health(t);
    await click(t, 'Enregistrer');
    expect(f.writes.single['count'], 12);
    expect(f.writes.single['mass_kg'], '10');
    f.api.close();
  });
  testWidgets('payment precision does not silently round an entered amount', (
    t,
  ) async {
    final f = FakeCommerce();
    await t.pumpWidget(editor(f, 'PAYMENT'));
    await fill(t, 'Montant du paiement', '1.001');
    await click(t, 'Enregistrer');
    expect(f.writes, isEmpty);
    expect(find.text('Au maximum 2 décimales.'), findsOneWidget);
    f.api.close();
  });
  testWidgets(
    'existing client card labels measured kg and never zero animals',
    (t) async {
      final api = FishClientApi();
      addTearDown(api.close);
      await size(t, 1080, 1);
      await t.pumpWidget(
        testApp(
          ClientDetailScreen(
            apiService: api,
            clientId: 5,
            nom: 'Client test',
            telephone: '010203',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('30.000000 kg'), findsOneWidget);
      expect(find.textContaining('0 animaux'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  test(
    'fish invoice keeps its reference, kg quantity and decimal amounts',
    () async {
      final bytes = await InvoicePdfService.buildInvoice(
        sale: invoice(),
        customerName: 'Client test',
        customerPhone: '010203',
        languageCode: 'fr',
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      final folder = Platform.environment['ELEVAGE_PHASE3C_CAPTURES'];
      if (folder != null) {
        await File(
          '$folder/../evidence/invoice-synthetic.pdf',
        ).writeAsBytes(bytes);
      }
    },
  );
  test('decimal money preview is exact and rounded to cents', () {
    expect(commerceTotal('0.333333', '3.00'), '1.00');
    expect(commerceTotal('30', '2.50'), '75.00');
    expect(commerceTotal('', '2'), isNull);
    expect(commerceValue(null), 'Non renseigné');
  });
  for (final mode in [
    'HARVEST',
    'DIRECT',
    'SALE',
    'LOSS',
    'CLIENT',
    'PAYMENT',
    'VOID',
    'CORRECTION',
  ]) {
    for (final width in [360.0, 1080.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$mode width $width text $scale', (t) async {
          final f = FakeCommerce();
          await size(t, width, scale);
          await t.pumpWidget(
            RepaintBoundary(child: editor(f, mode, scale: scale)),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          if (scale == 1) await capture(t, '$mode-${width.toInt()}');
          f.api.close();
        });
      }
    }
  }
  testWidgets(
    'kg stock sale leaves fish number unknown, explicit health and no living debit',
    (t) async {
      final f = FakeCommerce();
      await size(t, 360, 2, height: 800);
      await t.pumpWidget(editor(f, 'SALE', scale: 2));
      await t.pumpAndSettle();
      await choose(t, 'Client', 'Client test');
      await fill(t, 'Quantité (kg)', '30');
      await fill(t, 'Prix par kg (XAF)', '2.50');
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      await health(t);
      await click(t, 'Enregistrer');
      expect(f.writes.single['count'], isNull);
      expect(f.writes.single['quantity'], '30');
      expect(f.writes.single['mass_kg'], '30');
      expect(f.writes.single['review']['human_verified'], true);
      expect(f.writes.single.containsKey('live_count'), false);
      expect(f.paths.last, 'harvest-sales/');
      f.api.close();
    },
  );
  testWidgets(
    'stock harvest preserves unknown weight and requires actual count',
    (t) async {
      final f = FakeCommerce();
      await size(t, 360, 2, height: 800);
      await t.pumpWidget(editor(f, 'HARVEST', scale: 2));
      await t.pumpAndSettle();
      await fill(t, 'Poissons réellement comptés', '100');
      await choose(t, 'Unité de suivi et de prix', 'Nombre de poissons');
      await fill(t, 'Lieu de conservation', 'Glacière');
      await fill(t, 'Mode de conservation', 'Déclaration utilisateur');
      await health(t);
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      await click(t, 'Je confirme le nombre réellement compté et récolté');
      await click(t, 'Enregistrer');
      expect(f.writes.single['mass_kg'], isNull);
      expect(f.writes.single['mass_quality'], 'UNKNOWN');
      expect(f.writes.single['live_count'], 100);
      expect(f.writes.single['counted'], true);
      f.api.close();
    },
  );
  for (final width in [360.0, 1080.0]) {
    testWidgets('human sanitary review $width', (t) async {
      final f = FakeCommerce();
      await size(t, width, 1);
      await t.pumpWidget(RepaintBoundary(child: editor(f, 'SALE')));
      await t.pumpAndSettle();
      await click(t, 'Vérifier les précautions sanitaires');
      expect(
        find.textContaining('Produit fictif de qualification'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Délai avant commercialisation non renseigné'),
        findsOneWidget,
      );
      await capture(t, 'sanitary-${width.toInt()}');
      expect(f.writes, isEmpty);
      expect(t.takeException(), isNull);
      f.api.close();
    });
  }
  testWidgets('documented active restriction cannot be confirmed', (t) async {
    final f = FakeCommerce()
      ..blocked = true
      ..unknown = false;
    await t.pumpWidget(editor(f, 'SALE'));
    await t.pumpAndSettle();
    await choose(t, 'Client', 'Client test');
    await fill(t, 'Quantité (kg)', '1');
    await fill(t, 'Prix par kg (XAF)', '2');
    await click(t, 'Vérifier les précautions sanitaires');
    expect(find.textContaining('Confirmation bloquée'), findsOneWidget);
    await click(t, 'Enregistrer');
    expect(f.writes, isEmpty);
    f.api.close();
  });
  testWidgets('unknown response retries identical payment UUID and body', (
    t,
  ) async {
    final f = FakeCommerce()..interrupt = true;
    await t.pumpWidget(editor(f, 'PAYMENT'));
    await fill(t, 'Montant du paiement', '20.00');
    await click(t, 'Enregistrer');
    await click(t, 'Réessayer la même opération');
    expect(f.writes.length, 2);
    expect(f.writes.first, f.writes.last);
    f.api.close();
  });
  testWidgets('session change prevents retry by another author', (t) async {
    final f = FakeCommerce()..interrupt = true;
    await t.pumpWidget(editor(f, 'PAYMENT'));
    await fill(t, 'Montant du paiement', '20.00');
    await click(t, 'Enregistrer');
    ApiService.setLocalPresentationIdentity('commerce-B');
    addTearDown(ApiService.clearLocalPresentationIdentity);
    await click(t, 'Réessayer la même opération');
    expect(f.writes.length, 1);
    expect(find.textContaining('Session modifiée'), findsOneWidget);
    f.api.close();
  });
  testWidgets('client uses existing creation contract without sale', (t) async {
    final f = FakeCommerce();
    await t.pumpWidget(editor(f, 'CLIENT'));
    await fill(t, 'Nom du client', 'Nouveau client');
    await click(t, 'Enregistrer');
    expect(f.paths.last, 'commerce-clients/');
    expect(f.writes.single['customer']['nom'], 'Nouveau client');
    expect(f.writes.single.containsKey('price'), false);
    f.api.close();
  });
  for (final width in [360.0, 1080.0]) {
    testWidgets('stock and history $width', (t) async {
      final f = FakeCommerce();
      await size(t, width, 1);
      await t.pumpWidget(
        RepaintBoundary(
          child: testApp(
            SingleChildScrollView(
              child: Material(
                child: CommercePanel(
                  service: f,
                  owner: true,
                  rights: const [],
                  installations: installations,
                  cohorts: cohorts,
                  species: const [
                    {'id': 42, 'name': 'Tilapia'},
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Nombre restant : Non renseigné'),
        findsOneWidget,
      );
      await click(t, 'Consulter l’historique');
      expect(find.textContaining('FAC-2026-00123'), findsOneWidget);
      await capture(t, 'history-${width.toInt()}');
      expect(t.takeException(), isNull);
      f.api.close();
    });
  }
  testWidgets('failed reload clears private stock and financial details', (
    t,
  ) async {
    final f = FakeCommerce();
    await t.pumpWidget(
      testApp(
        SingleChildScrollView(
          child: Material(
            child: CommercePanel(
              service: f,
              owner: false,
              rights: const [],
              installations: installations,
              cohorts: cohorts,
              species: const [],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Nouvelle récolte'), findsNothing);
    expect(find.textContaining('25.000000 kg'), findsOneWidget);
    f.offline = true;
    await click(t, 'Actualiser');
    expect(find.textContaining('25.000000 kg'), findsNothing);
    expect(find.textContaining('Lecture impossible'), findsOneWidget);
    f.api.close();
  });
}

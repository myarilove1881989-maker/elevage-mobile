import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant;
import 'production_tracking_test.dart' show testApp;

const allCodes = [
  'finance.read',
  'purchases.create',
  'births.create',
  'mortality.create',
  'donations.create',
  'thefts.create',
  'feed.create',
  'weights.create',
  'egg_collections.create',
  'animal_sales.create',
  'egg_sales.create',
  'cash.create',
  'clients.create',
  'expenses.create',
  'agenda.progress',
];

/// Only startup/preparation is fixture-provided. UI, PIN, validation, declarations,
/// encrypted storage and projections are real; no server is contacted.
class PreparedFormTablet extends TabletController {
  PreparedFormTablet({
    required super.api,
    required super.secrets,
    required super.clock,
  }) : super(automaticSyncEnabled: false);
  @override
  Future<void> initialize() async {}
  Future<void> Function()? beforeDeclaration;
  @override
  Future<OutboxEntry> declare({required String entityType,required String operationType,
    required Map<String,dynamic> payload,required DateTime businessOccurredAt,
    String? operationId,String? localEntityId,List<String> dependencies=const [],
    String expectedServerVersion='',Future<void> Function()? project}) async {
    final hook=beforeDeclaration;beforeDeclaration=null;
    await hook?.call();
    return super.declare(entityType:entityType,operationType:operationType,payload:payload,
      businessOccurredAt:businessOccurredAt,operationId:operationId,localEntityId:localEntityId,
      dependencies:dependencies,expectedServerVersion:expectedServerVersion,project:project);
  }
}

class FormFixture {
  final secrets = TestSecretStore();
  late Directory directory;
  late FarmDatabase db;
  late PreparedFormTablet tablet;
  late DateTime now;
  int requests = 0;
  Future<void> start() async {
    now = DateTime.now().toUtc();
    directory = await Directory.systemTemp.createTemp(
      'elevage-functional-forms-',
    );
    db = open();
    final grant = await fineGrant(
      codes: allCodes,
      issuedAt: now.subtract(const Duration(minutes: 1)),
      now: now,
      duration: const Duration(days: 7),
    );
    final api = FoundationApi(
      baseUrl: 'https://forms.invalid/api',
      secrets: secrets,
      deviceIdentity: TestIdentity(),
      clock: () => DateTime.now().toUtc(),
      client: MockClient((_) async {
        requests++;
        throw StateError('Offline UI must not call HTTP');
      }),
    );
    tablet =
        PreparedFormTablet(
            api: api,
            secrets: secrets,
            clock: () => DateTime.now().toUtc(),
          )
          ..cache = db
          ..farmId = 1
          ..deviceId = 7
          ..generation = 1;
    tablet.operators = LocalOperatorSessions(
      store: secrets,
      namespace: Uri.encodeComponent(api.baseUrl),
      farmId: 1,
      deviceId: 7,
      generation: 1,
      clock: () => DateTime.now().toUtc(),
    );
    await tablet.operators!.enroll(grant, '123456');
    expect(await tablet.operators!.unlock(grant, '123456'), isTrue);
    await db.saveOperatorProfile(grant, 'Employé fictif');
    tablet.profiles = await db.operatorProfiles();
    tablet.selectedName = 'Employé fictif';
    await db.replaceConfirmedCache('lots', [
      {
        'id': 7,
        'nom': 'Lot chair fictif',
        'exploitation': 1,
        'stock': 10,
        'stock_oeufs': 0,
        'type_production': 'CHAIR',
        'confirmed_business_revision': 1,
      },
      {
        'id': 8,
        'nom': 'Lot ponte fictif',
        'exploitation': 1,
        'stock': 10,
        'stock_oeufs': 20,
        'type_production': 'OEUFS',
        'confirmed_business_revision': 1,
      },
    ]);
    await db.replaceConfirmedCache('species', [
      {'id': 1, 'nom': 'Poulet'},
    ]);
    await db.replaceConfirmedCache('clients', [
      {'id': 11, 'nom': 'Client fictif'},
    ]);
    await db.replaceConfirmedCache('expense_categories', [
      {'id': 1, 'nom': 'Frais fictifs'},
    ]);
    await db.replaceConfirmedCache('tasks', [
      {
        'id': 21,
        'title': 'Tâche fictive',
        'assigned_to': 2,
        'status': 'TODO',
        'report': '',
        'date': now.toIso8601String().substring(0, 10),
        'version': 1,
      },
    ]);
  }

  FarmDatabase open() => FarmDatabase(
    encryptedExecutor(
      File('${directory.path}/forms.db'),
      List.filled(32, 'b8').join(),
    ),
    farmId: 1,
    serverNamespace: 'forms-test',
  );
  Future<void> finish() async {
    if (!tablet.isDisposed) {
      tablet.dispose();
      tablet.api.close();
    }
    await db.close();
    await directory.delete(recursive: true);
  }
}

Future<void> flush(WidgetTester tester, FormFixture fixture) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => fixture.db.customSelect('SELECT 1').get());
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> choose(WidgetTester tester, String label, String value) async {
  final dropdown = find
      .ancestor(
        of: find.text(label).first,
        matching: find.byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField,
        ),
      )
      .first;
  await tap(tester, dropdown);
  await tap(tester, find.text(value).last);
}

Future<void> fill(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

void main() {
  testWidgets('visible confirmed stock refreshes after automatic receipt notification',(tester) async {
    final fixture=FormFixture();await tester.runAsync(fixture.start);
    addTearDown(() async {await tester.pumpWidget(const SizedBox());await tester.runAsync(fixture.finish);});
    await tester.pumpWidget(testApp(OfflineTabletScreen(controller:fixture.tablet)));await flush(tester,fixture);
    await choose(tester,'Consulter','Agenda');await flush(tester,fixture);
    await choose(tester,'Consulter','Lots');await flush(tester,fixture);
    expect(find.text('Stock confirmé : 10'),findsWidgets);
    await tester.runAsync(() async {
      await fixture.db.replaceConfirmedCache('lots',[{'id':7,'nom':'Lot chair fictif','exploitation':1,
        'stock':7,'stock_oeufs':0,'type_production':'CHAIR','confirmed_business_revision':2}]);
      await fixture.tablet.refreshOutbox();
    });
    await flush(tester,fixture);
    expect(find.text('Stock confirmé : 7'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('sale rereads changed stock and requires review before declaring', (tester) async {
    final fixture = FormFixture(); await tester.runAsync(fixture.start);
    addTearDown(() async {await tester.pumpWidget(const SizedBox()); await tester.runAsync(fixture.finish);});
    await tester.pumpWidget(testApp(OfflineTabletScreen(controller: fixture.tablet)));
    await flush(tester, fixture);
    await tap(tester, find.text('Enregistrer une vente ou un encaissement'));
    await flush(tester, fixture);
    await choose(tester, 'Client', 'Client fictif'); await flush(tester, fixture);
    await choose(tester, 'Lot', 'Lot chair fictif');
    await fill(tester, 'sale-quantity', '8'); await fill(tester, 'sale-price', '15.00');
    await tester.runAsync(() => fixture.tablet.declare(entityType: 'MORTALITE', operationType: 'CREATE',
      payload: {'lot_ref': {'server_id': 7}, 'quantite': 3}, businessOccurredAt: fixture.now));
    await tap(tester, find.text('Conserver sur la tablette')); await flush(tester, fixture);
    expect(find.textContaining('Le stock a changé'), findsOneWidget);
    expect(find.text('Dernier stock confirmé : 10 • stock projeté : 7'), findsOneWidget);
    expect((await tester.runAsync(() => fixture.db.listOutbox()))!, hasLength(1));
    await tap(tester, find.text('Conserver sur la tablette')); await flush(tester, fixture);
    expect(find.text('Indiquez le motif de la survente.'), findsOneWidget);
    await fill(tester, 'sale-note', 'Constat physique à rapprocher');
    await tap(tester, find.text('Conserver sur la tablette')); await flush(tester, fixture);
    final entries = (await tester.runAsync(() => fixture.db.listOutbox()))!;
    expect(entries, hasLength(2));
    final sale = entries.singleWhere((e) => e.declaration['entity_type'] == 'VENTE_ANIMAUX');
    expect(sale.businessStatus, 'UNREVIEWED');
    expect(sale.declaration['payload']['note'], 'Constat physique à rapprocher');
  });
  testWidgets('stock change between dialog review and commit rolls back only the sale', (tester) async {
    final fixture = FormFixture(); await tester.runAsync(fixture.start);
    addTearDown(() async {await tester.pumpWidget(const SizedBox()); await tester.runAsync(fixture.finish);});
    await tester.pumpWidget(testApp(OfflineTabletScreen(controller: fixture.tablet)));
    await flush(tester, fixture);
    await tap(tester, find.text('Enregistrer une vente ou un encaissement'));
    await flush(tester, fixture);
    await choose(tester, 'Client', 'Client fictif'); await flush(tester, fixture);
    await choose(tester, 'Lot', 'Lot chair fictif');
    await fill(tester, 'sale-quantity', '2'); await fill(tester, 'sale-price', '15.00');
    fixture.tablet.beforeDeclaration=() async {
      await fixture.db.enqueue(grant:fixture.tablet.operators!.session!.grant,isSessionCurrent:()=>true,
        entityType:'MORTALITE',operationType:'CREATE',payload:{'lot_ref':{'server_id':7},'quantite':1},
        businessOccurredAt:fixture.now);
    };
    await tap(tester, find.text('Conserver sur la tablette')); await flush(tester, fixture);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await flush(tester, fixture);
    expect(find.text('Le stock a changé pendant la validation. Rouvrez la vente et vérifiez le stock actualisé.'),findsOneWidget);
    final entries=(await tester.runAsync(()=>fixture.db.listOutbox()))!;
    expect(entries,hasLength(1));expect(entries.single.declaration['entity_type'],'MORTALITE');
    final data=(await tester.runAsync(()=>fixture.db.projectedPage('lots')))!
        .firstWhere((row)=>(row['data'] as Map)['id']==7)['data'];
    expect(data,containsPair('projected_stock',9));
  });
  const cases = {
    'ACHAT': {
      'nom_lot': 'Lot acheté fictif',
      'quantite': '10',
      'prix_unitaire': '10',
    },
    'NAISSANCE': {
      'nom_nouveau_lot': 'Lot enfant fictif',
      'total_naissances': '4',
      'mort_nes': '1',
    },
    'MORTALITE': {'quantite': '1'},
    'DON': {'quantite': '1'},
    'VOL': {'quantite': '1'},
    'ALIMENTATION': {
      'aliment': 'Aliment fictif',
      'quantite_kg': '1.000',
      'prix_kg': '12.34',
    },
    'PESEE': {'nombre_animaux_peses': '2', 'poids_total_kg': '3.000'},
    'COLLECTE_OEUFS': {
      'nombre_collecte': '12',
      'nombre_casses': '2',
      'nombre_declasses': '1',
      'nombre_consommes_donnes': '1',
    },
  };
  const labels = {
    'ACHAT': 'Achat',
    'NAISSANCE': 'Naissance',
    'MORTALITE': 'Mortalité',
    'DON': 'Don',
    'VOL': 'Vol',
    'ALIMENTATION': 'Alimentation',
    'PESEE': 'Pesée',
    'COLLECTE_OEUFS': 'Collecte d’œufs',
  };
  for (final operation in cases.entries) {
    testWidgets(
      'real offline ${operation.key} form persists original through encrypted reopen',
      (tester) async {
        final fixture = FormFixture();
        await tester.runAsync(fixture.start);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(fixture.finish);
        });
        await tester.pumpWidget(
          testApp(OfflineTabletScreen(controller: fixture.tablet)),
        );
        await flush(tester, fixture);
        await tap(tester, find.text('Enregistrer une opération terrain'));
        await flush(tester, fixture);
        if (operation.key != 'ALIMENTATION') {
          await choose(tester, 'Opération', labels[operation.key]!);
        }
        if (operation.key == 'ACHAT') {
          await choose(tester, 'Espèce', 'Poulet');
        } else {
          await choose(
            tester,
            operation.key == 'NAISSANCE' ? 'Lot parent / origine' : 'Lot',
            operation.key == 'COLLECTE_OEUFS'
                ? 'Lot ponte fictif'
                : 'Lot chair fictif',
          );
        }
        for (final field in operation.value.entries) {
          await fill(tester, '${operation.key}-${field.key}', field.value);
        }
        await tap(tester, find.text('Conserver sur la tablette'));
        await flush(tester, fixture);
        final entries = await tester.runAsync(() => fixture.db.listOutbox());
        expect(
          entries,
          hasLength(1),
          reason: '${operation.key}: ${tester.takeException()}',
        );
        final original = entries!.single;
        expect(original.declaration['entity_type'], operation.key);
        expect(original.authorId, 2);
        if (operation.key == 'ACHAT') {
          expect(original.declaration['payload']['prix_total'], '100.00');
        }
        expect(fixture.requests, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await fixture.db.close();
          fixture.db = fixture.open();
          final reopened = await fixture.db.listOutbox();
          expect(reopened.single.operationId, original.operationId);
          expect(reopened.single.declaration, original.declaration);
        });
      },
    );
  }
  for (final kind in [
    'CLIENT',
    'VENTE_ANIMAUX',
    'VENTE_OEUFS',
    'ENCAISSEMENT',
    'TASK',
  ]) {
    testWidgets(
      'real offline $kind personal form retains original author and values',
      (tester) async {
        final fixture = FormFixture();
        await tester.runAsync(fixture.start);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(fixture.finish);
        });
        await tester.pumpWidget(
          testApp(OfflineTabletScreen(controller: fixture.tablet)),
        );
        await flush(tester, fixture);
        if (kind == 'CLIENT') {
          await tap(tester, find.text('Enregistrer un client'));
          await tester.enterText(
            find.byType(TextFormField).first,
            'Client créé fictif',
          );
          await tap(tester, find.text('Enregistrer sur la tablette'));
        } else if (kind == 'TASK') {
          await choose(tester, 'Consulter', 'Agenda');
          await flush(tester, fixture);
          await tap(tester, find.text('Tâche fictive'));
          await choose(tester, 'État', 'En cours');
          await tester.enterText(
            find.byType(TextField).last,
            'Compte rendu fictif',
          );
          await tap(tester, find.text('Conserver mon compte rendu'));
        } else {
          await tap(
            tester,
            find.text('Enregistrer une vente ou un encaissement'),
          );
          await flush(tester, fixture);
          if (kind != 'VENTE_ANIMAUX') {
            await choose(
              tester,
              'Opération',
              kind == 'VENTE_OEUFS' ? 'Vente d’œufs' : 'Encaissement reçu',
            );
          }
          await choose(tester, 'Client', 'Client fictif');
          await flush(tester, fixture);
          if (kind == 'ENCAISSEMENT') {
            await fill(tester, 'cash-amount', '30.00');
          } else {
            await choose(
              tester,
              'Lot',
              kind == 'VENTE_OEUFS' ? 'Lot ponte fictif' : 'Lot chair fictif',
            );
            await fill(tester, 'sale-quantity', '2');
            await fill(tester, 'sale-price', '15.00');
          }
          if (kind.startsWith('VENTE_')) {
            final submit=find.text('Conserver sur la tablette');
            await tester.ensureVisible(submit);
            await tester.runAsync(() async {
              await tester.tap(submit);await tester.tap(submit);
              await Future<void>.delayed(const Duration(milliseconds:80));
            });
            await tester.pump();
          } else {
            await tap(tester, find.text('Conserver sur la tablette'));
          }
        }
        await flush(tester, fixture);
        final entries = await tester.runAsync(() => fixture.db.listOutbox());
        expect(entries, hasLength(1));
        expect(entries!.single.declaration['entity_type'], kind);
        expect(entries.single.authorId, 2);
        expect(fixture.requests, 0);
        final original = entries.single;
        final payload = original.declaration['payload'] as Map;
        if (kind == 'CLIENT') expect(payload['nom'], 'Client créé fictif');
        if (kind == 'TASK') {
          expect(payload['status'], 'IN_PROGRESS');
          expect(payload['report'], 'Compte rendu fictif');
        }
        if (kind == 'ENCAISSEMENT') expect(payload['montant_recu'], '30.00');
        if (kind.startsWith('VENTE_')) {
          expect(
            payload['prix_unitaire${kind == 'VENTE_OEUFS' ? '_conditionnement' : ''}'],
            '15.00',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await fixture.db.close();
          fixture.db = fixture.open();
          final reopened = await fixture.db.listOutbox();
          expect(reopened.single.operationId, original.operationId);
          expect(reopened.single.declaration, original.declaration);
        });
      },
    );
  }
}

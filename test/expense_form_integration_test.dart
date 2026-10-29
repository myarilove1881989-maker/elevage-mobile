import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:app_elevage/services/api_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:app_elevage/offline/expense_business_date.dart';
import 'package:app_elevage/offline/expense_form_controller.dart';
import 'package:app_elevage/offline/expense_intention.dart';
import 'package:app_elevage/offline/expense_preparation.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/expense_tablet_adapter.dart';
import 'package:app_elevage/offline/sync_coordinator.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;

class InterruptedTablet extends TabletController {
  InterruptedTablet({
    required super.api,
    required super.secrets,
    required super.clock,
  }) : super(
         automaticSyncEnabled: false,
         networkChanges: () => const Stream.empty(),
       );
  int declarations = 0;
  bool failBefore = false, failAfter = false;
  Completer<void>? beforeWrite, afterWrite;
  @override
  Future<OutboxEntry> declare({
    required String entityType,
    required String operationType,
    required Map<String, dynamic> payload,
    required DateTime businessOccurredAt,
    String? operationId,
    String? localEntityId,
    List<String> dependencies = const [],
    String expectedServerVersion = '',
    Future<void> Function()? project,
  }) async {
    declarations++;
    await beforeWrite?.future;
    if (failBefore) throw StateError('Synthetic interruption before write');
    final entry = await super.declare(
      entityType: entityType,
      operationType: operationType,
      payload: payload,
      businessOccurredAt: businessOccurredAt,
      operationId: operationId,
      localEntityId: localEntityId,
      dependencies: dependencies,
      expectedServerVersion: expectedServerVersion,
      project: project,
    );
    await afterWrite?.future;
    if (failAfter) {
      throw StateError('Synthetic interruption after durable commit');
    }
    return entry;
  }
}

class BrokenSummary implements SyncStateStore {
  @override
  Future<SyncSummary> syncSummary() async =>
      throw StateError('Synthetic post-commit summary error');
  @override
  Future<void> recordSyncSuccess(DateTime time) async =>
      throw StateError('No sync allowed');
}

class InstrumentedDatabase extends FarmDatabase {
  InstrumentedDatabase(
    super.executor, {
    required super.farmId,
    required super.serverNamespace,
    required super.clock,
  });
  bool failLedger = false;
  bool inaccessibleLot = false;
  Completer<void>? categoryGate;
  @override
  Future<List<Map<String, dynamic>>> projectedPage(
    String collection, {
    int offset = 0,
    int limit = 50,
    int? taskUserId,
    String search = '',
  }) async {
    final rows = await super.projectedPage(
      collection,
      offset: offset,
      limit: limit,
      taskUserId: taskUserId,
      search: search,
    );
    if (inaccessibleLot && collection == 'lots' && offset == 0) {
      rows.add({
        'data': {
          'id': '00000000-0000-4000-8000-000000000998',
          'nom': 'Inaccessible',
        },
        'local_uuid': '00000000-0000-4000-8000-000000000998',
        'dependency': '00000000-0000-4000-8000-000000000999',
        'state': 'UNREVIEWED',
      });
    }
    return rows;
  }

  @override
  Future<List<OutboxEntry>> listOutbox({
    int? authorId,
    int limit = 50,
    int offset = 0,
  }) async {
    if (failLedger) throw StateError('Synthetic register unreadable');
    {
      return super.listOutbox(authorId: authorId, limit: limit, offset: offset);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> cachedPage(
    String collection, {
    int offset = 0,
    int limit = 50,
    int? taskUserId,
  }) async {
    if (collection == 'expense_categories') await categoryGate?.future;
    return super.cachedPage(
      collection,
      offset: offset,
      limit: limit,
      taskUserId: taskUserId,
    );
  }
}

void main() {
  tzdata.initializeTimeZones();
  late Directory directory;
  late InstrumentedDatabase db;
  late VerifiedOfflineGrant grant;
  late TestSecretStore secrets;
  late LocalOperatorSessions sessions;
  late FoundationApi api;
  late InterruptedTablet tablet;
  late ExpenseFormController form;
  late DateTime now;
  late Map<String, String> pinSeed;
  late Map<String, dynamic> grantRecord;
  var requests = 0;
  Map<String, dynamic> profile(VerifiedOfflineGrant g) => {
    'user_id': g.userId,
    'membership_id': g.claims['membership_id'],
    'rights_version': g.rightsVersion,
    'write_generation': g.generation,
    'display_name': 'Synthétique',
  };
  setUpAll(() async {
    grant = await fineGrant(
      codes: [
        'finance.read',
        'expenses.create',
        'purchases.create',
        'births.create',
      ],
      issued: (record) => grantRecord = {
        'token': record['authorization'],
        'public_key': record['public_key'],
        'key_id': record['key_id'],
        'device_id': 7,
        'generation': 1,
        'rights_version': 1,
      },
    );
    final seed = TestSecretStore();
    await LocalOperatorSessions(
      store: seed,
      namespace: 'c2-test',
      farmId: 1,
      deviceId: 7,
      generation: 1,
      clock: () => syntheticNow,
    ).enroll(grant, '123456');
    pinSeed = Map.from(seed.values);
  });
  setUp(() async {
    now = syntheticNow;
    requests = 0;
    directory = await Directory.systemTemp.createTemp('elevage-c2-synthetic-');
    db = InstrumentedDatabase(
      encryptedExecutor(
        File('${directory.path}/farm.db'),
        List.filled(64, 'c').join(),
      ),
      farmId: 1,
      serverNamespace: 'c2.invalid',
      clock: () => now,
    );
    await db.replaceConfirmedCache('lots', [
      {
        'id': 10,
        'nom': 'Lot confirmé',
        'statut': 'ACTIF',
        'stock': 5,
        'stock_oeufs': 0,
        'exploitation': 1,
      },
      {
        'id': 11,
        'nom': 'Lot terminé',
        'statut': 'TERMINE',
        'stock': 0,
        'stock_oeufs': 0,
        'exploitation': 1,
      },
    ]);
    await db.replaceConfirmedCache('expense_categories', [
      {'id': 4, 'nom': 'Transport', 'exploitation': 1},
    ]);
    secrets = TestSecretStore()..values.addAll(pinSeed);
    secrets.values['offline_grant_${Uri.encodeComponent('https://c2.invalid/api')}_1_2'] =
        jsonEncode(grantRecord);
    sessions = LocalOperatorSessions(
      store: secrets,
      namespace: 'c2-test',
      farmId: 1,
      deviceId: 7,
      generation: 1,
      clock: () => now,
    );
    expect(await sessions.unlock(grant, '123456'), isTrue);
    api = FoundationApi(
      baseUrl: 'https://c2.invalid/api',
      deviceIdentity: TestIdentity(),
      secrets: secrets,
      clock: () => now,
      client: MockClient((_) async {
        requests++;
        throw StateError('ALL HTTP forbidden in C2 tests');
      }),
    );
    tablet = InterruptedTablet(api: api, secrets: secrets, clock: () => now)
      ..farmId = 1
      ..deviceId = 7
      ..generation = 1
      ..cache = db
      ..operators = sessions
      ..profiles = [profile(grant)]
      ..selectedName = 'Synthétique';
    form = ExpenseFormController(
      tablet,
      ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
    );
    await form.load();
    expect(form.error, isNull);
  });
  tearDown(() async {
    expect(requests, 0, reason: 'No expense HTTP or real synchronization');
    expect(tablet.automaticSyncEnabled, isFalse);
    expect(tablet.sync, isNull);
    form.dispose();
    tablet.dispose();
    api.close();
    await db.close();
    // Only this test's verified unique synthetic directory is removed.
    expect(directory.path, contains('elevage-c2-synthetic-'));
    await directory.delete(recursive: true);
  });
  Future<void> submit({
    ExpenseLotSelection? lot,
    String amount = '12,34',
    int category = 4,
  }) => form.submit(
    lot: lot ?? form.lots.first,
    categoryId: category,
    amount: amount,
    note: 'Été 🐓',
    day: ExpenseBusinessDay(2026, 10, 12),
  );
  Future<List<OutboxEntry>> expenses() async => (await db.listOutbox())
      .where((e) => e.declaration['entity_type'] == 'DEPENSE')
      .toList();
  Future<void> replaceGrant(VerifiedOfflineGrant replacement) async {
    tablet.lock();
    expect(await sessions.unlock(replacement, '123456'), isTrue);
    tablet.profiles = [profile(replacement)];
    tablet.selectedName = 'Synthétique';
  }

  Map<String, dynamic> receipt(OutboxEntry entry, String state) => {
    'client_operation_id': entry.operationId,
    'author_user_id': entry.authorId,
    'transport_status': 'SERVER_RECEIVED',
    'business_status': state,
    'received_at': now.toIso8601String(),
    if (state == 'CONFIRMED') 'applied_at': now.toIso8601String(),
    if (state == 'CONFIRMED') 'server_entity_id': '101',
  };

  test(
    'authorized OP creates one exact immutable local expense via actual encrypted outbox',
    () async {
      await submit();
      final entry = (await expenses()).single;
      expect(form.result.state, ExpenseDurableState.durable);
      expect(entry.operationId, form.operationId);
      expect(entry.declaration['local_entity_id'], form.operationId);
      expect(entry.declaration['payload'], {
        'lot_ref': {'server_id': 10},
        'categorie_id': 4,
        'montant': '12.34',
        'note': 'Été 🐓',
      });
      expect(
        entry.declaration['business_occurred_at'],
        '2026-10-12T12:00:00.000Z',
      );
      expect(entry.declaration['author_user_id'], 2);
      expect(entry.declaration['exploitation_id'], 1);
      expect(
        entry.declaration['offline_authorization_id'],
        grant.claims['jti'],
      );
      expect(entry.sequence, 1);
      expect(expenseStatusText(form.result), contains('sur cet appareil'));
    },
  );
  test('local purchase lot preserves original dependency', () async {
    final parent = await tablet.declare(
      entityType: 'ACHAT',
      operationType: 'CREATE',
      payload: {
        'nom_lot': 'Local',
        'quantite': 2,
        'prix_unitaire': '1.00',
        'prix_total': '2.00',
      },
      businessOccurredAt: now,
    );
    await form.load();
    final local = form.lots.singleWhere(
      (l) => l.reference.containsKey('local_uuid'),
    );
    await submit(lot: local);
    expect((await expenses()).single.declaration['dependencies'], [
      parent.operationId,
    ]);
    expect(
      ((await expenses()).single.declaration['payload'] as Map)['lot_ref'],
      {'local_uuid': parent.declaration['local_entity_id']},
    );
  });
  test('finished lot is allowed with explicit indication', () async {
    final finished = form.lots.singleWhere((l) => l.isFinished);
    await submit(lot: finished);
    expect(
      (await expenses()).single.declaration['payload'],
      containsPair('lot_ref', {'server_id': 11}),
    );
  });
  test(
    'all category pages beyond 200 remain selectable and unverified',
    () async {
      await db.replaceConfirmedCache(
        'expense_categories',
        List.generate(
          251,
          (i) => {'id': i + 1, 'nom': 'Catégorie $i', 'exploitation': 1},
        ),
      );
      await form.load();
      expect(form.categories!.catalog.categories, hasLength(251));
      expect(form.categories!.catalog.freshness, ExpenseCacheFreshness.unknown);
      await submit(category: 251);
      expect(
        (await expenses()).single.declaration['payload'],
        containsPair('categorie_id', 251),
      );
    },
  );
  for (final value in ['0', '1.234', '1e2', ' 1 ', '10000000000']) {
    test('invalid exact amount $value creates no intention or row', () async {
      await submit(amount: value);
      expect(form.fieldErrors, contains('montant'));
      expect(form.operationId, isNull);
      expect(await expenses(), isEmpty);
    });
  }
  test('missing fields have independent errors', () async {
    await form.submit(
      lot: null,
      categoryId: null,
      amount: '',
      day: ExpenseBusinessDay(2026, 10, 12),
    );
    expect(
      form.fieldErrors.keys,
      containsAll(['lot_ref', 'categorie_id', 'montant']),
    );
    expect(tablet.declarations, 0);
  });
  test('future business day refuses before any boundary', () async {
    await form.submit(
      lot: form.lots.first,
      categoryId: 4,
      amount: '1',
      day: ExpenseBusinessDay(2026, 10, 13),
    );
    expect(form.error, contains('Date métier'));
    expect(tablet.declarations, 0);
  });
  test('OWNER HTTP identity cannot replace signed operator context', () async {
    api.personal = OnlineOperatorIdentity(
      userId: 2,
      farmId: 1,
      role: 'OWNER',
      capabilities: {},
      access: 'synthetic',
      refresh: 'synthetic',
    );
    await submit();
    expect(await expenses(), isEmpty);
    expect(form.suspended, isTrue);
  });
  for (final legacy in [false, true]) {
    test(
      legacy ? 'V1 refused' : 'V2 without expenses.create refused',
      () async {
        await replaceGrant(
          await fineGrant(legacy: legacy, codes: ['finance.read']),
        );
        form.dispose();
        form = ExpenseFormController(
          tablet,
          ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
        );
        await form.load();
        expect(form.error, isNotNull);
        expect(await expenses(), isEmpty);
        expect(tablet.declarations, 0);
      },
    );
  }
  test('locked PIN masks draft and forbids writing', () async {
    tablet.lock();
    form.checkContext();
    expect(form.suspended, isTrue);
    expect(form.lots, isEmpty);
    expect(form.editable, isFalse);
    expect(await expenses(), isEmpty);
  });
  test('actual session expiry masks draft', () async {
    now = now.add(const Duration(days: 2));
    form.checkContext();
    expect(sessions.session, isNull);
    expect(form.suspended, isTrue);
    expect(form.editable, isFalse);
  });
  test('synchronous double click reserves one UUID and one sequence', () async {
    tablet.beforeWrite = Completer<void>();
    final first = submit();
    final uuid = form.operationId;
    expect(form.busy, isTrue);
    await submit();
    expect(form.operationId, uuid);
    while (tablet.declarations == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(tablet.declarations, 1);
    tablet.beforeWrite!.complete();
    await first;
    expect(await expenses(), hasLength(1));
    await submit();
    expect(tablet.declarations, 1);
  });
  test(
    'exception before write stays uncertain and never blindly retries',
    () async {
      tablet.failBefore = true;
      await submit();
      final uuid = form.operationId;
      expect(form.result.state, ExpenseDurableState.uncertain);
      expect(await expenses(), isEmpty);
      await form.verify();
      await submit();
      expect(form.operationId, uuid);
      expect(tablet.declarations, 1);
    },
  );
  test(
    'exception after durable commit finds original UUID without duplicate',
    () async {
      tablet.failAfter = true;
      await submit();
      final uuid = form.operationId;
      expect(form.result.state, ExpenseDurableState.durable);
      await form.verify();
      await submit();
      expect((await expenses()).single.operationId, uuid);
      expect(tablet.declarations, 1);
    },
  );
  test('simulated network cut needs no transport for local creation', () async {
    await submit();
    expect(await expenses(), hasLength(1));
    expect(requests, 0);
  });
  test(
    'late response after profile lock cannot publish and explicit original reopen reads only',
    () async {
      tablet.afterWrite = Completer<void>();
      final flight = submit();
      while ((await expenses()).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final uuid = form.operationId;
      tablet.lock();
      tablet.afterWrite!.complete();
      await flight;
      expect(form.suspended, isTrue);
      expect(form.result.state, ExpenseDurableState.uncertain);
      await replaceGrant(grant);
      await form.verify();
      expect(form.result.state, ExpenseDurableState.durable);
      expect(form.suspended, isTrue);
      expect(form.operationId, uuid);
      expect(await expenses(), hasLength(1));
      expect(form.editable, isFalse);
    },
  );
  test(
    'explicit recovered result is hidden on a subsequent session transition',
    () async {
      await submit();
      await replaceGrant(grant);
      await form.verify();
      expect(form.resultVisible, isTrue);
      expect(form.suspended, isTrue);
      tablet.lock();
      form.checkContext();
      expect(form.resultVisible, isFalse);
      expect(form.editable, isFalse);
      expect(await expenses(), hasLength(1));
    },
  );
  test(
    'explicit existing PIN reopens original profile for register consultation only',
    () async {
      await submit();
      final uuid = form.operationId;
      tablet.lock();
      await form.reopenOriginal('123456');
      expect(form.error, isNull);
      expect(form.resultVisible, isTrue);
      expect(form.result.state, ExpenseDurableState.durable);
      expect(form.suspended, isTrue);
      expect(form.editable, isFalse);
      expect(form.operationId, uuid);
      expect((await expenses()).single.operationId, uuid);
      expect(tablet.declarations, 1);
    },
  );
  test(
    'incorrect existing PIN does not create or reactivate anything',
    () async {
      await submit();
      tablet.lock();
      await form.reopenOriginal('000000');
      expect(form.error, isNotNull);
      expect(form.resultVisible, isFalse);
      expect(sessions.session, isNull);
      expect(form.editable, isFalse);
      expect(await expenses(), hasLength(1));
      expect(tablet.declarations, 1);
    },
  );
  test('renewed stored grant is refused before explicit PIN unlock', () async {
    await submit();
    tablet.lock();
    await fineGrant(
      codes: ['finance.read', 'expenses.create'],
      grantId: '00000000-0000-4000-8000-000000000099',
      issued: (record) =>
          secrets.values['offline_grant_${Uri.encodeComponent('https://c2.invalid/api')}_1_2'] =
              jsonEncode({
                'token': record['authorization'],
                'public_key': record['public_key'],
                'key_id': record['key_id'],
                'device_id': 7,
                'generation': 1,
                'rights_version': 1,
              }),
    );
    await form.reopenOriginal('123456');
    expect(form.error, isNotNull);
    expect(sessions.session, isNull);
    expect(form.resultVisible, isFalse);
    expect(await expenses(), hasLength(1));
    expect(tablet.declarations, 1);
  });
  test('round trip to same profile never reactivates draft', () async {
    await replaceGrant(grant);
    form.checkContext();
    expect(form.suspended, isTrue);
    expect(form.editable, isFalse);
    expect(await expenses(), isEmpty);
  });
  test('renewed grant cannot recover original intention', () async {
    await submit();
    await replaceGrant(
      await fineGrant(
        codes: ['finance.read', 'expenses.create'],
        grantId: '00000000-0000-4000-8000-000000000099',
      ),
    );
    await form.verify();
    expect(form.error, isNotNull);
    expect(form.suspended, isTrue);
    expect(await expenses(), hasLength(1));
  });
  for (final state in [
    'UNREVIEWED',
    'CONFIRMED',
    'NEEDS_RECONCILIATION',
    'NOT_APPLIED',
  ]) {
    test('explicit register read displays simulated receipt $state', () async {
      await submit();
      final entry = (await expenses()).single;
      await db.acceptReceipts([receipt(entry, state)]);
      await form.verify();
      expect(form.result.state, switch (state) {
        'CONFIRMED' => ExpenseDurableState.confirmed,
        'NEEDS_RECONCILIATION' => ExpenseDurableState.reconciliation,
        'NOT_APPLIED' => ExpenseDurableState.notApplied,
        _ => ExpenseDurableState.durable,
      });
      if (state == 'UNREVIEWED') {
        expect(expenseStatusText(form.result), contains('Reçu par le serveur'));
      }
      expect(tablet.declarations, 1);
    });
  }
  test('ambiguous category cache blocks validation', () async {
    await db.replaceConfirmedCache('expense_categories', [
      {'id': 4, 'nom': '', 'exploitation': 1},
    ]);
    await form.load();
    expect(form.error, isNotNull);
  });
  test(
    'real declare post-commit summary failure still recovers original entry',
    () async {
      var syncCalls = 0;
      tablet.sync = SyncCoordinator(
        store: BrokenSummary(),
        networkChanges: () => const Stream.empty(),
        synchronize: () async {
          syncCalls++;
          throw StateError('No synchronization allowed');
        },
      );
      await submit();
      expect(form.result.state, ExpenseDurableState.durable);
      expect(await expenses(), hasLength(1));
      expect(syncCalls, 0);
      tablet.sync!.dispose();
      tablet.sync = null;
    },
  );
  test(
    'unreadable original register remains uncertain after actual commit',
    () async {
      db.failLedger = true;
      await submit();
      expect(form.result.state, ExpenseDurableState.uncertain);
      final uuid = form.operationId;
      db.failLedger = false;
      expect((await expenses()).single.operationId, uuid);
      await form.verify();
      expect(form.result.state, ExpenseDurableState.durable);
      expect(tablet.declarations, 1);
    },
  );
  test(
    'UUID lookup traverses original register beyond bounded UI rows',
    () async {
      await submit();
      final uuid = form.operationId;
      for (var i = 0; i < 51; i++) {
        await db.enqueue(
          grant: grant,
          isSessionCurrent: () => true,
          entityType: 'DEPENSE',
          operationType: 'CREATE',
          payload: {
            'lot_ref': {'server_id': 10},
            'categorie_id': 4,
            'montant': '1.00',
            'note': 'Autre synthétique $i',
          },
          businessOccurredAt: now,
        );
      }
      expect(
        (await db.listOutbox()).map((e) => e.operationId),
        isNot(contains(uuid)),
      );
      await form.verify();
      expect(form.result.entry!.operationId, uuid);
      expect(tablet.declarations, 1);
    },
  );
  test('stale categories remain explicitly qualified', () async {
    form.categories = await ExpenseTabletReadBridge(
      form.observer,
      form.observer.capture(),
    ).categories(freshness: ExpenseCacheFreshness.stale);
    expect(form.categories!.catalog.needsFreshnessNotice, isTrue);
    await submit();
    expect(form.result.state, ExpenseDurableState.durable);
  });
  test('disappeared selected category is never replaced or written', () async {
    await db.replaceConfirmedCache('expense_categories', [
      {'id': 5, 'nom': 'Autre', 'exploitation': 1},
    ]);
    await submit();
    expect(form.error, isNotNull);
    expect(tablet.declarations, 0);
    expect(await expenses(), isEmpty);
    expect(form.operationId, isNotNull);
  });
  test(
    'profile switch during awaited category reread prevents the write',
    () async {
      db.categoryGate = Completer<void>();
      final lot = form.lots.first;
      final flight = submit(lot: lot);
      expect(form.operationId, isNotNull);
      tablet.lock();
      db.categoryGate!.complete();
      await flight;
      expect(form.suspended, isTrue);
      expect(tablet.declarations, 0);
      expect(await expenses(), isEmpty);
    },
  );
  test(
    'colleague local lot is selectable and expense keeps its own author',
    () async {
      final other = await fineGrant(
        user: 3,
        expectedUser: 3,
        codes: ['finance.read', 'purchases.create'],
      );
      final parent = await db.enqueue(
        grant: other,
        isSessionCurrent: () => true,
        entityType: 'ACHAT',
        operationType: 'CREATE',
        payload: {
          'nom_lot': 'Autre auteur',
          'quantite': 2,
          'prix_unitaire': '1.00',
          'prix_total': '2.00',
        },
        businessOccurredAt: now,
      );
      await form.load();
      expect(form.error, isNull);
      expect(form.editable, isTrue);
      expect(form.lots.any((lot) => lot.reference['server_id'] == 10), isTrue);
      await submit(
        lot: form.lots.singleWhere((lot) => lot.name == 'Autre auteur'),
      );
      final expense = (await expenses()).single;
      expect(expense.authorId, 2);
      expect(expense.declaration['dependencies'], [parent.operationId]);
      expect(expense.declaration['payload']['lot_ref'], {
        'local_uuid': parent.declaration['local_entity_id'],
      });
      expect(
        (await db.listOutbox(authorId: 3)).single.declaration,
        parent.declaration,
      );
    },
  );
  test(
    'inaccessible local reference does not hide a valid confirmed lot',
    () async {
      db.inaccessibleLot = true;
      await form.load();
      expect(form.error, isNull);
      expect(form.lots.any((lot) => lot.name == 'Inaccessible'), isFalse);
      await submit(
        lot: form.lots.firstWhere((lot) => lot.reference['server_id'] == 10),
      );
      expect((await expenses()).single.authorId, 2);
    },
  );
  testWidgets(
    'real screen submit and double click create only one local expense',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: AddDepenseScreen(tablet: tablet)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.tap(
        find.byType(DropdownButtonFormField<ExpenseLotSelection>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lot confirmé').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transport').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('expense-amount')), '0,29');
      await tester.ensureVisible(find.byKey(const Key('expense-submit')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('expense-submit')));
        await tester.tap(find.byKey(const Key('expense-submit')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final rows = await expenses();
        expect(rows, hasLength(1));
        expect(
          rows.single.declaration['payload'],
          containsPair('montant', '0.29'),
        );
      });
      await tester.pump();
      for(var attempt=0;attempt<100 && find.textContaining('Enregistré sur cet appareil').evaluate().isEmpty;attempt++) {
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));
        await tester.pump();
      }
      expect(
        find.textContaining('Enregistré sur cet appareil'),
        findsOneWidget,
      );
      expect(tablet.declarations, 1);
      tablet.lock();
      await tester.pump();
      expect(find.byKey(const Key('expense-amount')), findsNothing);
      expect(find.textContaining('Le brouillon est masqué'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('screen shows warning and field errors, performs no HTTP', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: AddDepenseScreen(tablet: tablet)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(
      find.textContaining('cohérence transactionnelle non vérifiée'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('expense-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-submit')));
    await tester.pump();
    expect(find.text('Champ obligatoire.'), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
    expect(tablet.declarations, 0);
  });
  testWidgets('repeated navigation never declares on screen opening', (
    tester,
  ) async {
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: AddDepenseScreen(key: ValueKey(i), tablet: tablet),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    }
    await tester.runAsync(() async {
      expect(await expenses(), isEmpty);
    });
    expect(tablet.declarations, 0);
  });
  testWidgets(
    'dashboard entry without tablet does not create session or synchronize',
    (tester) async {
      final api = ApiService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'user': 2,
              'exploitation': 1,
              'role': 'OPERATEUR',
              'offline_policy_enabled': true,
              'membership': {'version': 1},
              'permission_contract': {
                'version': 1,
                'user': 2,
                'exploitation': 1,
                'role': 'OPERATEUR',
                'rights_version': 1,
                'permissions': ['finance.read', 'expenses.create'],
              },
            }),
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: AddDepenseScreen(apiService: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ouvrir l’espace éleveur'), findsOneWidget);
      expect(find.byKey(const Key('expense-submit')), findsNothing);
      expect(tablet.declarations, 0);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}

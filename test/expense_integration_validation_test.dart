import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
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
import 'package:app_elevage/offline/sync_coordinator.dart';
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
  bool failBefore = false, failAfter = false, timeoutBefore = false;
  Completer<void>? beforeWrite, afterWrite;
  Future<void> Function()? transactionHook;
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
    if (timeoutBefore) throw TimeoutException('Synthetic timeout before write');
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
      project: project ?? transactionHook,
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
  bool failLedger = false, hideLedger = false;
  Completer<void>? ledgerGate;
  Completer<void>? categoryGate;
  @override
  Future<List<OutboxEntry>> listOutbox({
    int? authorId,
    int limit = 50,
    int offset = 0,
  }) async {
    await ledgerGate?.future;
    if (hideLedger) return [];
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
      namespace: 'd-test',
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
    directory = await Directory.systemTemp.createTemp('elevage-d-synthetic-');
    db = InstrumentedDatabase(
      encryptedExecutor(
        File('${directory.path}/farm.db'),
        List.filled(64, 'c').join(),
      ),
      farmId: 1,
      serverNamespace: 'd.invalid',
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
    secrets.values['offline_grant_${Uri.encodeComponent('https://d.invalid/api')}_1_2'] =
        jsonEncode(grantRecord);
    sessions = LocalOperatorSessions(
      store: secrets,
      namespace: 'd-test',
      farmId: 1,
      deviceId: 7,
      generation: 1,
      clock: () => now,
    );
    expect(await sessions.unlock(grant, '123456'), isTrue);
    api = FoundationApi(
      baseUrl: 'https://d.invalid/api',
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
    expect(directory.path, contains('elevage-d-synthetic-'));
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

  InstrumentedDatabase reopenDatabase() => InstrumentedDatabase(
    encryptedExecutor(
      File('${directory.path}/farm.db'),
      List.filled(64, 'c').join(),
    ),
    farmId: 1,
    serverNamespace: 'd.invalid',
    clock: () => now,
  );
  Future<void> restartStorage() async {
    form.dispose();
    tablet.lock();
    await db.close();
    db = reopenDatabase();
    tablet.cache = db;
    expect(await sessions.unlock(grant, '123456'), isTrue);
    tablet.selectedName = 'Synthétique';
    form = ExpenseFormController(
      tablet,
      ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
    );
    await form.load();
    expect(form.error, isNull);
  }

  Future<OutboxEntry> localParent(String kind) => tablet.declare(
    entityType: kind,
    operationType: 'CREATE',
    businessOccurredAt: now,
    payload: kind == 'ACHAT'
        ? {
            'nom_lot': 'Local',
            'quantite': 3,
            'prix_unitaire': '1.00',
            'prix_total': '3.00',
          }
        : {
            'lot_ref': {'server_id': 10},
            'nom_nouveau_lot': 'Enfant',
            'total_naissances': 4,
            'mort_nes': 1,
          },
  );
  Future<ExpenseLotSelection> selectLocal() async {
    await form.load();
    expect(form.error, isNull);
    return form.lots.singleWhere((l) => l.reference.containsKey('local_uuid'));
  }

  Future<void> mapParent(OutboxEntry parent) => db.acceptReceipts([
    {
      ...receipt(parent, 'CONFIRMED'),
      'server_entity_id': '30',
      'entity_mappings': [
        {
          'entity_type': 'LOT',
          'local_entity_id': parent.declaration['local_entity_id'],
          'server_entity_id': 42,
        },
        {
          'entity_type': parent.declaration['entity_type'],
          'local_entity_id': parent.declaration['local_entity_id'],
          'server_entity_id': 30,
        },
      ],
      'stock_snapshots': [
        {
          'id': 42,
          'nom': 'Lot confirmé ultérieurement',
          'exploitation': 1,
          'stock': 3,
          'stock_oeufs': 0,
          'type_production': 'CHAIR',
          'confirmed_business_revision': 1,
        },
      ],
    },
  ]);

  for (final kind in ['ACHAT', 'NAISSANCE']) {
    test(
      'D encrypted restart preserves original $kind dependency and entire declaration',
      () async {
        final parent = await localParent(kind);
        final local = await selectLocal();
        await submit(lot: local);
        final saved = (await expenses()).single;
        final declaration = canonicalDeclaration(saved.declaration);
        expect(saved.declaration['dependencies'], [parent.operationId]);
        expect(saved.declaration['local_entity_id'], saved.operationId);
        final file = await File('${directory.path}/farm.db').readAsBytes();
        expect(
          file.take(16).toList(),
          isNot(utf8.encode('SQLite format 3\u0000')),
        );
        final schema =
            (await db
                    .customSelect(
                      'SELECT name,sql FROM sqlite_master ORDER BY name',
                    )
                    .get())
                .map((r) => r.data)
                .toList();
        await restartStorage();
        final found = (await expenses()).single;
        expect(found.operationId, saved.operationId);
        expect(canonicalDeclaration(found.declaration), declaration);
        expect(found.transportStatus, 'LOCAL_PENDING');
        expect(found.businessStatus, 'UNREVIEWED');
        expect((await db.listOutbox()).length, 2);
        expect(tablet.declarations, 2);
        expect(
          (await db
                  .customSelect(
                    'SELECT name,sql FROM sqlite_master ORDER BY name',
                  )
                  .get())
              .map((r) => r.data)
              .toList(),
          schema,
        );
        expect(form.operationId, isNull);
        expect(form.result.state, ExpenseDurableState.notRecorded);
      },
    );
    test(
      'D subsequent $kind mapping never rewrites historical expense',
      () async {
        final parent = await localParent(kind);
        await submit(lot: await selectLocal());
        final original = canonicalDeclaration(
          (await expenses()).single.declaration,
        );
        await mapParent(parent);
        expect(
          (await db.projectedPage(
            'lots',
          )).any((r) => (r['data'] as Map)['id'] == 42),
          isTrue,
        );
        await form.verify();
        expect(form.result.state, ExpenseDurableState.durable);
        expect(
          canonicalDeclaration((await expenses()).single.declaration),
          original,
        );
        await restartStorage();
        expect(
          canonicalDeclaration((await expenses()).single.declaration),
          original,
        );
        expect(tablet.declarations, 2);
      },
    );
  }
  test(
    'D abandoned invalid draft disappears while durable operations survive restart',
    () async {
      await submit(amount: '1.234');
      expect(form.operationId, isNull);
      expect(await expenses(), isEmpty);
      await restartStorage();
      expect(form.operationId, isNull);
      expect(await expenses(), isEmpty);
      await submit(amount: '0.01');
      final id = form.operationId;
      await restartStorage();
      expect((await expenses()).single.operationId, id);
      expect(tablet.declarations, 1);
    },
  );
  test(
    'D disposed screen after durable commit never publishes or creates a retry',
    () async {
      tablet.afterWrite = Completer<void>();
      final old = form;
      final flight = submit();
      while ((await expenses()).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final id = old.operationId;
      var publishes = 0;
      old.addListener(() => publishes++);
      old.dispose();
      tablet.afterWrite!.complete();
      await flight;
      expect(publishes, 0);
      form = ExpenseFormController(
        tablet,
        ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
      );
      await form.load();
      expect((await expenses()).single.operationId, id);
      expect(tablet.declarations, 1);
    },
  );
  test('D interruption before validation allocates no UUID', () async {
    var once = false;
    form.addListener(() {
      if (!once) {
        once = true;
        tablet.lock();
      }
    });
    await submit();
    expect(form.operationId, isNull);
    expect(tablet.declarations, 0);
    expect(await expenses(), isEmpty);
  });
  test(
    'D interruption after UUID reservation and before declare retains UUID without write',
    () async {
      db.categoryGate = Completer<void>();
      final selected = form.lots.first;
      final flight = submit(lot: selected);
      final id = form.operationId;
      expect(id, isNotNull);
      expect(form.coordinator.current!.busy, isTrue);
      tablet.lock();
      db.categoryGate!.complete();
      await flight;
      expect(form.operationId, id);
      expect(tablet.declarations, 0);
      expect(await expenses(), isEmpty);
      expect(form.suspended, isTrue);
    },
  );
  test(
    'D timeout at entry into declare is uncertain and has no blind retry',
    () async {
      tablet.timeoutBefore = true;
      await submit();
      final id = form.operationId;
      expect(form.result.state, ExpenseDurableState.uncertain);
      expect(await expenses(), isEmpty);
      await form.verify();
      expect(form.operationId, id);
      expect(form.result.state, ExpenseDurableState.uncertain);
      expect(tablet.declarations, 1);
    },
  );
  test(
    'D partial register after commit cannot prove absence and never allocates another UUID',
    () async {
      db.hideLedger = true;
      await submit();
      final id = form.operationId;
      expect(form.result.state, ExpenseDurableState.uncertain);
      expect(form.editable, isFalse);
      await form.verify();
      expect(form.operationId, id);
      expect(tablet.declarations, 1);
      db.hideLedger = false;
      expect((await expenses()).single.operationId, id);
      await form.verify();
      expect(form.result.state, ExpenseDurableState.durable);
    },
  );
  test(
    'D profile changes while register read is delayed prevent publishing original result',
    () async {
      db.ledgerGate = Completer<void>();
      final flight = submit();
      while (tablet.declarations == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      while ((await db
                  .customSelect('SELECT COUNT(*) AS n FROM outbox')
                  .getSingle())
              .read<int>('n') ==
          0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      tablet.lock();
      db.ledgerGate!.complete();
      await flight;
      expect(form.suspended, isTrue);
      expect(form.resultVisible, isFalse);
      expect(form.result.state, ExpenseDurableState.uncertain);
      expect(await expenses(), hasLength(1));
    },
  );
  test(
    'D transition immediately before final UI notification masks the result',
    () async {
      var once = false;
      form.addListener(() {
        if (!once &&
            !form.busy &&
            form.result.state == ExpenseDurableState.durable) {
          once = true;
          tablet.lock();
        }
      });
      await submit();
      expect(once, isTrue);
      expect(form.suspended, isTrue);
      expect(form.resultVisible, isFalse);
      expect(await expenses(), hasLength(1));
      expect(tablet.declarations, 1);
    },
  );
  for (final transition in [
    'farm',
    'generation',
    'device',
    'revocation',
    'recovery',
    'profile',
  ]) {
    test('D original result cannot cross $transition transition', () async {
      await submit();
      final id = form.operationId;
      switch (transition) {
        case 'farm':
          tablet.farmId = 9;
        case 'generation':
          tablet.generation = 2;
        case 'device':
          tablet.deviceId = 8;
        case 'revocation':
          tablet.knownDeviceRevoked = true;
        case 'recovery':
          tablet.recovering = true;
        case 'profile':
          final other = await fineGrant(
            user: 3,
            expectedUser: 3,
            codes: ['finance.read', 'expenses.create'],
          );
          final otherSessions = LocalOperatorSessions(
            store: secrets,
            namespace: 'd-other',
            farmId: 1,
            deviceId: 7,
            generation: 1,
            clock: () => now,
          );
          await otherSessions.enroll(other, '654321');
          expect(await otherSessions.unlock(other, '654321'), isTrue);
          tablet.operators = otherSessions;
          tablet.profiles = [profile(other)];
      }
      form.checkContext();
      await form.verify();
      expect(form.suspended, isTrue);
      expect(form.resultVisible, isFalse);
      expect(form.operationId, id);
      final saved = (await expenses()).single;
      expect(saved.authorId, 2);
      expect(saved.declaration['exploitation_id'], 1);
      expect(tablet.declarations, 1);
    });
  }
  test(
    'D two authorized synthetic profiles preserve authors and shared monotonic sequence',
    () async {
      await submit();
      final first = (await expenses()).single;
      final other = await fineGrant(
        user: 3,
        expectedUser: 3,
        codes: ['finance.read', 'expenses.create'],
      );
      final otherSessions = LocalOperatorSessions(
        store: secrets,
        namespace: 'd-other',
        farmId: 1,
        deviceId: 7,
        generation: 1,
        clock: () => now,
      );
      await otherSessions.enroll(other, '654321');
      expect(await otherSessions.unlock(other, '654321'), isTrue);
      tablet.lock();
      tablet.operators = otherSessions;
      tablet.profiles = [profile(other)];
      tablet.selectedName = 'Synthétique';
      form.dispose();
      form = ExpenseFormController(
        tablet,
        ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
      );
      await form.load();
      await submit();
      final rows = await expenses();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.authorId).toSet(), {2, 3});
      expect(rows.map((r) => r.sequence).toSet(), {1, 2});
      expect(rows.map((r) => r.operationId).toSet(), hasLength(2));
      expect(
        canonicalDeclaration(
          rows.singleWhere((r) => r.authorId == 2).declaration,
        ),
        canonicalDeclaration(first.declaration),
      );
    },
  );
  for (final state in ['WAITING_DEPENDENCY', 'NEEDS_RECONCILIATION']) {
    test(
      'D pending local parent $state retains original reference and dependency',
      () async {
        final parent = await localParent('NAISSANCE');
        await db.acceptReceipts([receipt(parent, state)]);
        await submit(lot: await selectLocal());
        final entry = (await expenses()).single;
        expect(entry.declaration['dependencies'], [parent.operationId]);
        expect((entry.declaration['payload'] as Map)['lot_ref'], {
          'local_uuid': parent.declaration['local_entity_id'],
        });
      },
    );
  }
  test(
    'D missing original parent is excluded without fabricating a server reference',
    () async {
      final parent=await localParent('ACHAT');
      db.hideLedger = true;
      await form.load();
      expect(form.lots.where((lot)=>lot.reference['local_uuid']==parent.declaration['local_entity_id']),isEmpty);
      db.hideLedger = false;
      expect(await expenses(), isEmpty);
      expect(tablet.declarations, 1);
    },
  );
  test(
    'D parent from another farm cannot enter original expense provenance',
    () async {
      final foreign = await fineGrant(
        farm: 2,
        expectedFarm: 2,
        codes: ['finance.read', 'purchases.create'],
      );
      await expectLater(
        db.enqueue(
          grant: foreign,
          isSessionCurrent: () => true,
          entityType: 'ACHAT',
          operationType: 'CREATE',
          payload: {'nom_lot': 'Étranger', 'quantite': 1},
          businessOccurredAt: now,
        ),
        throwsStateError,
      );
      expect(await db.listOutbox(), isEmpty);
      expect(tablet.declarations, 0);
    },
  );
  for (final amount in ['0.01', '9999999999.99', '0,29']) {
    test('D actual outbox preserves exact amount $amount', () async {
      await submit(amount: amount);
      expect(form.error, isNull);
      final entry = (await expenses()).single;
      expect(
        entry.declaration['payload'],
        containsPair('montant', amount.replaceAll(',', '.')),
      );
      expect(
        canonicalDeclaration(entry.declaration['payload']),
        canonicalDeclaration(form.coordinator.current!.prepared.payload),
      );
    });
  }
  for (final amount in [
    '1 000.00',
    '1_000.00',
    '1,2,3',
    '+1',
    '١٢',
    '1.000,00',
  ]) {
    test('D unsupported separator or digits $amount never writes', () async {
      await submit(amount: amount);
      expect(form.fieldErrors, contains('montant'));
      expect(form.operationId, isNull);
      expect(await expenses(), isEmpty);
    });
  }
  final dateCases = [
    [2026, 1, 15, 11],
    [2026, 3, 28, 11],
    [2026, 3, 29, 10],
    [2026, 7, 15, 10],
    [2025, 10, 25, 10],
    [2025, 10, 26, 11],
  ];
  for (final parts in dateCases) {
    test(
      'D stale calendar date ${parts.take(3).join('-')} uses the system recording timestamp',
      () async {
        await form.submit(
          lot: form.lots.first,
          categoryId: 4,
          amount: '1',
          note: 'e\u0301 🐓 漢字',
          day: ExpenseBusinessDay(parts[0], parts[1], parts[2]),
        );
        final entry = (await expenses()).single;
        expect(
          entry.declaration['business_occurred_at'],
          now.toIso8601String(),
        );
        expect(
          entry.declaration['payload'],
          containsPair('note', 'e\u0301 🐓 漢字'),
        );
        expect(
          canonicalDeclaration(entry.declaration['payload']),
          canonicalDeclaration(form.coordinator.current!.prepared.payload),
        );
      },
    );
  }
  test(
    'D Paris day changes before UTC day and keeps the exact system timestamp',
    () async {
      now = DateTime.utc(2026, 10, 12, 22, 30);
      await form.submit(
        lot: form.lots.first,
        categoryId: 4,
        amount: '1',
        day: ExpenseBusinessDay(2026, 10, 13),
      );
      expect(form.error, isNull);
      expect(
        (await expenses()).single.declaration['business_occurred_at'],
        now.toIso8601String(),
      );
    },
  );
  test(
    'D empty category cache cannot record an inferred replacement',
    () async {
      await db.replaceConfirmedCache('expense_categories', []);
      await form.load();
      await submit();
      expect(form.error, isNotNull);
      expect(form.operationId, isNull);
      expect(await expenses(), isEmpty);
    },
  );
  test(
    'D incomplete confirmation receipt is refused and original ledger remains untouched',
    () async {
      await submit();
      final entry = (await expenses()).single;
      final declaration = canonicalDeclaration(entry.declaration);
      final incomplete = receipt(entry, 'CONFIRMED')..remove('applied_at');
      await expectLater(db.acceptReceipts([incomplete]), throwsStateError);
      await form.verify();
      expect(form.result.state, ExpenseDurableState.durable);
      expect((await expenses()).single.transportStatus, 'LOCAL_PENDING');
      expect(
        canonicalDeclaration((await expenses()).single.declaration),
        declaration,
      );
    },
  );
  test(
    'D confirmed expense and receipt replay preserve original declaration across restart',
    () async {
      await submit();
      final entry = (await expenses()).single;
      final declaration = canonicalDeclaration(entry.declaration);
      final confirmed = receipt(entry, 'CONFIRMED');
      await db.acceptReceipts([confirmed]);
      await db.acceptReceipts([confirmed]);
      await form.verify();
      expect(form.result.state, ExpenseDurableState.confirmed);
      await restartStorage();
      final saved = (await expenses()).single;
      expect(saved.businessStatus, 'CONFIRMED');
      expect(saved.receivedAt, now);
      expect(saved.appliedAt, now);
      expect(canonicalDeclaration(saved.declaration), declaration);
      expect(tablet.declarations, 1);
    },
  );

  test(
    'D transaction exception before commit rolls back without blind retry or consumed sequence',
    () async {
      tablet.transactionHook = () async {
        throw StateError('Synthetic exception inside original transaction');
      };
      await submit();
      final id = form.operationId;
      expect(id, isNotNull);
      expect(await expenses(), isEmpty);
      expect(form.result.state, ExpenseDurableState.uncertain);
      expect(
        (await db
                .customSelect(
                  'SELECT next_sequence FROM local_sequence_counter WHERE singleton=1',
                )
                .getSingle())
            .read<int>('next_sequence'),
        1,
      );
      await form.verify();
      expect(form.operationId, id);
      expect(tablet.declarations, 1);
    },
  );
  test(
    'D PIN lock during original transaction prevents durable commit',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      tablet.transactionHook = () async {
        entered.complete();
        await release.future;
      };
      final flight = submit();
      await entered.future;
      final id = form.operationId;
      tablet.lock();
      release.complete();
      await flight;
      expect(form.operationId, id);
      expect(await expenses(), isEmpty);
      expect(form.suspended, isTrue);
      expect(tablet.declarations, 1);
      expect(
        (await db
                .customSelect(
                  'SELECT next_sequence FROM local_sequence_counter WHERE singleton=1',
                )
                .getSingle())
            .read<int>('next_sequence'),
        1,
      );
    },
  );
  test(
    'D pending expense never mutates confirmed cache or confirmed animal totals',
    () async {
      final before =
          (await db
                  .customSelect(
                    'SELECT * FROM confirmed_cache ORDER BY collection,entity_id',
                  )
                  .get())
              .map((r) => r.data)
              .toList();
      final lotsBefore = await db.projectedPage('lots');
      await submit();
      expect(
        (await db
                .customSelect(
                  'SELECT * FROM confirmed_cache ORDER BY collection,entity_id',
                )
                .get())
            .map((r) => r.data)
            .toList(),
        before,
      );
      expect(await db.projectedPage('lots'), lotsBefore);
      expect(requests, 0);
      expect(form.result.state, ExpenseDurableState.durable);
    },
  );
  test(
    'D original profile round trip permits explicit reading without reactivating the intention',
    () async {
      await submit();
      final id = form.operationId;
      final original = canonicalDeclaration(
        (await expenses()).single.declaration,
      );
      await replaceGrant(grant);
      form.checkContext();
      await form.verify();
      expect(form.suspended, isTrue);
      expect(form.editable, isFalse);
      expect(form.result.state, ExpenseDurableState.durable);
      expect(form.resultVisible, isTrue);
      expect(form.operationId, id);
      expect(tablet.declarations, 1);
      expect(
        canonicalDeclaration((await expenses()).single.declaration),
        original,
      );
    },
  );
}

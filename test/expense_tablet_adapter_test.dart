import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:app_elevage/offline/expense_tablet_adapter.dart';
import 'package:app_elevage/offline/expense_intention.dart';
import 'package:app_elevage/offline/expense_intention_session.dart';
import 'package:app_elevage/offline/expense_business_date.dart';
import 'package:app_elevage/offline/expense_preparation.dart';
import 'package:app_elevage/offline/expense_consistent_catalog.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/farm_cache.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;

class ReadOnlyMemoryRegister implements FarmCache, OutboxStore {
  final rows = <OutboxEntry>[];
  final categories = <Map<String, dynamic>>[];
  int writes = 0;
  Future<void> Function(int offset)? beforeCategoryPage, beforeLedgerPage;
  @override
  Future<List<OutboxEntry>> listOutbox({
    int? authorId,
    int limit = 50,
    int offset = 0,
  }) async {
    await beforeLedgerPage?.call(offset);
    return rows
        .where((r) => authorId == null || r.authorId == authorId)
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> cachedPage(
    String collection, {
    int offset = 0,
    int limit = 50,
    int? taskUserId,
  }) async {
    if (collection != 'expense_categories') {
      throw StateError('Unexpected collection');
    }
    await beforeCategoryPage?.call(offset);
    return categories
        .skip(offset)
        .take(limit)
        .map((d) => <String, dynamic>{'data': d})
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    writes++;
    throw StateError('No write allowed: ${invocation.memberName}');
  }
}

class ContractSimulation implements ExpenseDeclarationSimulation {
  final Future<void> Function(ExpenseDeclarationParameters) run;
  ContractSimulation(this.run);
  @override
  Future<void> inspectContract(ExpenseDeclarationParameters parameters) =>
      run(parameters);
}

void main() {
  tzdata.initializeTimeZones();
  late VerifiedOfflineGrant grant;
  late Map<String, String> pinSeed;
  late TestSecretStore secrets;
  late LocalOperatorSessions sessions;
  late FoundationApi api;
  late TabletController tablet;
  late ReadOnlyMemoryRegister register;
  late ExpenseTabletSessionObserver observer;
  late DateTime now;
  var requests = 0;
  Map<String, dynamic> profile(VerifiedOfflineGrant g) => {
    'user_id': g.userId,
    'membership_id': g.claims['membership_id'],
    'rights_version': g.rightsVersion,
    'write_generation': g.generation,
    'display_name': 'Opérateur',
  };
  OnlineOperatorIdentity httpIdentity({
    String role = 'OPERATEUR',
    int user = 2,
    int farm = 1,
  }) => OnlineOperatorIdentity(
    userId: user,
    farmId: farm,
    role: role,
    capabilities: {
      'membership': {'id': 2, 'version': 1, 'is_active': true},
    },
    access: 'synthetic',
    refresh: 'synthetic',
  );

  setUpAll(() async {
    grant = await fineGrant(codes: ['finance.read', 'expenses.create']);
    final seed = TestSecretStore();
    final explicit = LocalOperatorSessions(
      store: seed,
      namespace: 'c1-test',
      farmId: 1,
      deviceId: 7,
      generation: 1,
      clock: () => syntheticNow,
    );
    await explicit.enroll(grant, '123456'); // explicit synthetic fixture only
    pinSeed = Map.from(seed.values);
  });
  setUp(() async {
    now = syntheticNow;
    requests = 0;
    secrets = TestSecretStore()..values.addAll(pinSeed);
    sessions = LocalOperatorSessions(
      store: secrets,
      namespace: 'c1-test',
      farmId: 1,
      deviceId: 7,
      generation: 1,
      clock: () => now,
    );
    expect(await sessions.unlock(grant, '123456'), isTrue);
    register = ReadOnlyMemoryRegister()
      ..categories.add({'id': 4, 'nom': 'Transport', 'exploitation': 1});
    api = FoundationApi(
      baseUrl: 'https://c1.invalid/api',
      deviceIdentity: TestIdentity(),
      secrets: secrets,
      clock: () => now,
      client: MockClient((_) async {
        requests++;
        throw StateError('No HTTP allowed');
      }),
    );
    tablet =
        TabletController(
            api: api,
            secrets: secrets,
            automaticSyncEnabled: false,
            clock: () => now,
          )
          ..farmId = 1
          ..deviceId = 7
          ..generation = 1
          ..operators = sessions
          ..cache = register
          ..profiles = [profile(grant)]
          ..selectedName = 'Opérateur';
    observer = ExpenseTabletSessionObserver(tablet);
  });
  tearDown(() {
    expect(register.writes, 0);
    expect(requests, 0);
    tablet.dispose();
    api.close();
  });

  Future<PreparedExpense> prepared({bool local = false}) async {
    final scope = ExpenseSelectionContext(farmId: 1, authorId: 2);
    final catalog = (await ExpenseTabletReadBridge(
      observer,
      observer.capture(),
    ).categories()).catalog;
    const parent = 'aaaaaaaa-1234-1234-1234-123456789abc';
    const child = 'bbbbbbbb-1234-1234-1234-123456789abc';
    final lot = ExpenseLotSelection.fromProjectedRow(
      local
          ? {
              'data': {'id': child, 'nom': 'Lot local'},
              'local_uuid': child,
              'dependency': parent,
              'state': 'UNREVIEWED',
            }
          : {
              'data': {'id': 17, 'nom': 'Lot confirmé'},
              'state': 'CONFIRMED_CACHE',
            },
      origin: scope,
      parentDeclaration: local
          ? {
              'client_operation_id': parent,
              'local_entity_id': child,
              'author_user_id': 2,
              'exploitation_id': 1,
              'entity_type': 'ACHAT',
              'operation_type': 'CREATE',
              'payload': {'quantite': 10},
            }
          : null,
    );
    return ExpensePreparation.compose(
      currentContext: scope,
      lot: lot,
      categories: catalog,
      categoryId: 4,
      amount: '1234,5',
      day: ExpenseBusinessDay(2026, 10, 12),
      dates: ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
      nowUtc: now,
    );
  }

  ExpenseIntentionCoordinator coordinator() => ExpenseIntentionCoordinator(
    observe: observer.observe,
    utcClock: () => now,
    uuid: () => '00000000-0000-4000-8000-000000000001',
  );
  OutboxEntry durable(
    ExpenseDeclarationParameters p, {
    bool confirmed = false,
  }) => OutboxEntry(
    declaration: {
      'client_operation_id': p.operationId,
      'local_entity_id': p.localEntityId,
      'author_user_id': p.origin.authorId,
      'author_membership_id': p.origin.membershipId,
      'exploitation_id': p.origin.farmId,
      'device_id': p.origin.deviceId,
      'device_generation': p.origin.generation,
      'offline_authorization_id': p.origin.grantId,
      'entity_type': p.entityType,
      'operation_type': p.operationType,
      'payload': p.payload,
      'dependencies': p.dependencies,
      'business_occurred_at': p.businessOccurredAt.toIso8601String(),
      'local_sequence': 1,
      'local_recorded_at': now.toIso8601String(),
    },
    transportStatus: confirmed ? 'SERVER_RECEIVED' : 'LOCAL_PENDING',
    businessStatus: confirmed ? 'CONFIRMED' : 'UNREVIEWED',
    attemptCount: 0,
    lastError: '',
    receivedAt: confirmed ? now : null,
    appliedAt: confirmed ? now : null,
    serverEntityId: confirmed ? '44' : '',
  );

  test('real PIN session and persisted profile observed without HTTP', () {
    final captured = observer.capture();
    expect(captured.authorId, 2);
    expect(captured.membershipId, 2);
    expect(captured.grantId, grant.claims['jti']);
    expect(observer.observe().epoch, captured.epoch);
  });
  test(
    'matching HTTP identity accepted but its permissions never authorize',
    () async {
      api.personal = httpIdentity();
      expect(observer.capture().authorId, 2);
      final denied = await fineGrant(codes: ['finance.read']);
      expect(await sessions.unlock(denied, '123456'), isTrue);
      expect(() => observer.capture(), throwsA(isA<ExpenseSessionException>()));
    },
  );
  for (final kind in [
    'owner',
    'foreignUser',
    'foreignFarm',
    'membership',
    'version',
    'inactive',
  ]) {
    test('conflicting HTTP context $kind refused', () {
      api.personal = httpIdentity(
        role: kind == 'owner' ? 'OWNER' : 'OPERATEUR',
        user: kind == 'foreignUser' ? 3 : 2,
        farm: kind == 'foreignFarm' ? 2 : 1,
      );
      final member = api.personal!.capabilities['membership'] as Map;
      if (kind == 'membership') member['id'] = 99;
      if (kind == 'version') member['version'] = 99;
      if (kind == 'inactive') member['is_active'] = false;
      expect(() => observer.capture(), throwsA(isA<ExpenseSessionException>()));
    });
  }
  test('legacy V1 PIN remains readable but cannot authorize new expense writes', () async {
    final legacy = await fineGrant(legacy: true);
    expect(await sessions.unlock(legacy, '123456'), isTrue);
    // The existing production policy already requires signed individual V2
    // rights for every new write. Historical V1 originals remain transportable.
    expect(legacy.permitsOperation('DEPENSE', 'CREATE', now), isFalse);
    expect(() => observer.capture(), throwsA(isA<ExpenseSessionException>()));
  });
  for (final kind in [
    'missingProfile',
    'duplicateProfile',
    'membership',
    'rights',
    'name',
    'generation',
    'cache',
  ]) {
    test('incomplete/ambiguous prepared profile $kind refused', () {
      switch (kind) {
        case 'missingProfile':
          tablet.profiles = [];
        case 'duplicateProfile':
          tablet.profiles.add(profile(grant));
        case 'membership':
          tablet.profiles.single['membership_id'] = 99;
        case 'rights':
          tablet.profiles.single['rights_version'] = 99;
        case 'name':
          tablet.selectedName = 'Other';
        case 'generation':
          tablet.profiles.single['write_generation'] = 99;
        case 'cache':
          tablet.cache = null;
      }
      expect(() => observer.capture(), throwsA(isA<ExpenseSessionException>()));
    });
  }
  test('actual lock and expiry transition increment observed epoch', () {
    final first = observer.observe();
    final epoch = sessions.sessionEpoch;
    sessions.lock();
    expect(sessions.sessionEpoch, epoch + 1);
    expect(observer.observe().epoch, greaterThan(first.epoch));
    expect(() => observer.capture(), throwsA(isA<ExpenseSessionException>()));
  });
  test('grant expiry uses existing session getter and locks PIN session', () {
    final epoch = observer.observe().epoch;
    now = grant.expiresAt;
    expect(observer.observe().personalSession, isNull);
    expect(observer.observe().epoch, greaterThan(epoch));
    expect(() => observer.capture(), throwsA(isA<ExpenseSessionException>()));
  });
  test('actual PIN change observed; no automatic reopening', () async {
    final before = observer.observe().epoch;
    expect(await sessions.changePin(grant, '123456', '654321'), isTrue);
    expect(observer.observe().epoch, greaterThan(before));
    expect(observer.observe().personalSession, isNull);
  });
  test(
    'unobserved lock/unlock round trip caught by real epoch counters',
    () async {
      final old = observer.capture();
      sessions.lock();
      expect(await sessions.unlock(grant, '123456'), isTrue);
      expect(
        () => old.checkIdentity(observer.observe()),
        throwsA(isA<ExpenseSessionException>()),
      );
    },
  );
  test('HTTP epoch round trip detected even with same object', () {
    api.personal = httpIdentity();
    final old = observer.capture();
    api.invalidatePendingPersonalWork();
    api.invalidatePendingPersonalWork();
    expect(
      () => old.checkIdentity(observer.observe()),
      throwsA(isA<ExpenseSessionException>()),
    );
  });
  for (final kind in [
    'farm',
    'device',
    'generation',
    'revoked',
    'recovering',
  ]) {
    test('tablet transition $kind rejected', () {
      final old = observer.capture();
      switch (kind) {
        case 'farm':
          tablet.farmId = 2;
        case 'device':
          tablet.deviceId = 8;
        case 'generation':
          tablet.generation = 2;
        case 'revoked':
          tablet.knownDeviceRevoked = true;
        case 'recovering':
          tablet.recovering = true;
      }
      expect(
        () => old.checkIdentity(observer.observe()),
        throwsA(isA<ExpenseSessionException>()),
      );
    });
  }
  test('actual cache pagination >200 remains unverified and stale', () async {
    register.categories.clear();
    register.categories.addAll([
      for (var i = 1; i <= 451; i++)
        {'id': i, 'nom': 'Cat $i', 'exploitation': 1},
    ]);
    final result = await ExpenseTabletReadBridge(
      observer,
      observer.capture(),
    ).categories(freshness: ExpenseCacheFreshness.stale);
    expect(result.catalog.categories, hasLength(451));
    expect(result.catalog.select(451).id, 451);
    expect(result.consistency, ExpenseCatalogConsistency.unverified);
    expect(result.catalog.needsFreshnessNotice, isTrue);
  });
  test(
    'observable replacement producing duplicate category is refused',
    () async {
      register.categories.addAll([
        for (var i = 5; i <= 54; i++) {'id': i, 'nom': 'Cat $i'},
      ]);
      register.beforeCategoryPage = (offset) async {
        if (offset == 50) {
          register.categories[50] = {'id': 4, 'nom': 'Duplicate'};
        }
      };
      await expectLater(
        ExpenseTabletReadBridge(observer, observer.capture()).categories(),
        throwsA(isA<ExpensePreparationException>()),
      );
    },
  );
  test(
    'undetectable valid replacement stays unverified, never claimed coherent',
    () async {
      register.beforeCategoryPage = (_) async {
        register.categories.single['nom'] = 'Replacement';
      };
      final result = await ExpenseTabletReadBridge(
        observer,
        observer.capture(),
      ).categories();
      expect(result.consistency, ExpenseCatalogConsistency.unverified);
      expect(result.catalog.freshness, ExpenseCacheFreshness.unknown);
    },
  );
  test(
    'typed parameters preserve B1/B2 UUID/date/dependencies without writing',
    () async {
      final c = coordinator();
      final expense = await prepared(local: true);
      final intention = c.begin(expense);
      final p = ExpenseDeclarationParameters.reserve(c);
      expect(p.operationId, intention.operationId);
      expect(p.localEntityId, intention.operationId);
      expect(p.payload, same(expense.payload));
      expect(p.businessOccurredAt, expense.businessOccurredAt);
      expect(p.dependencies, same(expense.dependencies));
      expect(p.entityType, 'DEPENSE');
      expect(
        () => ExpenseDeclarationParameters.reserve(c),
        throwsA(isA<ExpenseIntentionException>()),
      );
      expect(register.rows, isEmpty);
      c.releaseUnsubmittedValidation();
    },
  );
  test(
    'simulated commit then error resolved by trusted register reader, same UUID',
    () async {
      final c = coordinator();
      final intention = c.begin(await prepared());
      final p = ExpenseDeclarationParameters.reserve(c);
      final bridge = ExpenseTabletReadBridge(observer, intention.context);
      await expectLater(
        simulateExpenseBoundary(
          coordinator: c,
          parameters: p,
          observer: observer,
          simulation: ContractSimulation((parameters) async {
            register.rows.add(
              durable(parameters),
            ); // fixture memory, not enqueue
            throw StateError('accessory after simulated commit');
          }),
        ),
        throwsStateError,
      );
      expect(intention.result.state, ExpenseDurableState.uncertain);
      expect(c.begin(intention.prepared), same(intention));
      expect(
        (await c.inspect(bridge.ledgerPage)).state,
        ExpenseDurableState.durable,
      );
      expect(c.pendingOperationId, p.operationId);
      expect(register.writes, 0);
    },
  );
  test(
    'empty trusted register stays uncertain; no replacement expense',
    () async {
      final c = coordinator();
      final intention = c.begin(await prepared());
      c.markUncertain();
      final result = await c.inspect(
        ExpenseTabletReadBridge(observer, intention.context).ledgerPage,
      );
      expect(result.state, ExpenseDurableState.uncertain);
      expect(
        () => c.closeResolved(),
        throwsA(isA<ExpenseIntentionException>()),
      );
    },
  );
  test('late trusted register response rejected after tablet lock', () async {
    final c = coordinator();
    final intention = c.begin(await prepared());
    final wait = Completer<void>();
    register.beforeLedgerPage = (_) => wait.future;
    final pending = c.inspect(
      ExpenseTabletReadBridge(observer, intention.context).ledgerPage,
    );
    tablet.lock();
    final assertion = expectLater(
      pending,
      throwsA(isA<ExpenseSessionException>()),
    );
    wait.complete();
    await assertion;
    expect(intention.suspended, isTrue);
  });
  test(
    'explicit original-profile reopening permits read-only recovery, no reassignment',
    () async {
      final c = coordinator();
      final intention = c.begin(await prepared());
      final p = ExpenseDeclarationParameters.reserve(c);
      c.markUncertain();
      register.rows.add(durable(p, confirmed: true));
      tablet.lock();
      expect(() => c.current, throwsA(isA<ExpenseSessionException>()));
      expect(await sessions.unlock(grant, '123456'), isTrue);
      tablet.selectedName = 'Opérateur';
      final bridge = ExpenseTabletReadBridge(observer, observer.capture());
      final result = await bridge.recoverOriginal(intention, c);
      expect(result.state, ExpenseDurableState.confirmed);
      expect(intention.suspended, isTrue);
      expect(intention.context.grantId, p.origin.grantId);
      expect(c.pendingOperationId, p.operationId);
      expect(register.writes, 0);
    },
  );
  test(
    'explicit recovery cannot rebind an original intention to a renewed grant',
    () async {
      final c = coordinator();
      final intention = c.begin(await prepared());
      c.markUncertain();
      final renewed = await fineGrant(
        codes: ['finance.read', 'expenses.create'],
        grantId: 'aaaaaaaa-1234-1234-1234-123456789abc',
      );
      expect(await sessions.unlock(renewed, '123456'), isTrue);
      final bridge = ExpenseTabletReadBridge(observer, observer.capture());
      await expectLater(
        bridge.recoverOriginal(intention, c),
        throwsA(isA<ExpenseSessionException>()),
      );
    },
  );
  test(
    'late category page rejected across real PIN lock/unlock epoch',
    () async {
      final wait = Completer<void>();
      register.beforeCategoryPage = (_) => wait.future;
      final pending = ExpenseTabletReadBridge(
        observer,
        observer.capture(),
      ).categories();
      await Future<void>.delayed(Duration.zero);
      sessions.lock();
      expect(await sessions.unlock(grant, '123456'), isTrue);
      final assertion = expectLater(
        pending,
        throwsA(isA<ExpenseSessionException>()),
      );
      wait.complete();
      await assertion;
    },
  );
}

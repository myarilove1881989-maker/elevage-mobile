import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:app_elevage/offline/expense_business_date.dart';
import 'package:app_elevage/offline/expense_preparation.dart';
import 'package:app_elevage/offline/expense_intention_session.dart';
import 'package:app_elevage/offline/expense_intention.dart';
import 'package:app_elevage/offline/expense_consistent_catalog.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;

void main() {
  tzdata.initializeTimeZones();
  late VerifiedOfflineGrant grant;
  late LocalOperatorSession personal;
  late Object profile, cache;
  late ExpenseSessionObservation observation;
  late ExpenseIntentionCoordinator coordinator;
  late PreparedExpense prepared;
  var epoch = 1;
  var generated = 0;
  var now = syntheticNow;
  const parentId = 'aaaaaaaa-1234-1234-1234-123456789abc';
  const localId = 'bbbbbbbb-1234-1234-1234-123456789abc';

  ExpenseSessionObservation observe({
    LocalOperatorSession? session,
    Object? profileIdentity,
    Object? cacheIdentity,
    int? farm,
    int? generation,
    int? device,
    int? sessionEpoch,
    bool prepared = true,
    bool unlocked = true,
    bool revoked = false,
    bool recovering = false,
  }) => ExpenseSessionObservation(
    personalSession: session ?? personal,
    preparedProfileIdentity: profileIdentity ?? profile,
    cacheIdentity: cacheIdentity ?? cache,
    farmId: farm ?? 1,
    deviceId: device ?? 7,
    generation: generation ?? 1,
    epoch: sessionEpoch ?? epoch,
    explicitlyPrepared: prepared,
    pinUnlocked: unlocked,
    revoked: revoked,
    recovering: recovering,
  );

  Future<PreparedExpense> build({
    String amount = '1',
    bool local = false,
    ExpenseCacheFreshness freshness = ExpenseCacheFreshness.current,
  }) async {
    final origin = ExpenseSelectionContext(farmId: 1, authorId: 2);
    final catalog = await ExpenseCategoryCatalog.readAll(
      origin: origin,
      currentContext: () => origin,
      freshness: freshness,
      readPage: (_, {required offset, required limit}) async => offset == 0
          ? [
              {
                'data': {'id': 4, 'nom': 'Transport', 'exploitation': 1},
              },
            ]
          : [],
    );
    final lot = ExpenseLotSelection.fromProjectedRow(
      local
          ? {
              'data': {'id': localId, 'nom': 'Lot achat'},
              'local_uuid': localId,
              'dependency': parentId,
              'state': 'UNREVIEWED',
            }
          : {
              'data': {'id': 17, 'nom': 'Lot confirmé', 'exploitation': 1},
              'state': 'CONFIRMED_CACHE',
            },
      origin: origin,
      parentDeclaration: local
          ? {
              'client_operation_id': parentId,
              'local_entity_id': localId,
              'entity_type': 'ACHAT',
              'operation_type': 'CREATE',
              'exploitation_id': 1,
              'author_user_id': 2,
              'payload': {'quantite': 10},
            }
          : null,
    );
    return ExpensePreparation.compose(
      currentContext: origin,
      lot: lot,
      categories: catalog,
      categoryId: 4,
      amount: amount,
      note: 'Transport',
      day: ExpenseBusinessDay(2026, 10, 12),
      dates: ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
      nowUtc: syntheticNow,
    );
  }

  OutboxEntry entry(
    ExpenseIntention intention, {
    Map<String, dynamic>? change,
    String business = 'UNREVIEWED',
    bool receipt = false,
    String? uuid,
  }) => OutboxEntry(
    declaration: {
      'client_operation_id': uuid ?? intention.operationId,
      'author_user_id': 2,
      'author_membership_id': 2,
      'exploitation_id': 1,
      'device_id': 7,
      'device_generation': 1,
      'offline_authorization_id': grant.claims['jti'],
      'entity_type': 'DEPENSE',
      'operation_type': 'CREATE',
      'local_entity_id': uuid ?? intention.operationId,
      'payload': intention.prepared.payload,
      'dependencies': intention.prepared.dependencies,
      'business_occurred_at': intention.prepared.businessOccurredAt
          .toIso8601String(),
      'local_sequence': 1,
      'local_recorded_at': syntheticNow.toIso8601String(),
      ...?change,
    },
    transportStatus: receipt ? 'SERVER_RECEIVED' : 'LOCAL_PENDING',
    businessStatus: business,
    attemptCount: 0,
    lastError: '',
    receivedAt: receipt ? syntheticNow : null,
    appliedAt: receipt ? syntheticNow : null,
    serverEntityId: receipt ? '44' : '',
  );
  ExpenseLedgerPageReader single(OutboxEntry row) =>
      ({required authorId, required offset, required limit}) async =>
          offset == 0 ? [row] : [];
  Matcher sessionFailure(ExpenseSessionFailure code) =>
      isA<ExpenseSessionException>().having((e) => e.code, 'code', code);
  Matcher intentionFailure(ExpenseIntentionFailure code) =>
      isA<ExpenseIntentionException>().having((e) => e.code, 'code', code);

  setUp(() async {
    grant = await fineGrant(codes: ['finance.read', 'expenses.create']);
    personal = LocalOperatorSession(grant: grant, openedAt: syntheticNow);
    profile = Object();
    cache = Object();
    epoch = 1;
    generated = 0;
    now = syntheticNow;
    observation = observe();
    prepared = await build();
    coordinator = ExpenseIntentionCoordinator(
      observe: () => observation,
      utcClock: () => now,
      uuid: () =>
          '00000000-0000-4000-8000-${(++generated).toString().padLeft(12, '0')}',
    );
  });

  test('same logical intention and retry keep one UUID, no sequence', () {
    final intention = coordinator.begin(prepared);
    expect(intention.result.state, ExpenseDurableState.notRecorded);
    expect(coordinator.begin(prepared), same(intention));
    expect(coordinator.validateForFutureDeclaration(), same(intention));
    coordinator.markUncertain();
    expect(coordinator.begin(prepared), same(intention));
    expect(generated, 1);
    expect(
      () => coordinator.validateForFutureDeclaration(),
      throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
    );
    expect(
      () => coordinator.closeResolved(),
      throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
    );
  });
  test('new distinct expense only after explicit resolved closure', () async {
    final first = coordinator.begin(prepared);
    await coordinator.inspect(single(entry(first)));
    coordinator.closeResolved();
    final next = coordinator.begin(await build(amount: '2'));
    expect(next.operationId, isNot(first.operationId));
    expect(generated, 2);
  });
  test('modified payload cannot reuse an attributed UUID', () async {
    final first = coordinator.begin(prepared);
    expect(coordinator.begin(prepared), same(first));
    final changed = await build(amount: '2');
    expect(
      () => coordinator.begin(changed),
      throwsA(intentionFailure(ExpenseIntentionFailure.payloadChanged)),
    );
    expect(coordinator.current, same(first));
    expect(generated, 1);
  });
  test('UUID generator cannot recycle IDs after explicit closure', () {
    final fixed = ExpenseIntentionCoordinator(
      observe: () => observation,
      utcClock: () => now,
      uuid: () => '00000000-0000-4000-8000-000000000001',
    );
    fixed.begin(prepared);
    fixed.closeResolved();
    expect(
      () => fixed.begin(prepared),
      throwsA(intentionFailure(ExpenseIntentionFailure.invalidUuid)),
    );
  });
  test(
    'validation reservation prevents simultaneous validation until explicit release',
    () {
      final intention = coordinator.begin(prepared);
      expect(coordinator.validateForFutureDeclaration(), same(intention));
      expect(intention.busy, isTrue);
      expect(
        () => coordinator.validateForFutureDeclaration(),
        throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
      );
      expect(
        () => coordinator.closeResolved(),
        throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
      );
      coordinator.releaseUnsubmittedValidation();
      expect(intention.result.state, ExpenseDurableState.notRecorded);
      expect(coordinator.validateForFutureDeclaration(), same(intention));
      coordinator.markUncertain();
      expect(intention.busy, isFalse);
      expect(
        () => coordinator.releaseUnsubmittedValidation(),
        throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
      );
      expect(
        () => coordinator.closeResolved(),
        throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
      );
      expect(generated, 1);
    },
  );
  test('double click coalesces lookup before first await', () async {
    final intention = coordinator.begin(prepared);
    final barrier = Completer<List<OutboxEntry>>();
    var reads = 0;
    Future<List<OutboxEntry>> read({
      required int authorId,
      required int offset,
      required int limit,
    }) {
      reads++;
      return barrier.future;
    }

    final first = coordinator.inspect(read);
    final second = coordinator.inspect(read);
    expect(second, same(first));
    expect(reads, 1);
    expect(generated, 1);
    expect(
      () => coordinator.closeResolved(),
      throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
    );
    expect(
      () => coordinator.validateForFutureDeclaration(),
      throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
    );
    barrier.complete([entry(intention)]);
    expect((await first).state, ExpenseDurableState.durable);
    await second;
    expect(intention.busy, isFalse);
  });
  test(
    'exception before simulated commit remains uncertain without replacement UUID',
    () async {
      final intention = coordinator.begin(prepared);
      final result = await coordinator.inspect(
        ({required authorId, required offset, required limit}) async =>
            throw StateError('before commit'),
      );
      expect(result.state, ExpenseDurableState.uncertain);
      expect(result.issue, 'readFailed');
      expect(intention.busy, isFalse);
      expect(coordinator.begin(prepared), same(intention));
      expect(generated, 1);
    },
  );
  test(
    'accessory exception after simulated commit recovers original durable declaration',
    () async {
      final intention = coordinator.begin(prepared);
      final simulatedLedger = <OutboxEntry>[];
      await coordinator.inspect(({
        required authorId,
        required offset,
        required limit,
      }) async {
        simulatedLedger.add(entry(intention));
        throw StateError('summary after commit');
      });
      expect(intention.result.state, ExpenseDurableState.uncertain);
      final result = await coordinator.inspect(
        ({required authorId, required offset, required limit}) async =>
            offset == 0 ? simulatedLedger : [],
      );
      expect(result.state, ExpenseDurableState.durable);
      expect(result.entry!.operationId, intention.operationId);
      expect(generated, 1);
    },
  );
  test('partial absence and empty end remain uncertain', () async {
    coordinator.begin(prepared);
    final result = await coordinator.inspect(
      ({required authorId, required offset, required limit}) async => [],
    );
    expect(result.state, ExpenseDurableState.uncertain);
    expect(result.issue, 'absenceNotProven');
    expect(
      () => coordinator.closeResolved(),
      throwsA(intentionFailure(ExpenseIntentionFailure.unresolved)),
    );
  });
  test(
    'search after 200 entries and short pages uses original author and UUID',
    () async {
      final intention = coordinator.begin(prepared);
      final offsets = <int>[];
      final others = [
        for (var i = 0; i < 205; i++)
          entry(
            intention,
            uuid: '11111111-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          ),
      ];
      others.add(entry(intention));
      final result = await coordinator.inspect(({
        required authorId,
        required offset,
        required limit,
      }) async {
        expect(authorId, 2);
        offsets.add(offset);
        return others.skip(offset).take(offset == 0 ? 1 : limit).toList();
      });
      expect(result.state, ExpenseDurableState.durable);
      expect(offsets.last, 201);
    },
  );
  for (final status in [
    'UNREVIEWED',
    'WAITING_DEPENDENCY',
    'NEEDS_RECONCILIATION',
    'NOT_APPLIED',
    'SUPERSEDED',
  ]) {
    test('durable business state $status remains explicit', () async {
      final intention = coordinator.begin(prepared);
      final result = await coordinator.inspect(
        single(entry(intention, business: status)),
      );
      expect(
        result.state,
        status == 'NEEDS_RECONCILIATION'
            ? ExpenseDurableState.reconciliation
            : {'NOT_APPLIED', 'SUPERSEDED'}.contains(status)
            ? ExpenseDurableState.notApplied
            : ExpenseDurableState.durable,
      );
    });
  }
  test('server confirmation requires corresponding receipt metadata', () async {
    final intention = coordinator.begin(prepared);
    final forged = await coordinator.inspect(
      single(entry(intention, business: 'CONFIRMED')),
    );
    expect(forged.state, ExpenseDurableState.uncertain);
    expect(forged.issue, 'integrityMismatch');
    final confirmed = await coordinator.inspect(
      single(entry(intention, business: 'CONFIRMED', receipt: true)),
    );
    expect(confirmed.state, ExpenseDurableState.confirmed);
    expect(confirmed.entry!.receivedAt, isNotNull);
    expect(confirmed.entry!.appliedAt, isNotNull);
    final later = await coordinator.inspect(
      ({required authorId, required offset, required limit}) async => [],
    );
    expect(later.state, ExpenseDurableState.confirmed);
  });
  for (final change in <String, dynamic>{
    'author_user_id': 3,
    'author_membership_id': 3,
    'exploitation_id': 2,
    'device_id': 8,
    'device_generation': 2,
    'offline_authorization_id': 'other',
    'entity_type': 'CLIENT',
    'operation_type': 'UPDATE',
    'local_entity_id': localId,
    'payload': {'montant': '2.00'},
    'dependencies': [parentId],
    'business_occurred_at': '2026-10-11T10:00:00Z',
    'local_sequence': 0,
    'local_recorded_at': 'bad',
    'rights_version': 99,
  }.entries) {
    test('original declaration integrity ${change.key}', () async {
      final intention = coordinator.begin(prepared);
      final result = await coordinator.inspect(
        single(entry(intention, change: {change.key: change.value})),
      );
      expect(result.state, ExpenseDurableState.uncertain);
      expect(result.issue, 'integrityMismatch');
      expect(generated, 1);
    });
  }
  test('repeated pages are uncertain instead of looping', () async {
    final intention = coordinator.begin(prepared);
    final different = entry(intention, uuid: parentId);
    final result = await coordinator.inspect(
      ({required authorId, required offset, required limit}) async => [
        different,
      ],
    );
    expect(result.state, ExpenseDurableState.uncertain);
    expect(result.issue, 'integrityMismatch');
  });
  for (final transition in [
    'epoch',
    'profile',
    'cache',
    'farm',
    'device',
    'generation',
    'lock',
    'revoked',
    'recovering',
  ]) {
    test(
      'late response during $transition suspends without reassignment',
      () async {
        final intention = coordinator.begin(prepared);
        final barrier = Completer<List<OutboxEntry>>();
        final pending = coordinator.inspect(
          ({required authorId, required offset, required limit}) =>
              barrier.future,
        );
        switch (transition) {
          case 'epoch':
            observation = observe(sessionEpoch: 2);
          case 'profile':
            observation = observe(profileIdentity: Object());
          case 'cache':
            observation = observe(cacheIdentity: Object());
          case 'farm':
            observation = observe(farm: 2);
          case 'device':
            observation = observe(device: 8);
          case 'generation':
            observation = observe(generation: 2);
          case 'lock':
            observation = observe(unlocked: false);
          case 'revoked':
            observation = observe(revoked: true);
          case 'recovering':
            observation = observe(recovering: true);
        }
        final assertion = expectLater(
          pending,
          throwsA(isA<ExpenseSessionException>()),
        );
        barrier.complete([entry(intention)]);
        await assertion;
        expect(intention.suspended, isTrue);
        expect(intention.result.entry, isNull);
        expect(coordinator.pendingOperationId, intention.operationId);
        expect(generated, 1);
        expect(
          () => coordinator.current,
          throwsA(intentionFailure(ExpenseIntentionFailure.suspended)),
        );
      },
    );
  }
  test('profile round trip cannot bypass monotonic epoch', () async {
    final intention = coordinator.begin(prepared);
    final barrier = Completer<List<OutboxEntry>>();
    final pending = coordinator.inspect(
      ({required authorId, required offset, required limit}) => barrier.future,
    );
    observation = observe(profileIdentity: Object(), sessionEpoch: 2);
    observation = observe(
      sessionEpoch: 3,
    ); // same original object, but new epoch
    final assertion = expectLater(
      pending,
      throwsA(sessionFailure(ExpenseSessionFailure.contextChanged)),
    );
    barrier.complete([entry(intention)]);
    await assertion;
    observation = observe();
    expect(
      () => coordinator.begin(prepared),
      throwsA(intentionFailure(ExpenseIntentionFailure.suspended)),
    );
    expect(generated, 1);
  });
  test(
    'author/grant changes including return to same user suspend intention',
    () async {
      final intention = coordinator.begin(prepared);
      final next = await fineGrant(
        codes: ['finance.read', 'expenses.create'],
        grantId: parentId,
      );
      observation = observe(
        session: LocalOperatorSession(grant: next, openedAt: syntheticNow),
        sessionEpoch: 2,
      );
      expect(
        () => coordinator.validateForFutureDeclaration(),
        throwsA(sessionFailure(ExpenseSessionFailure.contextChanged)),
      );
      expect(intention.context.grantId, grant.claims['jti']);
      expect(coordinator.pendingOperationId, intention.operationId);
    },
  );
  test(
    'switch to another prepared author never reattributes the old intent',
    () async {
      final intention = coordinator.begin(prepared);
      final other = await fineGrant(
        user: 3,
        expectedUser: 3,
        codes: ['finance.read', 'expenses.create'],
      );
      observation = observe(
        session: LocalOperatorSession(grant: other, openedAt: syntheticNow),
        sessionEpoch: 2,
      );
      expect(
        () => coordinator.current,
        throwsA(sessionFailure(ExpenseSessionFailure.contextChanged)),
      );
      expect(intention.context.authorId, 2);
      expect(coordinator.pendingOperationId, intention.operationId);
      expect(generated, 1);
    },
  );
  test('session interruption during a later outbox page is rejected', () async {
    final intention = coordinator.begin(prepared);
    final barrier = Completer<List<OutboxEntry>>();
    final pending = coordinator.inspect(({
      required authorId,
      required offset,
      required limit,
    }) async {
      if (offset == 0) return [entry(intention, uuid: parentId)];
      return await barrier.future;
    });
    await Future<void>.delayed(Duration.zero);
    observation = observe(sessionEpoch: 2);
    final assertion = expectLater(
      pending,
      throwsA(isA<ExpenseSessionException>()),
    );
    barrier.complete([entry(intention)]);
    await assertion;
    expect(intention.result.entry, isNull);
  });
  test(
    'read exception after session transition is not returned to new profile',
    () async {
      final intention = coordinator.begin(prepared);
      final barrier = Completer<List<OutboxEntry>>();
      final pending = coordinator.inspect(
        ({required authorId, required offset, required limit}) =>
            barrier.future,
      );
      observation = observe(sessionEpoch: 2);
      final assertion = expectLater(
        pending,
        throwsA(sessionFailure(ExpenseSessionFailure.contextChanged)),
      );
      barrier.completeError(StateError('read failed'));
      await assertion;
      expect(intention.suspended, isTrue);
    },
  );
  test(
    'explicit preparation, PIN, permission and V2 required before UUID',
    () async {
      observation = observe(prepared: false);
      expect(
        () => coordinator.begin(prepared),
        throwsA(sessionFailure(ExpenseSessionFailure.notPrepared)),
      );
      observation = observe(unlocked: false);
      expect(
        () => coordinator.begin(prepared),
        throwsA(sessionFailure(ExpenseSessionFailure.pinLocked)),
      );
      final denied = await fineGrant(codes: ['finance.read']);
      personal = LocalOperatorSession(grant: denied, openedAt: syntheticNow);
      observation = observe();
      expect(
        () => coordinator.begin(prepared),
        throwsA(sessionFailure(ExpenseSessionFailure.permissionDenied)),
      );
      final legacy = await fineGrant(legacy: true);
      personal = LocalOperatorSession(grant: legacy, openedAt: syntheticNow);
      observation = observe();
      expect(
        () => coordinator.begin(prepared),
        throwsA(sessionFailure(ExpenseSessionFailure.permissionDenied)),
      );
      expect(generated, 0);
    },
  );
  test(
    'OWNER cannot obtain a fine create grant; legacy is no substitute',
    () async {
      await expectLater(
        fineGrant(role: 'OWNER', codes: ['finance.read', 'expenses.create']),
        throwsStateError,
      );
      final legacyOwner = await fineGrant(role: 'OWNER', legacy: true);
      personal = LocalOperatorSession(
        grant: legacyOwner,
        openedAt: syntheticNow,
      );
      observation = observe();
      expect(
        () => coordinator.begin(prepared),
        throwsA(sessionFailure(ExpenseSessionFailure.permissionDenied)),
      );
      expect(generated, 0);
    },
  );
  test('expired/not-yet-valid grant blocks future validation', () {
    final intention = coordinator.begin(prepared);
    now = grant.expiresAt;
    expect(
      () => coordinator.validateForFutureDeclaration(),
      throwsA(sessionFailure(ExpenseSessionFailure.permissionDenied)),
    );
    expect(intention.suspended, isTrue);
  });
  test('not-yet-valid grant blocks before allocating UUID', () {
    now = syntheticNow.subtract(const Duration(minutes: 1));
    expect(
      () => coordinator.begin(prepared),
      throwsA(sessionFailure(ExpenseSessionFailure.permissionDenied)),
    );
    expect(generated, 0);
  });
  test(
    'read lookup can recover original evidence without new write permission',
    () async {
      final intention = coordinator.begin(prepared);
      now = grant.expiresAt;
      final result = await coordinator.inspect(single(entry(intention)));
      expect(result.state, ExpenseDurableState.durable);
      expect(
        generated,
        1,
      ); // original snapshot still explicitly unlocked in simulation
    },
  );
  test(
    'prepared B2 local dependency and stale notice retained, nothing written',
    () async {
      final local = await build(
        local: true,
        freshness: ExpenseCacheFreshness.stale,
      );
      final intention = coordinator.begin(local);
      coordinator.validateForFutureDeclaration();
      expect(intention.prepared.payload['lot_ref'], {'local_uuid': localId});
      expect(intention.prepared.dependencies, [parentId]);
      expect(
        intention.prepared.categoryCacheFreshness,
        ExpenseCacheFreshness.stale,
      );
      expect(intention.result.state, ExpenseDurableState.notRecorded);
      expect(
        () => intention.prepared.payload['montant'] = '2',
        throwsUnsupportedError,
      );
      // There is no declare/enqueue/write dependency on this coordinator.
    },
  );

  Future<ExpenseCheckedCatalog> readCatalog({
    Future<String?> Function()? version,
    Future<List<Map<String, dynamic>>> Function(int offset)? page,
  }) {
    final captured = ExpenseCapturedSession.capture(observation, syntheticNow);
    return ExpenseConsistentCatalog.read(
      captured: captured,
      observe: () => observation,
      freshness: ExpenseCacheFreshness.stale,
      readVersion: version,
      readPage: (collection, {required offset, required limit}) async {
        expect(collection, 'expense_categories');
        return page != null
            ? await page(offset)
            : offset == 0
            ? [
                {
                  'data': {'id': 4, 'nom': 'Transport', 'exploitation': 1},
                },
              ]
            : [];
      },
    );
  }

  test(
    'existing category API without version stays unverified and stale',
    () async {
      final result = await readCatalog();
      expect(result.consistency, ExpenseCatalogConsistency.unverified);
      expect(result.catalog.freshness, ExpenseCacheFreshness.stale);
      expect(result.catalog.select(4).id, 4);
    },
  );
  test(
    'stable injected revision demonstrates consistency, not freshness',
    () async {
      final result = await readCatalog(version: () async => 'revision:1');
      expect(result.consistency, ExpenseCatalogConsistency.verifiedByVersion);
      expect(result.catalog.needsFreshnessNotice, isTrue);
    },
  );
  test('cache replacement during page is refused', () async {
    var revision = '1';
    await expectLater(
      readCatalog(
        version: () async => revision,
        page: (offset) async {
          revision = '2';
          return [
            {
              'data': {'id': 4, 'nom': 'Transport'},
            },
          ];
        },
      ),
      throwsA(isA<ExpensePreparationException>()),
    );
  });
  test('version disappearing after first page is refused', () async {
    String? revision = '1';
    await expectLater(
      readCatalog(
        version: () async => revision,
        page: (offset) async {
          revision = null;
          return [];
        },
      ),
      throwsA(isA<ExpensePreparationException>()),
    );
  });
  test(
    'category version async boundary checks epoch before accepting answer',
    () async {
      final barrier = Completer<String?>();
      final pending = readCatalog(version: () => barrier.future);
      observation = observe(sessionEpoch: 2);
      final assertion = expectLater(
        pending,
        throwsA(sessionFailure(ExpenseSessionFailure.contextChanged)),
      );
      barrier.complete('1');
      await assertion;
    },
  );
  test('category page async boundary rejects profile round trip', () async {
    final barrier = Completer<List<Map<String, dynamic>>>();
    final pending = readCatalog(page: (_) => barrier.future);
    await Future<void>.delayed(Duration.zero);
    observation = observe(sessionEpoch: 3);
    final assertion = expectLater(
      pending,
      throwsA(sessionFailure(ExpenseSessionFailure.contextChanged)),
    );
    barrier.complete([
      {
        'data': {'id': 4, 'nom': 'Transport'},
      },
    ]);
    await assertion;
  });
  for (var boundary = 1; boundary <= 6; boundary++) {
    test(
      'category version checkpoint $boundary rejects interrupted epoch',
      () async {
        var count = 0;
        await expectLater(
          readCatalog(
            version: () async {
              count++;
              if (count == boundary) observation = observe(sessionEpoch: 2);
              return '1';
            },
          ),
          throwsA(sessionFailure(ExpenseSessionFailure.contextChanged)),
        );
        expect(count, boundary);
      },
    );
  }
}

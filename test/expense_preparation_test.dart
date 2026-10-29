import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:app_elevage/offline/expense_business_date.dart';
import 'package:app_elevage/offline/expense_preparation.dart';

void main() {
  tzdata.initializeTimeZones();
  final dates = ExpenseBusinessDate(tz.getLocation('Europe/Paris'));
  final context = ExpenseSelectionContext(farmId: 1, authorId: 2);
  final now = DateTime.utc(2026, 12, 31, 23, 30);
  const local = '12345678-1234-1234-1234-123456789abc';
  const parent = 'aaaaaaaa-1234-1234-1234-123456789abc';
  Map<String, dynamic> serverRow({bool finished = false}) => {
    'data': {
      'id': 17,
      'nom': 'Lot confirmé',
      'exploitation': 1,
      'statut': finished ? 'TERMINE' : 'ACTIF',
      'date_fin': null,
    },
    'state': 'CONFIRMED_CACHE',
    'dependency': null,
  };
  Map<String, dynamic> localRow() => {
    'data': {'id': local, 'nom': 'Lot provisoire'},
    'local_uuid': local,
    'dependency': parent,
    'state': 'UNREVIEWED',
  };
  Map<String, dynamic> declaration(String kind) => {
    'client_operation_id': parent,
    'local_entity_id': local,
    'entity_type': kind,
    'operation_type': 'CREATE',
    'exploitation_id': 1,
    'author_user_id': 2,
    'payload': kind == 'ACHAT'
        ? {'quantite': 10, 'nom_lot': 'Lot provisoire'}
        : {
            'total_naissances': 12,
            'mort_nes': 2,
            'nom_nouveau_lot': 'Lot provisoire',
          },
  };
  Future<ExpenseCategoryCatalog> catalog({
    ExpenseCacheFreshness freshness = ExpenseCacheFreshness.current,
    ExpenseSelectionContext? scope,
  }) => ExpenseCategoryCatalog.readAll(
    origin: scope ?? context,
    currentContext: () => scope ?? context,
    freshness: freshness,
    readPage: (collection, {required offset, required limit}) async =>
        offset == 0
        ? [
            {
              'data': {
                'id': 4,
                'nom': 'Transport',
                'exploitation': (scope ?? context).farmId,
              },
            },
          ]
        : [],
  );
  Matcher prepError(ExpensePreparationError code) =>
      isA<ExpensePreparationException>().having((e) => e.code, 'code', code);
  Matcher dateError(ExpenseDateError code) =>
      isA<ExpenseDateException>().having((e) => e.code, 'code', code);

  for (final entry in {
    '2026-01-15': 11,
    '2026-07-15': 10,
    '2026-03-28': 11,
    '2026-03-29': 10,
    '2026-10-24': 10,
    '2026-10-25': 11,
    '2026-01-31': 11,
    '2026-04-30': 10,
    '2025-12-31': 11,
    '2026-01-01': 11,
    '2024-02-29': 11,
  }.entries) {
    test('Paris noon and round trip ${entry.key}', () {
      final parts = entry.key.split('-').map(int.parse).toList();
      final selected = ExpenseBusinessDay(parts[0], parts[1], parts[2]);
      final utc = dates.representativeUtc(selected, nowUtc: now);
      expect(utc, DateTime.utc(parts[0], parts[1], parts[2], entry.value));
      expect(utc.isUtc, isTrue);
      final roundTrip = dates.businessDayOf(utc);
      expect([roundTrip.year, roundTrip.month, roundTrip.day], parts);
    });
  }
  test('phone timezone globals never used or changed', () {
    final previous = tz.local;
    try {
      for (final name in ['Asia/Tokyo', 'Pacific/Honolulu', 'UTC']) {
        final phone = tz.getLocation(name);
        tz.setLocalLocation(phone);
        final result = dates.representativeUtc(
          ExpenseBusinessDay(2026, 7, 15),
          nowUtc: now,
        );
        expect(result, DateTime.utc(2026, 7, 15, 10));
        expect(tz.local, same(phone));
      }
    } finally {
      tz.setLocalLocation(previous);
    }
  });
  test('today is Paris day even across UTC month/year boundary', () {
    final result = dates.representativeUtc(
      ExpenseBusinessDay(2027, 1, 1),
      nowUtc: now,
    );
    expect(result, DateTime.utc(2027, 1, 1, 11));
    expect(
      () =>
          dates.representativeUtc(ExpenseBusinessDay(2027, 1, 2), nowUtc: now),
      throwsA(dateError(ExpenseDateError.futureDate)),
    );
    expect(
      () => dates.representativeUtc(
        ExpenseBusinessDay(2026, 4, 1),
        nowUtc: DateTime.utc(2026, 3, 31, 21, 59),
      ),
      throwsA(dateError(ExpenseDateError.futureDate)),
    );
    expect(
      dates.representativeUtc(
        ExpenseBusinessDay(2026, 4, 1),
        nowUtc: DateTime.utc(2026, 3, 31, 22),
      ),
      DateTime.utc(2026, 4, 1, 10),
    );
  });
  for (final parts in [
    [2026, 2, 29],
    [2026, 4, 31],
    [2026, 0, 1],
    [2026, 13, 1],
    [2026, 1, 0],
    [0, 1, 1],
    [1000000, 1, 1],
  ]) {
    test('invalid calendar date $parts', () {
      expect(
        () => ExpenseBusinessDay(parts[0], parts[1], parts[2]),
        throwsA(dateError(ExpenseDateError.invalidDate)),
      );
    });
  }
  test('explicit UTC clock and Paris location required', () {
    expect(
      () => dates.representativeUtc(
        ExpenseBusinessDay(2026, 1, 1),
        nowUtc: DateTime(2026, 2, 1),
      ),
      throwsA(dateError(ExpenseDateError.utcRequired)),
    );
    expect(
      () => dates.businessDayOf(DateTime(2026, 1, 1)),
      throwsA(dateError(ExpenseDateError.utcRequired)),
    );
    expect(
      () => ExpenseBusinessDate(tz.getLocation('UTC')),
      throwsA(dateError(ExpenseDateError.wrongTimeZone)),
    );
  });
  test('confirmed and finished lots retain explicit display state', () {
    final result = ExpenseLotSelection.fromProjectedRow(
      serverRow(finished: true),
      origin: context,
    );
    expect(result.reference, {'server_id': 17});
    expect(result.dependencies, isEmpty);
    expect(result.isFinished, isTrue);
    expect(result.name, 'Lot confirmé');
    expect(result.state, 'CONFIRMED_CACHE');
    final reconcile = serverRow()..['state'] = 'NEEDS_RECONCILIATION';
    expect(
      ExpenseLotSelection.fromProjectedRow(reconcile, origin: context).state,
      'NEEDS_RECONCILIATION',
    );
  });
  for (final kind in ['ACHAT', 'NAISSANCE']) {
    test(
      'existing $kind local lot creator dependency and immutable selection',
      () {
        final row = localRow();
        final original = declaration(kind);
        final result = ExpenseLotSelection.fromProjectedRow(
          row,
          origin: context,
          parentDeclaration: original,
        );
        expect(result.reference, {'local_uuid': local});
        expect(result.dependencies, [parent]);
        expect(result.originatingEntityType, kind);
        expect(original, declaration(kind));
        (row['data'] as Map)['nom'] = 'Changed';
        original['local_entity_id'] = 'Changed';
        expect(result.name, 'Lot provisoire');
        expect(result.reference, {'local_uuid': local});
        expect(
          () => result.reference['server_id'] = 17,
          throwsUnsupportedError,
        );
        expect(() => result.dependencies.add(local), throwsUnsupportedError);
      },
    );
  }
  test('later confirmed mapping never rewrites an earlier local selection', () {
    final original = declaration('ACHAT');
    final earlier = ExpenseLotSelection.fromProjectedRow(
      localRow(),
      origin: context,
      parentDeclaration: original,
    );
    final mappedRow = serverRow()..['local_uuid'] = local;
    final later = ExpenseLotSelection.fromProjectedRow(
      mappedRow,
      origin: context,
    );
    expect(later.reference, {'server_id': 17});
    expect(earlier.reference, {'local_uuid': local});
    expect(earlier.dependencies, [parent]);
    expect(original, declaration('ACHAT'));
  });
  for (final key in ['exploitation', 'exploitation_id']) {
    test('foreign known lot $key refused', () {
      final row = serverRow();
      (row['data'] as Map)[key] = 9;
      expect(
        () => ExpenseLotSelection.fromProjectedRow(row, origin: context),
        throwsA(prepError(ExpensePreparationError.foreignContext)),
      );
    });
  }
  for (final change in <String, Object>{
    'author_user_id': 3,
    'exploitation_id': 2,
    'entity_type': 'CLIENT',
    'operation_type': 'UPDATE',
    'local_entity_id': parent,
    'client_operation_id': local,
  }.entries) {
    test('invalid or foreign local parent ${change.key}', () {
      final original = declaration('ACHAT')..[change.key] = change.value;
      expect(
        () => ExpenseLotSelection.fromProjectedRow(
          localRow(),
          origin: context,
          parentDeclaration: original,
        ),
        throwsA(isA<ExpensePreparationException>()),
      );
    });
  }
  test(
    'colleague parent requires explicit same-device generation provenance',
    () {
      final original = declaration('ACHAT')
        ..['author_user_id'] = 3
        ..['device_id'] = 7
        ..['device_generation'] = 1;
      // A caller without prepared device context cannot share a foreign author.
      expect(
        () => ExpenseLotSelection.fromProjectedRow(
          localRow(),
          origin: context,
          parentDeclaration: original,
        ),
        throwsA(isA<ExpensePreparationException>()),
      );
      final selection = ExpenseLotSelection.fromProjectedRow(
        localRow(),
        origin: context,
        parentDeclaration: original,
        deviceId: 7,
        generation: 1,
      );
      expect(selection.origin.authorId, 2);
      expect(selection.dependencies, [parent]);
      expect(original['author_user_id'], 3);
      for (final change in {
        'device_id': 8,
        'device_generation': 2,
        'exploitation_id': 2,
      }.entries) {
        expect(
          () => ExpenseLotSelection.fromProjectedRow(
            localRow(),
            origin: context,
            parentDeclaration: {...original, change.key: change.value},
            deviceId: 7,
            generation: 1,
          ),
          throwsA(isA<ExpensePreparationException>()),
        );
      }
    },
  );
  test(
    'missing parent, no live births, bad IDs and ambiguous rows refused',
    () {
      expect(
        () => ExpenseLotSelection.fromProjectedRow(localRow(), origin: context),
        throwsA(prepError(ExpensePreparationError.invalidParent)),
      );
      final noChild = declaration('NAISSANCE')
        ..['payload'] = {'total_naissances': 2, 'mort_nes': 2};
      expect(
        () => ExpenseLotSelection.fromProjectedRow(
          localRow(),
          origin: context,
          parentDeclaration: noChild,
        ),
        throwsA(prepError(ExpensePreparationError.invalidParent)),
      );
      for (final id in [0, -1, 17.0, '17', true]) {
        final row = serverRow();
        (row['data'] as Map)['id'] = id;
        expect(
          () => ExpenseLotSelection.fromProjectedRow(row, origin: context),
          throwsA(isA<ExpensePreparationException>()),
        );
      }
      final ambiguous = serverRow()..['dependency'] = parent;
      expect(
        () => ExpenseLotSelection.fromProjectedRow(ambiguous, origin: context),
        throwsA(prepError(ExpensePreparationError.invalidReference)),
      );
    },
  );
  test(
    'all category pages, including >200 items, read from existing collection',
    () async {
      final offsets = <int>[];
      final result = await ExpenseCategoryCatalog.readAll(
        origin: context,
        currentContext: () => context,
        freshness: ExpenseCacheFreshness.current,
        readPage: (collection, {required offset, required limit}) async {
          expect(collection, 'expense_categories');
          expect(limit, 50);
          offsets.add(offset);
          final end = (offset + limit).clamp(0, 451);
          return [
            for (var i = offset; i < end; i++)
              {
                'data': {'id': i + 1, 'nom': 'Cat $i', 'exploitation': 1},
              },
          ];
        },
      );
      expect(result.categories, hasLength(451));
      expect(result.select(451).id, 451);
      expect(offsets, [0, 50, 100, 150, 200, 250, 300, 350, 400, 450, 451]);
      expect(() => result.categories.clear(), throwsUnsupportedError);
    },
  );
  test('short category page does not end pagination', () async {
    var calls = 0;
    final result = await ExpenseCategoryCatalog.readAll(
      origin: context,
      currentContext: () => context,
      freshness: ExpenseCacheFreshness.unknown,
      readPage: (_, {required offset, required limit}) async {
        calls++;
        return offset < 3
            ? [
                {
                  'data': {'id': offset + 1, 'nom': 'Cat'},
                },
              ]
            : [];
      },
    );
    expect(result.categories, hasLength(3));
    expect(calls, 4);
    expect(result.needsFreshnessNotice, isTrue);
  });
  test('empty cache and disappeared category have no fallback', () async {
    final empty = await ExpenseCategoryCatalog.readAll(
      origin: context,
      currentContext: () => context,
      freshness: ExpenseCacheFreshness.unknown,
      readPage: (_, {required offset, required limit}) async => [],
    );
    expect(empty.isEmpty, isTrue);
    expect(
      () => empty.select(4),
      throwsA(prepError(ExpensePreparationError.missingCategory)),
    );
    final available = await catalog();
    expect(
      () => available.select(5),
      throwsA(prepError(ExpensePreparationError.missingCategory)),
    );
  });
  for (final freshness in ExpenseCacheFreshness.values) {
    test('category cache exposes freshness $freshness', () async {
      final result = await catalog(freshness: freshness);
      expect(result.freshness, freshness);
      expect(
        result.needsFreshnessNotice,
        freshness != ExpenseCacheFreshness.current,
      );
      expect(result.select(4).id, 4);
    });
  }
  for (final data in [
    {'id': 0, 'nom': 'Bad'},
    {'id': '4', 'nom': 'Bad'},
    {'id': 4, 'nom': ''},
    {'id': 4, 'nom': 'Foreign', 'exploitation': 2},
    {'id': 4, 'nom': 'Foreign', 'exploitation_id': 2},
  ]) {
    test('invalid/foreign category $data', () async {
      await expectLater(
        ExpenseCategoryCatalog.readAll(
          origin: context,
          currentContext: () => context,
          freshness: ExpenseCacheFreshness.current,
          readPage: (_, {required offset, required limit}) async => [
            {'data': data},
          ],
        ),
        throwsA(isA<ExpensePreparationException>()),
      );
    });
  }
  test(
    'repeated page refused instead of infinite loop or incomplete catalog',
    () async {
      await expectLater(
        ExpenseCategoryCatalog.readAll(
          origin: context,
          currentContext: () => context,
          freshness: ExpenseCacheFreshness.current,
          readPage: (_, {required offset, required limit}) async => [
            {
              'data': {'id': 4, 'nom': 'Cat'},
            },
          ],
        ),
        throwsA(prepError(ExpensePreparationError.invalidCache)),
      );
    },
  );
  test('profile/farm switch during category read fails closed', () async {
    for (final next in [
      ExpenseSelectionContext(farmId: 2, authorId: 2),
      ExpenseSelectionContext(farmId: 1, authorId: 3),
    ]) {
      var current = context;
      await expectLater(
        ExpenseCategoryCatalog.readAll(
          origin: context,
          currentContext: () => current,
          freshness: ExpenseCacheFreshness.current,
          readPage: (_, {required offset, required limit}) async {
            current = next;
            return [
              {
                'data': {'id': 4, 'nom': 'Cat'},
              },
            ];
          },
        ),
        throwsA(prepError(ExpensePreparationError.changedContext)),
      );
    }
  });
  test(
    'invalid page size, oversized page and read failure preserved',
    () async {
      await expectLater(
        ExpenseCategoryCatalog.readAll(
          origin: context,
          currentContext: () => context,
          freshness: ExpenseCacheFreshness.current,
          pageSize: 201,
          readPage: (_, {required offset, required limit}) async => [],
        ),
        throwsA(prepError(ExpensePreparationError.invalidCache)),
      );
      await expectLater(
        ExpenseCategoryCatalog.readAll(
          origin: context,
          currentContext: () => context,
          freshness: ExpenseCacheFreshness.current,
          pageSize: 1,
          readPage: (_, {required offset, required limit}) async => [{}, {}],
        ),
        throwsA(prepError(ExpensePreparationError.invalidCache)),
      );
      await expectLater(
        ExpenseCategoryCatalog.readAll(
          origin: context,
          currentContext: () => context,
          freshness: ExpenseCacheFreshness.current,
          readPage: (_, {required offset, required limit}) async =>
              throw StateError('read failed'),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'compose B1, date and existing dependency without transport metadata',
    () async {
      final lot = ExpenseLotSelection.fromProjectedRow(
        localRow(),
        origin: context,
        parentDeclaration: declaration('ACHAT'),
      );
      final result = ExpensePreparation.compose(
        currentContext: context,
        lot: lot,
        categories: await catalog(freshness: ExpenseCacheFreshness.stale),
        categoryId: 4,
        amount: '1234,5',
        note: ' Transport ',
        day: ExpenseBusinessDay(2026, 7, 15),
        dates: dates,
        nowUtc: now,
      );
      expect(result.payload, {
        'lot_ref': {'local_uuid': local},
        'categorie_id': 4,
        'montant': '1234.50',
        'note': 'Transport',
      });
      expect(result.businessOccurredAt, now);
      expect(result.dependencies, [parent]);
      expect(result.origin, same(context));
      expect(result.categoryCacheFreshness, ExpenseCacheFreshness.stale);
      expect(() => result.payload['date'] = 'bad', throwsUnsupportedError);
      expect(() => result.dependencies.clear(), throwsUnsupportedError);
      expect((result.payload['lot_ref'] as Map).keys, ['local_uuid']);
    },
  );
  test(
    'finished lot can compose; cross-profile/farm/category and bad B1 rejected',
    () async {
      final lot = ExpenseLotSelection.fromProjectedRow(
        serverRow(finished: true),
        origin: context,
      );
      final categories = await catalog();
      PreparedExpense compose({
        ExpenseSelectionContext? current,
        ExpenseCategoryCatalog? cats,
        String amount = '1',
        int categoryId = 4,
      }) => ExpensePreparation.compose(
        currentContext: current ?? context,
        lot: lot,
        categories: cats ?? categories,
        categoryId: categoryId,
        amount: amount,
        day: ExpenseBusinessDay(2026, 1, 1),
        dates: dates,
        nowUtc: now,
      );
      expect(compose().lot.isFinished, isTrue);
      expect(compose().dependencies, isEmpty);
      for (final current in [
        ExpenseSelectionContext(farmId: 2, authorId: 2),
        ExpenseSelectionContext(farmId: 1, authorId: 3),
      ]) {
        expect(
          () => compose(current: current),
          throwsA(prepError(ExpensePreparationError.foreignContext)),
        );
      }
      final foreign = await catalog(
        scope: ExpenseSelectionContext(farmId: 2, authorId: 2),
      );
      expect(
        () => compose(cats: foreign),
        throwsA(prepError(ExpensePreparationError.foreignContext)),
      );
      expect(
        () => compose(categoryId: 99),
        throwsA(prepError(ExpensePreparationError.missingCategory)),
      );
      expect(
        () => compose(amount: '1.999'),
        throwsA(
          isA<ExpensePreparationException>().having(
            (e) => e.fieldErrors.keys,
            'fields',
            ['montant'],
          ),
        ),
      );
    },
  );
}

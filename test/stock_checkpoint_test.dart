import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'outbox_test.dart' show testOutboxGrant;

void main() {
  late Directory directory;
  late FarmDatabase db;
  late VerifiedOfflineGrant paul, jean;
  final now = DateTime.utc(2026, 10, 7);
  FarmDatabase open() => FarmDatabase(
    encryptedExecutor(
      File('${directory.path}/farm.db'),
      List.filled(64, 'c').join(),
    ),
    farmId: 1,
    serverNamespace: 'checkpoint.invalid',
    clock: () => now,
  );
  Map<String, dynamic> lot(int stock, int revision) => {
    'id': 7,
    'nom': 'Porcs fictifs',
    'exploitation': 1,
    'stock': stock,
    'stock_oeufs': 0,
    'confirmed_business_revision': revision,
  };
  Future<OutboxEntry> sale({VerifiedOfflineGrant? author, String? id}) => db.enqueue(
    grant: author ?? paul,
    isSessionCurrent: () => true,
    entityType: 'VENTE_ANIMAUX',
    operationType: 'CREATE',
    payload: {
      'lot_ref': {'server_id': 7},
      'client_ref': {'server_id': 11},
      'quantite': 10,
      'prix_unitaire': '1.00',
    },
    businessOccurredAt: now,
    operationId: id,
  );
  Map<String, dynamic> receipt(
    OutboxEntry entry,
    int stock,
    int revision, {
    String state = 'CONFIRMED',
  }) => {
    'client_operation_id': entry.operationId,
    'author_user_id': entry.authorId,
    'transport_status': 'SERVER_RECEIVED',
    'business_status': state,
    'received_at': now.toIso8601String(),
    'applied_at': state == 'CONFIRMED' ? now.toIso8601String() : null,
    'server_entity_id': state == 'CONFIRMED' ? '${entry.sequence}' : '',
    'server_version': state == 'CONFIRMED' ? 'farm:${entry.sequence}' : '',
    'stock_snapshots': state == 'CONFIRMED' ? [lot(stock, revision)] : [],
    'reason_code': state == 'NEEDS_RECONCILIATION'
        ? 'OFFLINE_PERMISSION_DENIED'
        : '',
  };
  Future<Map> stock() async =>
      (await db.projectedPage('lots')).single['data'] as Map;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'elevage-stock-checkpoint-',
    );
    db = open();
    paul = await testOutboxGrant(2, now);
    jean = await testOutboxGrant(3, now);
    await db.replaceConfirmedCache('lots', [lot(100, 0)]);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  for (final reverse in [false, true]) {
    test(
      'two authors partial receipts reverse=$reverse preserve 80 through restart and duplicate',
      () async {
        final a = await sale(id: '11111111-1111-4111-8111-111111111111'),
            b = await sale(author: jean, id: '22222222-2222-4222-8222-222222222222');
        final first = reverse ? b : a, last = reverse ? a : b;
        expect((await stock())['projected_stock'], 80);
        await db.acceptReceipts([receipt(first, 80, 2)]);
        expect((await stock())['stock'], 100);
        expect((await stock())['projected_stock'], 80);
        expect(
          (await db.listOutbox())
              .singleWhere((e) => e.operationId == last.operationId)
              .businessStatus,
          'UNREVIEWED',
        );
        await db.acceptReceipts([receipt(first, 80, 2)]);
        await expectLater(
          db.replaceConfirmedCache('lots', [lot(80, 2)]),
          throwsStateError,
        );
        await db.close();
        db = open();
        expect((await stock())['projected_stock'], 80);
        await db.acceptReceipts([receipt(last, 80, 2)]);
        expect((await stock())['stock'], 80);
        expect((await stock())['local_delta'], 0);
        expect((await stock())['projected_stock'], 80);
        await db.acceptReceipts([receipt(first, 80, 2), receipt(last, 80, 2)]);
        expect((await stock())['projected_stock'], 80);
        expect(
          (await db.listOutbox()).map((e) => e.declaration),
          containsAll([a.declaration, b.declaration]),
        );
      },
    );
  }

  test(
    'a different server decrease never confirms or covers an unknown original',
    () async {
      final a = await sale(), b = await sale(author: jean);
      // Only A applied; an unrelated server movement also removed 10.
      await db.acceptReceipts([receipt(a, 80, 2)]);
      expect(
        (await stock())['projected_stock'],
        80,
      ); // Last checkpoint + both originals.
      expect(
        (await db.listOutbox())
            .singleWhere((e) => e.operationId == b.operationId)
            .businessStatus,
        'UNREVIEWED',
      );
      await db.acceptReceipts([receipt(b, 70, 3)]);
      expect((await stock())['projected_stock'], 70);
    },
  );

  test('an older first snapshot arriving after the second never rolls stock back', () async {
    final a=await sale(),b=await sale(author:jean);
    await db.acceptReceipts([receipt(b,80,2)]);
    expect((await stock())['projected_stock'],80);
    await db.acceptReceipts([receipt(a,90,1)]);
    expect((await stock())['stock'],80);
    expect((await stock())['local_delta'],0);
    await db.acceptReceipts([receipt(a,90,1)]);
    expect((await stock())['projected_stock'],80);
  });

  test(
    'refused and reconciliation originals stay visible without preventing a coherent checkpoint',
    () async {
      final a = await sale(), b = await sale(author: jean);
      await db.acceptReceipts([receipt(a, 90, 1)]);
      await db.acceptReceipts([
        receipt(b, 90, 1, state: 'NEEDS_RECONCILIATION'),
      ]);
      expect((await stock())['stock'], 90);
      expect(
        (await stock())['projected_stock'],
        80,
      ); // Existing physical-constat policy.
      expect(
        (await db.projectedPage('lots')).single['state'],
        'NEEDS_RECONCILIATION',
      );
      expect(
        (await db.listOutbox())
            .singleWhere((e) => e.operationId == b.operationId)
            .declaration,
        b.declaration,
      );
    },
  );

  test(
    '61 originals and paginated receipts do not fold the first page prematurely',
    () async {
      await db.replaceConfirmedCache('lots', [lot(1000, 0)]);
      final originals = <OutboxEntry>[];
      for (var i = 0; i < 61; i++) {
        originals.add(await sale(author: i.isEven ? paul : jean));
      }
      await db.acceptReceipts([
        for (final e in originals.take(50))
          receipt(e, 390, 61, state: 'UNREVIEWED'),
      ]);
      await db.acceptReceipts([
        for (final e in originals.skip(50))
          receipt(e, 390, 61, state: 'UNREVIEWED'),
      ]);
      final firstPage = await db.awaitingReceipts();
      expect(firstPage, hasLength(50));
      await db.acceptReceipts([for (final e in firstPage) receipt(e, 390, 61)]);
      expect((await stock())['projected_stock'], 390);
      expect((await stock())['stock'], 1000);
      await db.close();
      db = open();
      final secondPage = await db.awaitingReceipts();
      expect(
        secondPage.where((e) => e.businessStatus == 'UNREVIEWED'),
        hasLength(11),
      );
      await db.acceptReceipts([
        for (final e in secondPage) receipt(e, 390, 61),
      ]);
      expect((await stock())['stock'], 390);
      expect((await stock())['local_delta'], 0);
      expect(await db.listOutbox(limit: 200), hasLength(61));
      expect(
        (await db.listOutbox(limit: 200)).map((e) => e.declaration),
        containsAll(originals.map((e) => e.declaration)),
      );
    },
  );

  test(
    'a duplicate of a folded original cannot add its delta again while another awaits',
    () async {
      final a = await sale();
      await db.acceptReceipts([receipt(a, 90, 1)]);
      final b = await sale(author: jean);
      await db.acceptReceipts([receipt(a, 80, 2)]);
      expect((await stock())['stock'], 90);
      expect((await stock())['projected_stock'], 80);
      await db.acceptReceipts([receipt(b, 80, 2)]);
      expect((await stock())['projected_stock'], 80);
    },
  );

  for (final kind in ['MORTALITE', 'DON', 'VOL']) {
    test('$kind shares the same explicit checkpoint as sales', () async {
      final removal = await db.enqueue(
        grant: paul,
        isSessionCurrent: () => true,
        entityType: kind,
        operationType: 'CREATE',
        payload: {
          'lot_ref': {'server_id': 7},
          'quantite': 10,
        },
        businessOccurredAt: now,
      );
      final b = await sale(author: jean);
      await db.acceptReceipts([receipt(removal, 80, 2)]);
      expect((await stock())['projected_stock'], 80);
      await db.acceptReceipts([receipt(b, 80, 2)]);
      expect((await stock())['stock'], 80);
      expect((await stock())['local_delta'], 0);
    });
  }

  test(
    'NOT_APPLIED original is kept but its effect is not projected',
    () async {
      final a = await sale(), b = await sale(author: jean);
      await db.acceptReceipts([receipt(a, 90, 1)]);
      await db.acceptReceipts([receipt(b, 90, 1, state: 'NOT_APPLIED')]);
      expect((await stock())['projected_stock'], 90);
      expect(
        (await db.listOutbox())
            .singleWhere((e) => e.operationId == b.operationId)
            .declaration,
        b.declaration,
      );
    },
  );

  test(
    'schema 7 ambiguous cached stock is preserved and explicitly blocked until rebased',
    () async {
      final a = await sale(), b = await sale(author: jean);
      await db.acceptReceipts([receipt(a, 80, 2)]);
      // Reconstruct the old defect exactly in a synthetic encrypted fixture:
      // old cache already 80, A confirmed, B unknown, no projection metadata.
      await db.customStatement(
        "UPDATE confirmed_cache SET payload=? WHERE collection='lots' AND entity_id='7'",
        [
          '{"id":7,"nom":"Porcs fictifs","exploitation":1,"stock":80,"stock_oeufs":0,"confirmed_business_revision":2}',
        ],
      );
      await db.customStatement('DROP TABLE terrain_pending_stock_snapshot');
      await db.customStatement(
        'ALTER TABLE outbox DROP COLUMN stock_projection_folded',
      );
      await db.customStatement(
        'ALTER TABLE tablet_sync_state DROP COLUMN stock_rebase_required',
      );
      await db.customStatement('DROP TABLE screen_snapshots');
      await db.customStatement('PRAGMA user_version=7');
      await db.close();
      db = open();
      await expectLater(stock(), throwsStateError);
      expect(
        (await db.cachedPage('lots')).single['data'],
        containsPair('stock', 80),
      );
      await db.acceptReceipts([receipt(b, 80, 2)]);
      await expectLater(stock(), throwsStateError);
      await db.replaceConfirmedCache('lots', [lot(80, 2)]);
      expect((await stock())['projected_stock'], 80);
      expect(
        (await db.listOutbox()).map((e) => e.declaration),
        containsAll([a.declaration, b.declaration]),
      );
    },
  );

  for (final kind in ['ACHAT', 'NAISSANCE']) {
    test(
      '$kind mapping remains usable while its child loss awaits a receipt',
      () async {
        final payload = kind == 'ACHAT'
            ? <String, dynamic>{
                'nom_lot': 'Enfant fictif',
                'quantite': 10,
                'espece': 1,
                'prix_total': '10.00',
                'prix_unitaire': '1.00',
              }
            : <String, dynamic>{
                'lot_ref': {'server_id': 7},
                'total_naissances': 12,
                'mort_nes': 2,
                'nom_nouveau_lot': 'Enfant fictif',
              };
        final parent = await db.enqueue(
          grant: paul,
          isSessionCurrent: () => true,
          entityType: kind,
          operationType: 'CREATE',
          payload: payload,
          businessOccurredAt: now,
        );
        final child = await db.enqueue(
          grant: jean,
          isSessionCurrent: () => true,
          entityType: 'MORTALITE',
          operationType: 'CREATE',
          payload: {
            'lot_ref': {'local_uuid': parent.declaration['local_entity_id']},
            'quantite': 2,
          },
          businessOccurredAt: now,
          dependencies: [parent.operationId],
        );
        final snapshot = lot(8, 2)..['id'] = 42;
        final parentReceipt = receipt(parent, 8, 2)
          ..['stock_snapshots'] = [snapshot]
          ..['entity_mappings'] = [
            {
              'entity_type': 'LOT',
              'local_entity_id': parent.declaration['local_entity_id'],
              'server_entity_id': 42,
            },
          ];
        await db.acceptReceipts([parentReceipt]);
        await db.close();
        db = open();
        var rows = await db.projectedPage('lots');
        final projected = rows.singleWhere(
          (row) => (row['data'] as Map)['id'] == 42,
        );
        expect(projected['data'], containsPair('projected_stock', 8));
        expect(projected['data'], containsPair('stock', 0));
        expect(projected['stock_checkpoint_pending'], isTrue);
        final childReceipt = receipt(child, 8, 2)
          ..['stock_snapshots'] = [snapshot];
        await db.acceptReceipts([childReceipt]);
        rows = await db.projectedPage('lots');
        expect(
          rows.where((row) => (row['data'] as Map)['id'] == 42),
          hasLength(1),
        );
        expect(
          rows.singleWhere((row) => (row['data'] as Map)['id'] == 42)['data'],
          containsPair('stock', 8),
        );
        expect(
          rows.singleWhere((row) => (row['data'] as Map)['id'] == 7)['data'],
          containsPair('stock', 100),
        );
        expect((await db.listOutbox()).map((e) => e.authorId).toSet(), {2, 3});
      },
    );
  }

  test(
    'egg collection and sale retain both deltas until the last receipt',
    () async {
      final collection = await db.enqueue(
        grant: paul,
        isSessionCurrent: () => true,
        entityType: 'COLLECTE_OEUFS',
        operationType: 'CREATE',
        payload: {
          'lot_ref': {'server_id': 7},
          'nombre_collecte': 8,
        },
        businessOccurredAt: now,
      );
      final sale = await db.enqueue(
        grant: jean,
        isSessionCurrent: () => true,
        entityType: 'VENTE_OEUFS',
        operationType: 'CREATE',
        payload: {
          'lot_ref': {'server_id': 7},
          'client_ref': {'server_id': 11},
          'conditionnement': 'UNITE',
          'nombre_conditionnements': 3,
          'prix_unitaire_conditionnement': '1.00',
        },
        businessOccurredAt: now,
      );
      final snapshot = lot(100, 2)..['stock_oeufs'] = 5;
      await db.acceptReceipts([
        receipt(collection, 100, 2)..['stock_snapshots'] = [snapshot],
      ]);
      expect((await stock())['projected_egg_stock'], 5);
      await db.acceptReceipts([
        receipt(sale, 100, 2)..['stock_snapshots'] = [snapshot],
      ]);
      expect((await stock())['stock_oeufs'], 5);
      expect((await stock())['local_egg_delta'], 0);
    },
  );

  test(
    'contradictory partial snapshot rolls back its receipt without losing either original',
    () async {
      final a = await sale(), b = await sale(author: jean);
      await db.acceptReceipts([receipt(a, 80, 2)]);
      await expectLater(
        db.acceptReceipts([receipt(b, 81, 2)]),
        throwsStateError,
      );
      expect((await stock())['projected_stock'], 80);
      expect(
        (await db.listOutbox())
            .singleWhere((e) => e.operationId == b.operationId)
            .businessStatus,
        'UNREVIEWED',
      );
      await db.acceptReceipts([receipt(b, 80, 2)]);
      expect((await stock())['stock'], 80);
      expect(await db.listOutbox(), hasLength(2));
    },
  );
}

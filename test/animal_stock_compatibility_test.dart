import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'outbox_test.dart' show testOutboxGrant;

void main() {
  late Directory directory;
  late FarmDatabase db;
  late VerifiedOfflineGrant grant;
  final now = DateTime.utc(2026, 10, 7);
  final key = List.filled(64, 'd').join();
  FarmDatabase open() => FarmDatabase(
    encryptedExecutor(File('${directory.path}/farm.db'), key),
    farmId: 1, serverNamespace: 'c111-stock', clock: () => now,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('c111-stock-');
    db = open();
    grant = await testOutboxGrant(2, now);
  });
  tearDown(() async { await db.close(); await directory.delete(recursive: true); });

  Map<String, dynamic> lot(int stock, int revision, {int eggs = 100}) => {
    'id': 7, 'nom': 'Synthetic lot', 'exploitation': 1, 'stock': stock,
    'stock_oeufs': eggs, 'confirmed_business_revision': revision,
  };
  Future<OutboxEntry> declare(String kind, Map<String, dynamic> payload) => db.enqueue(
    grant: grant, isSessionCurrent: () => true, entityType: kind,
    operationType: 'CREATE', payload: payload, businessOccurredAt: now,
  );
  Map<String, dynamic> receipt(OutboxEntry entry, Map<String, dynamic> snapshot,
      {bool reversed = false}) => {
    'client_operation_id': entry.operationId, 'author_user_id': entry.authorId,
    'transport_status': 'SERVER_RECEIVED',
    'business_status': reversed ? 'SUPERSEDED' : 'CONFIRMED',
    'server_entity_id': '42', 'server_version': reversed ? '2' : '1',
    'received_at': now.toIso8601String(), 'applied_at': now.toIso8601String(),
    'stock_snapshots': [snapshot],
    if (reversed) ...{'decision_version': 1, 'decision_action': 'REVERSE', 'decision_actor_id': 1},
  };
  Future<Map> current() async => (await db.projectedPage('lots')).single['data'] as Map;

  test('animal compensation is a revised absolute snapshot and never a second local delta', () async {
    await db.replaceConfirmedCache('lots', [lot(10, 1)]);
    final loss = await declare('MORTALITE', {'lot_ref': {'server_id': 7}, 'quantite': 2});
    expect((await current())['stock'], 10);
    expect((await current())['projected_stock'], 8);
    final confirmed = receipt(loss, lot(8, 2));
    await db.acceptReceipts([confirmed]);
    expect((await current())['local_delta'], 0);
    expect((await current())['projected_stock'], 8);
    final reversed = receipt(loss, lot(10, 3), reversed: true);
    await db.acceptReceipts([reversed]);
    await db.acceptReceipts([reversed]);
    await db.close(); db = open();
    await db.acceptReceipts([confirmed]);
    await db.replaceConfirmedCache('lots', [lot(8, 2)]);
    var data = await current();
    expect(data['stock'], 10); expect(data['local_delta'], 0);
    expect(data['projected_stock'], 10); expect(data['stock_oeufs'], 100);
    final pending = await declare('VOL', {'lot_ref': {'server_id': 7}, 'quantite': 1});
    data = await current();
    expect(data['stock'], 10); expect(data['local_delta'], -1);
    expect(data['projected_stock'], 9);
    final rows = await db.listOutbox();
    expect(rows, hasLength(2));
    expect(rows.first.operationId, pending.operationId);
    expect(rows.last.declaration, loss.declaration);
    expect(rows.last.businessStatus, 'SUPERSEDED');
  });

  test('a compensated purchase reaches zero without deleting its declaration or doubling the original entry', () async {
    final purchase = await declare('ACHAT', {
      'nom_lot': 'Purchased', 'espece': 1, 'quantite': 10,
      'prix_total': '20.00', 'prix_unitaire': '2.00',
    });
    final snapshot = lot(10, 1, eggs: 0)..['id'] = 9;
    final confirmed = receipt(purchase, snapshot)..['entity_mappings'] = [
      {'entity_type': 'LOT', 'local_entity_id': purchase.declaration['local_entity_id'], 'server_entity_id': 9},
      {'entity_type': 'ACHAT', 'local_entity_id': purchase.declaration['local_entity_id'], 'server_entity_id': 42},
    ];
    await db.acceptReceipts([confirmed]);
    final reversedSnapshot = {...snapshot, 'stock': 0, 'confirmed_business_revision': 2, 'statut_production': 'TERMINE'};
    final reversed = receipt(purchase, reversedSnapshot, reversed: true)
      ..['entity_mappings'] = confirmed['entity_mappings'];
    await db.acceptReceipts([reversed]); await db.acceptReceipts([reversed]);
    await db.close(); db = open(); await db.acceptReceipts([confirmed]);
    final data = await current();
    expect(data['stock'], 0); expect(data['projected_stock'], 0);
    expect(data['local_delta'], 0); expect(data['statut_production'], 'TERMINE');
    expect((await db.listOutbox()).single.declaration, purchase.declaration);
  });

  test('egg sale reversal updates only eggs and preserves animal stock through replay and restart', () async {
    await db.replaceConfirmedCache('lots', [lot(8, 1)]);
    final sale = await declare('VENTE_OEUFS', {
      'lot_ref': {'server_id': 7}, 'client_ref': {'server_id': 4},
      'conditionnement': 'PLATEAU', 'nombre_conditionnements': 2,
      'prix_unitaire_conditionnement': '5.00',
    });
    expect((await current())['projected_egg_stock'], 40);
    expect((await current())['projected_stock'], 8);
    final confirmed = receipt(sale, lot(8, 2, eggs: 40));
    await db.acceptReceipts([confirmed]);
    final reversed = receipt(sale, lot(8, 3), reversed: true);
    await db.acceptReceipts([reversed]); await db.acceptReceipts([reversed]);
    await db.close(); db = open(); await db.acceptReceipts([confirmed]);
    final data = await current();
    expect(data['stock'], 8); expect(data['projected_stock'], 8);
    expect(data['stock_oeufs'], 100); expect(data['projected_egg_stock'], 100);
    expect(data['local_egg_delta'], 0);
    expect((await db.listOutbox()).single.declaration, sale.declaration);
  });
}

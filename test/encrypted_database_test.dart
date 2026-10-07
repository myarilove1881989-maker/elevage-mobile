import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/offline_database_native.dart';

void main() {
  late String key;
  late Directory directory;
  late File file;
  FarmDatabase open({int farm=1,String? encryptionKey}) => FarmDatabase(
    encryptedExecutor(file,encryptionKey ?? key),farmId:farm,serverNamespace:'test-only');
  setUp(() async {
    key=List.generate(32,(_)=>Random.secure().nextInt(256)).map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    directory=await Directory.systemTemp.createTemp('elevage-cipher-test-'); file=File('${directory.path}/farm.db');
  });
  tearDown(() async { await directory.delete(recursive:true); });

  test('encrypted shared cache survives reopen and rejects wrong key and tenant', () async {
    var db=open();
    await db.replaceConfirmedCache('clients',[{'id':1,'name':'Jean client'}]);
    await db.close();
    final header = (await file.readAsBytes()).take(16).toList();
    expect(header,isNot(utf8.encode('SQLite format 3\u0000')));
    db=open();
    expect((await db.cachedPage('clients')).single['data'],{'id':1,'name':'Jean client'});
    await db.close();
    db=open(farm:2);
    await expectLater(db.cachedPage('clients'),throwsA(predicate<Object>(
      (error)=>error.toString().contains('Cette base appartient à une autre exploitation.'),
      'explicit tenant isolation rejection, including Drift isolate transport',
    )));
    await db.close();
    db=open(encryptionKey:'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');
    await expectLater(db.cachedPage('clients'),throwsA(anything));
    await db.close();
  });

  test('cache refuses secrets and invalid pagination without erasing valid data', () async {
    final db=open();
    try {
      await db.replaceConfirmedCache('clients',[{'id':1,'name':'original'}]);
      await expectLater(db.replaceConfirmedCache('clients',[{'id':2,'refresh_token':'secret'}]),throwsArgumentError);
      expect((await db.cachedPage('clients')).single['data'],{'id':1,'name':'original'});
      await expectLater(db.cachedPage('clients',limit:10000),throwsArgumentError);
    } finally { await db.close(); }
  });

  test('multi-page cache remains visible until complete atomic promotion',() async {
    final db=open();
    try {
      await db.replaceConfirmedCache('clients',[{'id':1,'name':'old'}]);
      await db.beginCacheRefresh('clients');
      await db.stageConfirmedPage('clients',[{'id':2,'name':'page one'}]);
      expect((await db.cachedPage('clients')).single['data'],{'id':1,'name':'old'});
      await db.stageConfirmedPage('clients',[{'id':3,'name':'page two'}]);
      await db.commitCacheRefresh('clients');
      expect((await db.cachedPage('clients')).map((r)=>(r['data'] as Map)['id']),[2,3]);
    } finally {await db.close();}
  });

  test('operator agenda refresh preserves another profile tasks and filters before pagination',() async {
    final db=open();
    try {
      await db.replaceConfirmedCache('tasks',[{'id':1,'assigned_to':2,'title':'Paul'},
        {'id':2,'assigned_to':1,'title':'Jean old'}]);
      await db.beginCacheRefresh('tasks');
      await db.stageConfirmedPage('tasks',[{'id':3,'assigned_to':1,'title':'Jean new'}]);
      await db.commitCacheRefresh('tasks',taskUserId:1);
      expect((await db.cachedPage('tasks',taskUserId:1,limit:1)).single['data'],
        {'id':3,'assigned_to':1,'title':'Jean new'});
      expect((await db.cachedPage('tasks',taskUserId:2)).single['data'],
        {'id':1,'assigned_to':2,'title':'Paul'});
    } finally {await db.close();}
  });

  test('additive local schema migration preserves encrypted confirmed cache',() async {
    var db=open();
    await db.replaceConfirmedCache('clients',[{'id':1,'name':'retained'}]);
    // Recreate the exact previous schema using this synthetic test database.
    await db.customStatement('DROP TABLE terrain_entity_mapping');
    await db.customStatement('DROP TABLE outbox');
    await db.customStatement('DROP TABLE local_sequence_counter');
    await db.customStatement('DROP TABLE confirmed_cache_staging');
    await db.customStatement('PRAGMA user_version=1');
    await db.close();
    db=open();
    try {
      expect((await db.cachedPage('clients')).single['data'],{'id':1,'name':'retained'});
      await db.beginCacheRefresh('clients');
      await db.stageConfirmedPage('clients',[{'id':2,'name':'new'}]);
      await db.commitCacheRefresh('clients');
      expect((await db.cachedPage('clients')).single['data'],{'id':2,'name':'new'});
    } finally {await db.close();}
  });
}

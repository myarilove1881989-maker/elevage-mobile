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
}

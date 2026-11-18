import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/offline_database_native.dart';
import 'feed_stock_projection_test.dart' show baseline;
import 'vaccine_projection_test.dart' show vaccineSnapshot;
void main(){
  test('stock snapshots persist encrypted without changing schema or existing client cache',()async{
    final dir=await Directory.systemTemp.createTemp('synthetic-stock-cache-');
    final file=File('${dir.path}/farm.db');
    final key=List.generate(32,(_)=>Random.secure().nextInt(256)).map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
    FarmDatabase open()=>FarmDatabase(encryptedExecutor(file,key),farmId:1,serverNamespace:'synthetic-stock');
    var db=open();
    try{
      expect(db.schemaVersion,9);
      await db.replaceConfirmedCache('clients',[{'id':7,'nom':'Client fictif'}]);
      await db.replaceConfirmedCache('feed_stock',[baseline(revision:2)]);
      await db.replaceConfirmedCache('vaccine_stock',[vaccineSnapshot(revision:2)]);
      await db.close();expect((await file.readAsBytes()).take(16).toList(),isNot(utf8.encode('SQLite format 3\u0000')));
      db=open();
      expect((await db.cachedPage('clients')).single['data']['nom'],'Client fictif');
      expect((await db.cachedPage('feed_stock')).single['data']['confirmed_business_revision'],2);
      await db.replaceConfirmedCache('feed_stock',[baseline(revision:1)]);
      expect((await db.cachedPage('feed_stock')).single['data']['confirmed_business_revision'],2);
      final foreign=vaccineSnapshot(revision:3)..['exploitation']=2;
      await expectLater(db.replaceConfirmedCache('vaccine_stock',[foreign]),throwsStateError);
      expect((await db.cachedPage('vaccine_stock')).single['data']['confirmed_business_revision'],2);
    }finally{await db.close();await dir.delete(recursive:true);}
  });
}

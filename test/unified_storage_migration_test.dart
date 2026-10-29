import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/offline/farm_database.dart';
import 'offline_fine_permissions_test.dart' show fineGrant,syntheticNow;
import 'unified_access_harness.dart';

void main() {
  test('schema8 upgrade retains original outbox, sequence and prepared profile byte for byte',() async {
    final dir=await Directory.systemTemp.createTemp('elevage-ux-migration-');
    final path=File('${dir.path}/farm.db');
    FarmDatabase open()=>FarmDatabase(encryptedExecutor(path,List.filled(32,'b7').join()),farmId:1,serverNamespace:'migration-test',clock:()=>syntheticNow);
    var db=open();
    try {
      final grant=await fineGrant(credentialVersion:1);
      await db.saveOperatorProfile(grant,'synthetic');
      final original=await db.enqueue(grant:grant,isSessionCurrent:()=>true,entityType:'CLIENT',
        operationType:'CREATE',payload:{'nom':'Synthetic retained original'},businessOccurredAt:syntheticNow);
      final profiles=await db.operatorProfiles();
      final before=await db.customSelect('SELECT next_sequence FROM local_sequence_counter').getSingle();
      // Construct an actual version8 fixture: only the newly added empty table
      // is removed from this newly generated synthetic DB, never user data.
      await db.customStatement('DROP TABLE screen_snapshots');
      await db.customStatement('PRAGMA user_version=8');
      await db.close();db=open();
      final after=(await db.listOutbox()).single;
      expect(jsonEncode(after.declaration),jsonEncode(original.declaration));
      expect(after.sequence,original.sequence);expect(after.transportStatus,original.transportStatus);
      expect(await db.operatorProfiles(),profiles);
      expect((await db.customSelect('SELECT next_sequence FROM local_sequence_counter').getSingle()).data,before.data);
      await db.saveScreenSnapshot(userId:2,credentialVersion:1,path:'/dashboard/',payload:{'kpis':{'stock':10}});
      await db.close();db=open();
      expect(await db.screenSnapshot(userId:2,credentialVersion:1,path:'/dashboard/'),{'kpis':{'stock':10}});
      expect(utf8.decode(await path.readAsBytes(),allowMalformed:true),isNot(contains('Synthetic retained original')));
    } finally {
      await db.close();
      final expected='${Directory.systemTemp.absolute.path}${Platform.pathSeparator}elevage-ux-migration-';
      if(!dir.absolute.path.startsWith(expected)) throw StateError('Unexpected test cleanup path');
      await dir.delete(recursive:true);
    }
  });
  test('prepared core cache supplies expense references offline without first visiting the expense screen',() async {
    SharedPreferences.setMockInitialValues({});tzdata.initializeTimeZones();
    final h=UnifiedAccessHarness();await h.start();
    await h.db.replaceConfirmedCache('lots',[{'id':7,'nom':'Lot fictif','exploitation':1,'espece':1,'stock':10,'stock_oeufs':0,'type_production':'CHAIR'}]);
    await h.db.replaceConfirmedCache('expense_categories',[{'id':3,'nom':'Frais fictifs','exploitation':1}]);
    final runtime=await h.runtime();
    try {
      final api=await runtime.signIn('synthetic','1234');
      h.down=true;await runtime.connection.probe();
      final categories=await api.getCategoriesDepense(),lots=await api.getLots();
      expect(categories.single['id'],3);expect(lots.single['id'],7);
      expect(api.lastReadWasCached,isTrue);
    } finally {
      await runtime.tablet.sync?.waitForIdle();runtime.dispose();await h.db.close();
      final expected='${Directory.systemTemp.absolute.path}${Platform.pathSeparator}elevage-seven-day-';
      if(!h.directory.absolute.path.startsWith(expected)) throw StateError('Unexpected test cleanup path');
      await h.directory.delete(recursive:true);
    }
  });
}

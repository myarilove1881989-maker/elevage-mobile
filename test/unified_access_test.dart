import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/services/server_connection.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/farmer_runtime.dart';
import 'package:app_elevage/services/classic_terrain_command.dart';
import 'foundation_api_test.dart' show TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant,syntheticNow;
import 'unified_access_harness.dart';

void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});tzdata.initializeTimeZones();ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();});
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();ApiService.farmerSession=false;});
  test('same four-character code uses independent salted verifier, old PIN policy retained',() async {
    final store=TestSecretStore();final grant=await fineGrant(credentialVersion:1);
    final sessions=LocalOperatorSessions(store:store,namespace:'unified',farmId:1,deviceId:7,generation:1,clock:()=>syntheticNow);
    await sessions.enroll(grant,'654321');
    await sessions.enrollPersonalCode(grant,'1234',authenticatedCredentialVersion:1);
    expect(await sessions.unlockPersonalCode(grant,'1234'),isTrue);
    expect(store.values.values.any((value)=>value.contains('"1234"')),isFalse);
    expect(await sessions.unlock(grant,'654321'),isTrue);
    await expectLater(sessions.enroll(grant,'1234'),throwsA(isA<ArgumentError>()));
  });
  test('personal code lock survives reconstruction, cooldown and clock rollback',() async {
    var now=syntheticNow;final store=TestSecretStore();final grant=await fineGrant(credentialVersion:1);
    LocalOperatorSessions open()=>LocalOperatorSessions(store:store,namespace:'attempts',farmId:1,deviceId:7,generation:1,clock:()=>now);
    var sessions=open();await sessions.enrollPersonalCode(grant,'1234',authenticatedCredentialVersion:1);
    for(var i=0;i<5;i++) {expect(await sessions.unlockPersonalCode(grant,'0000'),isFalse);}
    sessions=open();expect(await sessions.unlockPersonalCode(grant,'1234'),isFalse);
    now=now.add(const Duration(seconds:31));expect(await sessions.unlockPersonalCode(grant,'1234'),isTrue);
    now=syntheticNow;expect(await sessions.unlockPersonalCode(grant,'1234'),isFalse);
  });
  test('signed credential epoch prevents reverting to old code or legacy grant',() async {
    final store=TestSecretStore();final old=await fineGrant(credentialVersion:1);
    final current=await fineGrant(credentialVersion:2);
    final legacy=await fineGrant();
    final sessions=LocalOperatorSessions(store:store,namespace:'epoch',farmId:1,deviceId:7,generation:1,clock:()=>syntheticNow);
    await sessions.enrollPersonalCode(old,'1234',authenticatedCredentialVersion:1);
    expect(await sessions.unlockPersonalCode(current,'1234'),isFalse);
    await sessions.enrollPersonalCode(current,'4321',authenticatedCredentialVersion:2);
    expect(await sessions.unlockPersonalCode(old,'1234'),isFalse);
    expect(await sessions.unlockPersonalCode(current,'4321'),isTrue);
    await expectLater(sessions.enrollPersonalCode(legacy,'1234',authenticatedCredentialVersion:1),throwsStateError);
    await expectLater(sessions.enrollPersonalCode(current,'1234',authenticatedCredentialVersion:1),throwsStateError);
  });
  test('real server availability requires correct health body, not a Wi-Fi hint',() async {
    var ok=false,calls=0;final hints=StreamController<bool?>.broadcast(sync:true);
    final c=ServerConnection(baseUrl:Config.apiUrl,client:MockClient((_) async {calls++;return http.Response(ok?'{"status":"ok"}':'{"captive_portal":true}',200);}),interval:const Duration(days:1));
    c.start(networkHints:hints.stream);await c.probe();expect(c.available,isFalse);
    hints.add(true);await c.probe();expect(c.available,isFalse);
    ok=true;await c.probe();expect(c.available,isTrue);expect(calls,greaterThanOrEqualTo(2));
    c.dispose();await hints.close();
  });
  test('a stale health result cannot revive availability after pause',() async {
    final reply=Completer<http.Response>();var calls=0;
    final c=ServerConnection(baseUrl:Config.apiUrl,client:MockClient((_) {calls++;return reply.future;}));
    final first=c.probe(),second=c.probe();c.pause();reply.complete(http.Response('{"status":"ok"}',200));
    await first;await second;expect(calls,1);expect(c.available,isNull);c.dispose();
  });
  test('historical command mapper preserves supported fields and refuses invented accounting',() {
    final command=ClassicTerrainCommand.decode('POST','/depenses/create/',{'lot':7,'categorie':1,'montant':'12.34','note':'fictif','date':'2026-10-12'})!;
    expect(command.kind,'DEPENSE');expect(command.payload,{'lot_ref':{'server_id':7},'categorie_id':1,'montant':'12.34','note':'fictif'});
    expect(ClassicTerrainCommand.decode('POST','/payments/create/',{'client':1,'vente':2,'montant':3}),isNull);
    expect(ClassicTerrainCommand.decode('DELETE','/achats/delete/1/',{}),isNull);
    expect(()=>ClassicTerrainCommand.decode('POST','/depenses/create/',{'lot':7,'montant':1.001}),throwsArgumentError);
    expect(()=>ClassicTerrainCommand.decode('POST','/depenses/create/',{'lot':7,'montant':1,'hidden':true}),throwsArgumentError);
  });
  Future<void> close(UnifiedAccessHarness h,FarmerRuntime runtime) async {
    runtime.dispose();await h.db.close();await h.directory.delete(recursive:true);
  }
  test('online personal code prepares same offline code; failed online auth never falls back',() async {
    final h=UnifiedAccessHarness();await h.start();final runtime=await h.runtime();
    try {
      final api=await runtime.signIn('synthetic','1234');
      expect(api.hasUnifiedOfflineSession,isTrue);expect(runtime.grant!.credentialVersion,1);
      expect(runtime.tablet.selectedName,'synthetic');
      await expectLater(runtime.signIn('synthetic','0000'),throwsA(isA<Exception>()));
      expect(runtime.signedIn,isFalse);
      h.down=true;await expectLater(runtime.signIn('synthetic','1234'),throwsStateError);
    } finally {await close(h,runtime);}
  });
  test('legacy server and unavailable fine issuance preserve authenticated online access only',() async {
    for(final mode in ['legacy','disabled','503']) {
      final h=UnifiedAccessHarness();await h.start();
      h.includeCredentialVersion=mode!='legacy';h.issuanceEnabled=mode!='disabled';h.refuseGrant=mode=='503';
      final runtime=await h.runtime();
      try {
        final api=await runtime.signIn('synthetic','1234');
        expect(runtime.signedIn,isTrue);expect(runtime.prepared,isFalse);
        expect(runtime.warning,contains('Accès en ligne disponible'));
        expect(await api.getDashboard(),{'stock_total':10});
        expect(await h.db.listOutbox(),isEmpty);
        h.down=true;await runtime.connection.probe();
        await expectLater(runtime.signIn('synthetic','1234'),throwsA(anything));
      } finally {await close(h,runtime);}
    }
  });
  test('Unicode species and snapshots survive cold offline login as UTF-8 JSON',() async {
    final h=UnifiedAccessHarness();await h.start();var runtime=await h.runtime();
    const label='Œufs — chèvre 🐐';
    try {
      await h.db.replaceConfirmedCache('species',[{'id':217,'nom':label}]);
      await runtime.signIn('synthetic','1234');
      await h.db.saveScreenSnapshot(userId:2,credentialVersion:1,path:'/dashboard/',payload:{'libelle':label});
      runtime.dispose();await h.db.close();h.db=h.openDatabase();
      h.down=true;await h.controller();runtime=await h.runtime();
      final api=await runtime.signIn('synthetic','1234');
      expect((await api.getEspeces()).single['nom'],label);
      expect((await api.getDashboard())['libelle'],label);
      expect(api.lastReadWasCached,isTrue);
    } finally {await close(h,runtime);}
  });
  test('encrypted views are scoped to user/epoch, reject secrets, and survive reopening',() async {
    final h=UnifiedAccessHarness();await h.start();final runtime=await h.runtime();
    try {
      final api=await runtime.signIn('synthetic','1234');
      expect(await api.getDashboard(),{'stock_total':10});
      expect(await h.db.screenSnapshot(userId:3,credentialVersion:1,path:'/dashboard/'),isNull);
      expect(await h.db.screenSnapshot(userId:2,credentialVersion:2,path:'/dashboard/'),isNull);
      await expectLater(h.db.saveScreenSnapshot(userId:2,credentialVersion:1,path:'/dashboard/',payload:{'refresh':'must-not-store'}),throwsArgumentError);
      h.down=true;await runtime.connection.probe();
      expect(await api.getDashboard(),{'stock_total':10});expect(api.lastReadWasCached,isTrue);
      final bytes=await File('${h.directory.path}/farm.db').readAsBytes();
      expect(utf8.decode(bytes,allowMalformed:true),isNot(contains('stock_total')));
    } finally {await close(h,runtime);}
  });
  test('offline original survives app close, reconnects automatically, and never duplicates effect',() async {
    final h=UnifiedAccessHarness();await h.start();var runtime=await h.runtime();
    try {
      var api=await runtime.signIn('synthetic','1234');
      h.down=true;await runtime.connection.probe();
      await api.createDepense(lotId:7,categorieId:1,montant:12.34,date:h.now,note:'Synthetic offline');
      var rows=await h.db.listOutbox();expect(rows,hasLength(1));
      final id=rows.single.operationId;
      expect(rows.single.businessStatus,'UNREVIEWED');expect(api.operationFeedback('confirmed'),contains('en attente'));
      runtime.dispose();await h.db.close();h.db=h.openDatabase();
      // Reconstruct controllers, encrypted store and personal-code KDF after exit.
      await h.controller();runtime=await h.runtime();
      api=await runtime.signIn('synthetic','1234');
      expect(ApiService.token,isNull);expect(runtime.prepared,isTrue);
      expect((await h.db.listOutbox()).single.operationId,id);
      h.now=h.now.add(const Duration(seconds:20));h.down=false;h.lost=true;
      await runtime.connection.probe();await Future<void>.delayed(Duration.zero);await runtime.tablet.sync!.waitForIdle();
      h.now=h.now.add(const Duration(seconds:30));await runtime.connection.probe();
      await runtime.tablet.sync!.trigger();await runtime.tablet.sync!.waitForIdle();
      rows=await h.db.listOutbox();expect(rows.single.operationId,id);
      expect(h.originals,hasLength(1));expect(h.effects,hasLength(1));expect(rows.single.businessStatus,'CONFIRMED');
    } finally {await close(h,runtime);}
  });
  test('historical online-only mutation stays online and is never falsely queued offline',() async {
    final h=UnifiedAccessHarness();await h.start();final runtime=await h.runtime();
    try {
      await runtime.signIn('synthetic','1234');
      final online=http.Request('PATCH',Uri.parse('${Config.apiUrl}/tasks/1/'))..body=jsonEncode({'status':'DONE','expected_version':1});
      expect((await runtime.request(online)).statusCode,200);
      expect(h.onlineWrites,hasLength(1));expect(await h.db.listOutbox(),isEmpty);
      h.down=true;await runtime.connection.probe();
      final offline=http.Request('PATCH',Uri.parse('${Config.apiUrl}/tasks/1/'))..body=jsonEncode({'status':'DONE','expected_version':1});
      expect((await runtime.request(offline)).statusCode,409);
      expect(h.onlineWrites,hasLength(1));expect(await h.db.listOutbox(),isEmpty);
    } finally {await close(h,runtime);}
  });
  test('known revocation blocks an unlocked personal profile and keeps original conflicts',() async {
    final h=UnifiedAccessHarness();await h.start();final runtime=await h.runtime();
    try {
      final api=await runtime.signIn('synthetic','1234');
      h.down=true;await runtime.connection.probe();
      await api.createDepense(lotId:7,categorieId:1,montant:12.34,date:h.now);
      h.businessState='NEEDS_RECONCILIATION';h.disabled=true;h.down=false;h.now=h.now.add(const Duration(seconds:20));
      await runtime.connection.probe();await Future<void>.delayed(Duration.zero);await runtime.tablet.sync!.waitForIdle();
      expect((await h.db.listOutbox()).single.businessStatus,'NEEDS_RECONCILIATION',reason:'posts=${h.posts}; originals=${h.originals.length}; network=${runtime.tablet.sync!.networkAvailable}; error=${runtime.tablet.sync!.error}');
      expect(runtime.prepared,isFalse);
      await expectLater(runtime.signIn('synthetic','1234'),throwsA(isA<Exception>()));
      expect(h.effects,isEmpty);
    } finally {await close(h,runtime);}
  });
}

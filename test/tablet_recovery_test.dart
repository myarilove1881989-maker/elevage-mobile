import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'foundation_api_test.dart' show TestIdentity,TestSecretStore;
import 'outbox_test.dart' show testOutboxGrant;

void main() {
  late Directory directory;
  late FarmDatabase db;
  late TestSecretStore secrets;
  late TestIdentity identity;
  late FoundationApi api;
  late TabletController tablet;
  late List<OutboxEntry> originals;
  final now=DateTime.utc(2026,10,8);
  var revoked=true,malformed=false,posts=0;
  Completer<void>? hold;
  Map<String,dynamic>? body;
  Map<String,dynamic> receipt(OutboxEntry e)=>{
    'client_operation_id':e.operationId,'author_user_id':e.authorId,
    'transport_status':'SERVER_RECEIVED','business_status':'NEEDS_RECONCILIATION',
    'reason_code':'RECOVERED_REVOKED_DEVICE','received_at':now.toIso8601String(),
    'applied_at':null,'server_entity_id':'','server_version':'',
  };
  TabletController controller()=>TabletController(api:api,secrets:secrets,automaticSyncEnabled:false,
    networkChanges:()=>const Stream<bool?>.empty(),clock:()=>now,
    cacheOpener:({required int farmId,required Uri server}) async=>db);
  setUp(() async {
    revoked=true;malformed=false;posts=0;hold=null;body=null;
    directory=await Directory.systemTemp.createTemp('elevage-recovery-');
    db=FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),List.filled(32,'a1').join()),
      farmId:1,serverNamespace:'recovery-test',clock:()=>now);
    originals=[];
    for(final user in [2,3]) {
      originals.add(await db.enqueue(grant:await testOutboxGrant(user,now),isSessionCurrent:()=>true,
        entityType:'CLIENT',operationType:'CREATE',payload:{'nom':'Auteur $user'},businessOccurredAt:now));
    }
    secrets=TestSecretStore();identity=TestIdentity();
    await secrets.write('tablet_context_${Uri.encodeComponent('https://test.invalid/api')}',jsonEncode({
      'farm_id':1,'device_id':7,'generation':1,'installation_uuid':'test-installation'}));
    api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:identity,secrets:secrets,
      client:MockClient((request) async {
        if(request.url.path=='/api/devices/') return http.Response(jsonEncode([
          {'id':7,'status':revoked?'REVOKED':'ACTIVE','is_primary_writer':!revoked},
          {'id':8,'status':'ACTIVE','is_primary_writer':true},
        ]),200);
        if(request.url.path=='/api/devices/challenge/') return http.Response(jsonEncode({
          'id':'recovery-challenge','device_id':7,'user_id':1,'purpose':'RECOVER',
          'signature_contract':'ELEVAGE-DEVICE-V1'}),201);
        if(request.url.path=='/api/offline/recovery/') {
          posts++;body=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
          if(hold!=null) await hold!.future;
          return http.Response(jsonEncode({'receipts':malformed?[receipt(originals.first),receipt(originals.first)]:
            originals.map(receipt).toList()}),200);
        }
        return http.Response('{}',404);
      }));
    api.personal=OnlineOperatorIdentity(userId:1,farmId:1,role:'OWNER',capabilities:{},access:'synthetic-access',refresh:'synthetic-refresh');
    tablet=controller();await tablet.initialize();
  });
  tearDown(() async {tablet.dispose();api.close();await db.close();await directory.delete(recursive:true);});

  test('explicit recovery keeps both authors and original bytes; revoked context survives restart',() async {
    expect(await tablet.recoverPending('Remplacement matériel décidé'),2);
    expect(posts,1);expect(body!['operations'],originals.map((e)=>e.declaration).toList());
    expect(body!['reason'],'Remplacement matériel décidé');
    expect(utf8.decode(identity.signed!),contains('\nRECOVER\nPOST\n/api/offline/recovery/\n'));
    final rows=await db.listOutbox();
    for(final original in originals) {
      final row=rows.singleWhere((e)=>e.operationId==original.operationId);
      expect(row.declaration,original.declaration);expect(row.authorId,original.authorId);
      expect(row.transportStatus,'SERVER_RECEIVED');expect(row.businessStatus,'NEEDS_RECONCILIATION');
    }
    expect((await db.syncSummary()).conflicts,2);expect((await db.syncSummary()).pending,0);
    tablet.dispose();tablet=controller();await tablet.initialize();
    expect(tablet.knownDeviceRevoked,isTrue);
    await expectLater(tablet.syncOutbox(),throwsStateError);
    await expectLater(tablet.unlockProfile(2,'Jean','123456'),throwsStateError);
    expect(await tablet.recoverPending('Vérification sans nouvelles déclarations'),0);expect(posts,1);
  });

  test('double click has one signed recovery flight',() async {
    hold=Completer<void>();final first=tablet.recoverPending('Ancienne tablette remplacée');
    await expectLater(tablet.recoverPending('Second clic'),throwsStateError);
    hold!.complete();expect(await first,2);expect(posts,1);expect(tablet.recovering,isFalse);
  });

  test('duplicate or missing receipt cannot partially accept originals',() async {
    malformed=true;
    await expectLater(tablet.recoverPending('Transmission à vérifier'),throwsStateError);
    expect((await db.listOutbox()).every((e)=>e.transportStatus=='LOCAL_PENDING'),isTrue);
    expect((await db.syncSummary()).lastSuccess,isNull);
    expect(tablet.knownDeviceRevoked,isTrue);expect(tablet.recovering,isFalse);
  });

  test('active tablet and operator cannot request recovery',() async {
    revoked=false;
    await expectLater(tablet.recoverPending('Appareil toujours actif'),throwsStateError);expect(posts,0);
    api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',capabilities:{},access:'a',refresh:'r');
    await expectLater(tablet.recoverPending('Demande opérateur'),throwsA(isA<FoundationApiException>()));
    expect(posts,0);expect(await db.listOutbox(),hasLength(2));
  });

  test('recovery selection includes blocked originals without changing attempts or declaration',() async {
    await db.leasePending();await db.transportFailure(originals.map((e)=>e.operationId).toList(),code:'HTTP_403',blocked:true);
    final batch=await db.recoveryBatch();expect(batch.map((e)=>e.authorId),[2,3]);
    expect(batch.every((e)=>e.transportStatus=='TRANSPORT_BLOCKED' && e.attemptCount==1),isTrue);
    expect(batch.map((e)=>e.declaration),originals.map((e)=>e.declaration));
    await tablet.recoverPending('Récupération après refus normal');
    expect((await db.listOutbox()).every((e)=>e.attemptCount==1),isTrue);
  });

  test('received declarations awaiting validation are distinct from pending transport',() async {
    await db.acceptReceipts([{...receipt(originals.first),'business_status':'UNREVIEWED','reason_code':''}]);
    final summary=await db.syncSummary();expect(summary.pending,1);expect(summary.awaitingValidation,1);expect(summary.conflicts,0);
    expect((await db.recoveryBatch()).single.operationId,originals.last.operationId);
  });
}

import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/device_identity.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/offline_database.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/sync_coordinator.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'package:app_elevage/screens/supervision_screen.dart';
import 'package:app_elevage/services/supervision_service.dart';
import 'package:app_elevage/services/api_service.dart';

class DelayedGrantStore implements OperatorSecretStore {
  final delegate=const AndroidOperatorSecretStore();
  bool hold=false;
  final started=Completer<void>();
  final release=Completer<void>();
  @override
  Future<String?> read(String key) async {
    if(hold && key.startsWith('offline_grant_')) {
      if(!started.isCompleted) started.complete();
      await release.future;
    }
    return delegate.read(key);
  }
  @override
  Future<void> write(String key,String value)=>delegate.write(key,value);
}

/// Only records bounded stage names, never signatures or private material.
class DiagnosticDeviceIdentity extends AndroidDeviceIdentity {
  final stages=<String>[];
  @override
  Future<Map<String,dynamic>> publicIdentity() async {
    stages.add('IDENTITY_START');
    try {final result=await super.publicIdentity();stages.add('IDENTITY_OK');return result;}
    catch(error) {stages.add('IDENTITY_ERROR_${error.runtimeType}');rethrow;}
  }
  @override
  Future<String> sign(Uint8List message) async {
    stages.add('SIGN_START');
    try {final result=await super.sign(message);stages.add('SIGN_OK');return result;}
    catch(error) {stages.add('SIGN_ERROR_${error.runtimeType}');rethrow;}
  }
}

void main() {
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  String? terrainNamespace;
  void stage(String value) {binding.reportData={'journey_complete':false,'stage':value};}
  testWidgets('Android Keystore encrypted shared cache Jean Paul PIN and restart', (tester) async {
    Future<void> tapVisible(Finder target) async {
      await Scrollable.ensureVisible(tester.element(target),alignment:0.5);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    stage('START');
    final native=AndroidDeviceIdentity();
    final installation=await native.publicIdentity();
    expect(installation['private_key_exportable'],isFalse);
    final serverKey=await Ed25519().newKeyPair();
    final public=await serverKey.extractPublicKey();
    final pem='-----BEGIN PUBLIC KEY-----\n${base64.encode([
      0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00,...public.bytes,
    ])}\n-----END PUBLIC KEY-----';
    var user=1;
    final namespace='https://android-test-${DateTime.now().microsecondsSinceEpoch}.invalid/api';
    terrainNamespace=namespace;
    final secrets=DelayedGrantStore();
    MockClient client()=>MockClient((request) async {
      Map<String,dynamic> response;
      final path=request.url.path;
      if(path.endsWith('/token/')) {
        final credentials=jsonDecode(request.body) as Map;
        user=credentials['username']=='owner'?1:credentials['username']=='Jean'?2:3;
        response={'access':'synthetic-access-$user','refresh':'synthetic-refresh-$user'};
      } else if(path.endsWith('/capabilities/')) {
        response={'user':user,'exploitation':1,'role':user==1?'OWNER':'OPERATEUR',
          'membership':{'id':user,'username':user==2?'Jean':'Paul','version':1},
          'offline_policy_enabled':true,'write_generation':1,
          'primary_device':{'id':7,'installation_uuid':installation['installation_uuid']}};
      } else if(path.endsWith('/devices/')) {
        response={'results':[{'id':7,'installation_uuid':installation['installation_uuid'],
          'status':'ACTIVE','is_primary_writer':true}]};
      } else if(path.endsWith('/challenge/')) {
        final data=jsonDecode(request.body) as Map;
        response={'id':'synthetic-challenge','user_id':user,'device_id':7,
          'purpose':data['purpose'],'signature_contract':'ELEVAGE-DEVICE-V1'};
      } else if(path.endsWith('/offline-authorizations/')) {
        expect(request.headers['X-Elevage-Signature'],isNotEmpty);
        final now=DateTime.now().toUtc();
        final header=base64Url.encode(utf8.encode('{"alg":"EdDSA","kid":"android-test"}')).replaceAll('=','');
        final claims=base64Url.encode(utf8.encode(jsonEncode({'iss':'elevage-offline','aud':'elevage-device',
          'typ':'offline-authorization','jti':'00000000-0000-4000-8000-${user.toString().padLeft(12,'0')}','sub':'$user','membership_id':user,
          'exploitation_id':1,'device_id':7,'rights_version':1,'write_generation':1,
          'capabilities':{'can_create_terrain_operation':true},'iat':now.millisecondsSinceEpoch~/1000,
          'exp':now.add(const Duration(days:3)).millisecondsSinceEpoch~/1000}))).replaceAll('=','');
        final signature=await Ed25519().sign(utf8.encode('$header.$claims'),keyPair:serverKey);
        response={'authorization':'$header.$claims.${base64Url.encode(signature.bytes).replaceAll('=','')}',
          'public_key':pem,'key_id':'android-test'};
      } else if(path.endsWith('/cache-page/')) {
        final collection=request.url.queryParameters['collection'];
        response={'collection':collection,'next_cursor':null,'results':collection=='sales'?[]:[
          {'id':1,'nom':'Fixture partagée','stock':10,if(collection=='tasks')...{'title':'Fixture agenda','assigned_to':null,'version':1,'status':'TODO','report':'','date':'2026-10-07'}},
        ]};
      } else {throw StateError('Unexpected synthetic request $path');}
      return http.Response(jsonEncode(response),200);
    });
    TabletController controller()=>TabletController(api:FoundationApi(baseUrl:namespace,
      deviceIdentity:native,secrets:secrets,client:client()),secrets:secrets,automaticSyncEnabled:false);
    var tablet=controller();
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Test Android hors ligne'))));
    await tablet.signIn('owner','synthetic-password');
    await tablet.preparePrimaryTablet();
    await tablet.signIn('Jean','synthetic-password');
    await tablet.prepareOperator('123456');
    await tablet.refreshCache();
    await tablet.signIn('Paul','synthetic-password');
    await tablet.prepareOperator('654321');
    tablet.api.personal=null; // no server session needed for personal PIN unlock
    await tablet.unlockProfile(2,'Jean','123456');
    await tablet.declare(entityType:'CLIENT',operationType:'CREATE',payload:{'nom':'Déclaration native Jean'},businessOccurredAt:DateTime.now().toUtc());
    expect((await tablet.readPage('lots')).single['data'],containsPair('stock',10));
    await tablet.unlockProfile(3,'Paul','654321');
    await tablet.declare(entityType:'CLIENT',operationType:'CREATE',payload:{'nom':'Déclaration native Paul'},businessOccurredAt:DateTime.now().toUtc());
    expect(tablet.operators!.session!.userId,3);
    final sharedClients=await tablet.readPage('clients');
    expect(sharedClients,hasLength(3));
    expect(sharedClients.map((row)=>(row['data'] as Map)['nom']),containsAll(['Fixture partagée','Déclaration native Jean','Déclaration native Paul']));
    tablet.lock();tablet.api.close();tablet.dispose();
    await closeAndroidFarmDatabase(farmId:1,server:Uri.parse(namespace));
    tablet=controller();
    await tablet.initialize();
    expect(tablet.operators!.session,isNull);
    expect(tablet.profiles.map((p)=>p['display_name']),containsAll(['Jean','Paul']));
    stage('ENCRYPTED_QUEUE_REOPENED');
    await tablet.unlockProfile(2,'Jean','123456');
    expect(tablet.outboxRows.single.authorId,2);
    expect(tablet.outboxRows.single.transportStatus,'LOCAL_PENDING');
    expect((await tablet.readPage('tasks')).single['data'],containsPair('assigned_to',null));
    await expectLater(tablet.unlockProfile(3,'Paul','123456'),throwsStateError);
    expect(tablet.operators!.session,isNull);
    secrets.hold=true;
    final pending=tablet.unlockProfile(2,'Jean','123456');
    final refused=expectLater(pending,throwsStateError);
    await secrets.started.future;
    tablet.lock();
    secrets.release.complete();
    await refused;
    expect(tablet.operators!.session,isNull);
    secrets.hold=false;
    await tester.pumpWidget(MaterialApp(home:OfflineTabletScreen(controller:tablet)));
    await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && find.text('Jean').evaluate().isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(find.text('Jean'),findsOneWidget);
    await tester.tap(find.text('Jean'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last,'123456');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && find.text('Profil ouvert : Jean').evaluate().isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(find.text('Profil ouvert : Jean'),findsOneWidget);
    await tester.scrollUntilVisible(find.text('Stock confirmé : 10'),200,maxScrolls:20,
      scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Stock confirmé : 10'),findsOneWidget);
    await tester.scrollUntilVisible(find.text('Enregistrer un client'),-200,maxScrolls:20,
      scrollable:find.byType(Scrollable).first);
    await tapVisible(find.text('Enregistrer un client'));
    await tester.enterText(find.byType(TextFormField).first,'Client créé sans réseau');
    await tester.tap(find.text('Enregistrer sur la tablette'));
    await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.length<2;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(tablet.outboxRows,hasLength(2));
    expect(tablet.outboxRows.every((row)=>row.authorId==2),isTrue);
    expect((await tablet.readPage('clients')).map((row)=>(row['data'] as Map)['nom']),contains('Client créé sans réseau'));
    stage('NATIVE_CLIENT_SAVED');
    await tester.ensureVisible(find.text('Enregistrer une opération terrain'));
    await tester.tap(find.text('Enregistrer une opération terrain'));
    await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && find.text('Opération réalisée sur le terrain').evaluate().isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    await tester.tap(find.descendant(of:find.byType(AlertDialog),matching:find.byType(DropdownButtonFormField<String>)).first);
    await tester.pumpAndSettle();await tester.tap(find.text('Achat').last);await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<Map<String,dynamic>>).first);
    await tester.pumpAndSettle();await tester.tap(find.text('Fixture partagée').last);await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ACHAT-nom_lot')),'Achat natif test');
    await tester.ensureVisible(find.byKey(const ValueKey('ACHAT-quantite')));
    await tester.enterText(find.byKey(const ValueKey('ACHAT-quantite')),'3');
    await tester.ensureVisible(find.byKey(const ValueKey('ACHAT-prix_unitaire')));
    await tester.enterText(find.byKey(const ValueKey('ACHAT-prix_unitaire')),'13,01');
    await tester.tap(find.text('Conserver sur la tablette'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.length<3;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(tablet.outboxRows,hasLength(3));
    final nativePurchase=tablet.outboxRows.singleWhere((entry)=>entry.declaration['entity_type']=='ACHAT');
    expect(nativePurchase.declaration['payload'],containsPair('prix_total','39.03'));
    expect((await tablet.readPage('lots')).singleWhere((row)=>(row['data'] as Map)['nom']=='Achat natif test')['data'],containsPair('projected_stock',3));
    stage('NATIVE_PURCHASE_SAVED');
    await Scrollable.ensureVisible(tester.element(find.text('Enregistrer une vente ou un encaissement')),
      alignment:0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer une vente ou un encaissement'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && find.text('Vente ou encaissement terrain').evaluate().isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(find.text('Vente ou encaissement terrain'),findsOneWidget);
    await tapVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).first);
    await tester.pumpAndSettle();await tester.tap(find.text('Client créé sans réseau').last);await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).last);
    await tapVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).last);
    await tester.pumpAndSettle();await tester.tap(find.text('Achat natif test').last);await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('sale-quantity')));
    await tester.enterText(find.byKey(const ValueKey('sale-quantity')),'1');
    await tester.ensureVisible(find.byKey(const ValueKey('sale-price')));
    await tester.enterText(find.byKey(const ValueKey('sale-price')),'13,01');
    await tester.tap(find.text('Conserver sur la tablette'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.length<4;attempt++) {await tester.pump(const Duration(milliseconds:100));}
    expect(tablet.outboxRows,hasLength(4));
    final nativeSale=tablet.outboxRows.singleWhere((entry)=>entry.declaration['entity_type']=='VENTE_ANIMAUX');
    expect(nativeSale.declaration['dependencies'],contains(nativePurchase.operationId));
    expect((await tablet.readPage('lots')).singleWhere((row)=>(row['data'] as Map)['nom']=='Achat natif test')['data'],containsPair('projected_stock',2));
    stage('NATIVE_SALE_SAVED');
    await Scrollable.ensureVisible(tester.element(find.text('Enregistrer une vente ou un encaissement')),
      alignment:0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer une vente ou un encaissement'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && find.text('Vente ou encaissement terrain').evaluate().isEmpty;attempt++) {await tester.pump(const Duration(milliseconds:100));}
    expect(find.text('Vente ou encaissement terrain'),findsOneWidget);
    await tapVisible(find.descendant(of:find.byType(AlertDialog),matching:find.byType(DropdownButtonFormField<String>)).first);
    await tester.pumpAndSettle();await tester.tap(find.text('Encaissement reçu').last);await tester.pumpAndSettle();
    await tapVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).first);
    await tester.pumpAndSettle();await tester.tap(find.text('Client créé sans réseau').last);await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).last);
    await tapVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).last);
    await tester.pumpAndSettle();await tester.tap(find.textContaining('Vente animaux ').last);await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cash-amount')));
    await tester.enterText(find.byKey(const ValueKey('cash-amount')),'50,00');
    await tester.tap(find.text('Conserver sur la tablette'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.length<5;attempt++) {await tester.pump(const Duration(milliseconds:100));}
    expect(tablet.outboxRows,hasLength(5));
    final nativeCash=tablet.outboxRows.singleWhere((entry)=>entry.declaration['entity_type']=='ENCAISSEMENT');
    expect(nativeCash.declaration['payload'],containsPair('montant_recu','50.00'));
    expect(nativeCash.declaration['dependencies'],contains(nativeSale.operationId));
    expect(tablet.outboxRows.every((entry)=>entry.authorId==2),isTrue);
    stage('NATIVE_CASH_SAVED');
    await Scrollable.ensureVisible(tester.element(find.text('Enregistrer une vente ou un encaissement')),
      alignment:0.5);
    await tester.pumpAndSettle();await tester.tap(find.text('Enregistrer une vente ou un encaissement'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && find.text('Vente ou encaissement terrain').evaluate().isEmpty;attempt++) {await tester.pump(const Duration(milliseconds:100));}
    expect(find.text('Vente ou encaissement terrain'),findsOneWidget);
    await tapVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).first);
    await tester.pumpAndSettle();await tester.tap(find.text('Client créé sans réseau').last);await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).last);
    await tester.pumpAndSettle();await tapVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).last);
    await tester.pumpAndSettle();await tester.tap(find.text('Achat natif test').last);await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('sale-quantity')));
    await tester.enterText(find.byKey(const ValueKey('sale-quantity')),'3');await tester.pumpAndSettle();
    expect(find.textContaining('Alerte : cette vente dépasse le stock projeté'),findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('sale-price')));
    await tester.enterText(find.byKey(const ValueKey('sale-price')),'13,01');await tester.pumpAndSettle();
    await tester.tap(find.text('Conserver sur la tablette'));await tester.pumpAndSettle();
    expect(find.text('Indiquez le motif de la survente.'),findsOneWidget);expect(tablet.outboxRows,hasLength(5));
    await tester.ensureVisible(find.byKey(const ValueKey('sale-note')));
    await tester.enterText(find.byKey(const ValueKey('sale-note')),'Vente effectuée, inventaire à rapprocher.');await tester.pumpAndSettle();
    await tester.tap(find.text('Conserver sur la tablette'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.length<6;attempt++) {await tester.pump(const Duration(milliseconds:100));}
    expect(tablet.outboxRows,hasLength(6));
    expect(tablet.outboxRows.singleWhere((entry)=>(entry.declaration['payload'] as Map)['note']=='Vente effectuée, inventaire à rapprocher.').authorId,2);
    final oversold=(await tablet.readPage('lots')).singleWhere((row)=>(row['data'] as Map)['nom']=='Achat natif test')['data'] as Map;
    expect(oversold['stock'],0);expect(oversold['projected_stock'],-1);
    stage('NATIVE_OVERSALE_WITH_REASON_SAVED');
    await tester.tap(find.byTooltip('Verrouiller / changer d’opérateur'));
    await tester.pumpAndSettle();
    expect(find.text('Profil ouvert : Jean'),findsNothing);
    await tester.scrollUntilVisible(find.text('Jean'),-200,maxScrolls:20,
      scrollable:find.byType(Scrollable).first);
    expect(find.text('Jean'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await closeAndroidFarmDatabase(farmId:1,server:Uri.parse(namespace));
    binding.reportData={'journey_complete':true,'stage':'COMPLETE','own_pending_operations':6,
      'original_author_user_id':2,'oversale_note_preserved':true};
    debugPrint('NATIVE_JOURNEY_COMPLETE own_operations=6 author=2');
  },timeout:const Timeout(Duration(minutes:5)));

  testWidgets('Android owner supervision preserves Jean original and requires an explicit reason', (tester) async {
    expect(binding.reportData?['journey_complete'],isTrue);
    binding.reportData={...binding.reportData??{},'stage':'OWNER_SUPERVISION_START','owner_supervision_complete':false};
    const operation='d4608303-99bc-43ef-a938-b51087277e65';
    final now=DateTime.now().toUtc().toIso8601String();
    bool cancelled=false;Map<String,dynamic>? saved;
    Map<String,dynamic> declaration()=>{
      'operation_uuid':operation,'entity_type':'CLIENT','original_author_id':2,'device_id':7,
      'business_occurred_at':now,'received_at':now,'original_payload':{'nom':'Client original Jean, conservé'},
      'decision_version':cancelled?1:0,'decisions':[],'decisions_next_page':null,
      'receipt':{'business_status':cancelled?'NOT_APPLIED':'NEEDS_RECONCILIATION','applied_at':null,
        'reason_text':cancelled?saved!['reason']:'','reason_code':cancelled?'CANCELLED_BY_DECISION':'AUTHOR_RIGHTS_CHANGED'},
    };
    final previousToken=ApiService.token,previousGlobal=globalToken;
    ApiService.token='synthetic-native-owner-session';globalToken=null;
    final api=ApiService(client:MockClient((request) async {
      dynamic response;
      final path=request.url.path;
      if(path.endsWith('/capabilities/')) {
        response={'user':1,'exploitation':1,'role':'OWNER','capabilities':{'can_reconcile':true},
          'membership':{'username':'Propriétaire'}};
      } else if(path.endsWith('/memberships/')) {
        response=[{'user':1,'username':'Propriétaire'},{'user':2,'username':'Jean'},{'user':3,'username':'Paul'}];
      } else if(path.endsWith('/audit-events/')) {
        response={'count':cancelled?1:0,'next':null,'results':cancelled?[{
          'exploitation_id':1,'actor_user_id':2,'decision_actor_id':1,'operation_id':operation,
          'action':'CANCEL','occurred_at':now,'reason_text':saved!['reason'],
          'before_data':{'nom':'Client original Jean, conservé'},'after_data':{'nom':'Client original Jean, conservé'},
        }]:[]};
      } else if(request.method=='POST') {
        expect(request.headers['authorization'],contains('synthetic-native-owner-session'));
        saved=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
        expect(saved!['action'],'CANCEL');expect(saved!['expected_decision_version'],0);
        expect(saved!['payload'],isEmpty);expect(saved!['reason'],'Doublon vérifié avec Jean sur tablette.');
        cancelled=true;response={'decision_uuid':saved!['decision_uuid'],'decision_actor_id':1,
          'original_author_id':2,'receipt':declaration()['receipt']};
      } else if(path.endsWith('/reconciliation/')) {
        response={'count':cancelled?0:1,'results':cancelled?[]:[declaration()],'next':null};
      } else if(path.endsWith('/$operation/')) {
        response=declaration();
      } else {throw StateError('Unexpected native supervision request $path');}
      return http.Response(jsonEncode(response),200,headers:{'content-type':'application/json'});
    }));
    addTearDown(() {api.close();ApiService.token=previousToken;globalToken=previousGlobal;});
    Future<void> tapVisible(Finder target) async {
      await Scrollable.ensureVisible(tester.element(target),alignment:0.5);
      await tester.pumpAndSettle();await tester.tap(target);await tester.pumpAndSettle();
    }
    await tester.pumpWidget(MaterialApp(home:SupervisionScreen(service:SupervisionService(api:api))));
    await tester.pumpAndSettle();await tapVisible(find.text('Client'));
    expect(find.text('Auteur original : Jean'),findsOneWidget);
    await tapVisible(find.text('Prendre une décision avec motif'));
    await tapVisible(find.descendant(of:find.byType(AlertDialog),matching:find.byType(DropdownButtonFormField<String>)));
    await tester.tap(find.text('Annuler sans supprimer').last);await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer la décision'));await tester.pumpAndSettle();
    expect(find.text('Indiquez le motif de votre décision.'),findsOneWidget);expect(saved,isNull);
    await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('decision-reason'))),alignment:0.5);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('decision-reason')),'Doublon vérifié avec Jean sur tablette.');
    await tester.pumpAndSettle();await tester.tap(find.text('Enregistrer la décision'));await tester.pumpAndSettle();
    expect(cancelled,isTrue);expect(find.text('Auteur original : Jean'),findsOneWidget);
    expect(find.text('Non appliqué'),findsOneWidget);
    expect(find.text('Nom : Client original Jean, conservé'),findsWidgets);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    binding.reportData={...binding.reportData??{},'stage':'COMPLETE','owner_supervision_complete':true};
    debugPrint('NATIVE_OWNER_SUPERVISION_COMPLETE original_author=2 decision_actor=1');
  },timeout:const Timeout(Duration(minutes:5)));

  testWidgets('Android startup sync transmits Jean and Paul while PIN and JWT sessions remain closed',(tester) async {
    expect(binding.reportData?['owner_supervision_complete'],isTrue);
    binding.reportData={...binding.reportData??{},'stage':'SHARED_SYNC_START','shared_sync_complete':false};
    final namespace=terrainNamespace!;
    const secrets=AndroidOperatorSecretStore();
    final native=DiagnosticDeviceIdentity();
    final network=StreamController<bool?>.broadcast(sync:true);
    final requestStages=<String>[];
    var bearerSeen=false;
    final signedProofs=<bool>[];
    final server=<String,Map<String,dynamic>>{};int posts=0;
    MockClient transportClient()=>MockClient((request) async {
      requestStages.add(request.url.path.endsWith('/transport-challenge/')?'CHALLENGE':'SIGNED_REQUEST');
      // Background callbacks may run while tester.pump is guarded. Record the
      // evidence here and assert in the test's awaited control flow instead.
      bearerSeen|=request.headers.keys.any((key)=>key.toLowerCase()=='authorization');
      final data=jsonDecode(request.body) as Map;
      if(request.url.path.endsWith('/transport-challenge/')) {
        return http.Response(jsonEncode({'id':'00000000-0000-4000-8000-000000000099','device_id':7,
          'exploitation_id':1,'device_generation':1,'purpose':data['purpose'],'method':'POST',
          'path':data['purpose']=='RECEIVE'?'/api/offline/submissions/':'/api/offline/submissions/status/',
          'signature_contract':'ELEVAGE-DEVICE-TRANSPORT-V1'}),201);
      }
      signedProofs.add((request.headers['X-Elevage-Signature']??'').isNotEmpty);
      if(data['operations'] is List) {
        posts++;
        for(final value in data['operations'] as List) {
          final operation=Map<String,dynamic>.from(value as Map);
          server.putIfAbsent(operation['client_operation_id'] as String,()=>operation);
        }
      }
      final ids=data['operation_ids'] is List?List<String>.from(data['operation_ids'] as List):server.keys.toList();
      return http.Response(jsonEncode({'receipts':[for(final id in ids) {
        'client_operation_id':id,'transport_status':'SERVER_RECEIVED','business_status':'UNREVIEWED',
        'author_user_id':server[id]!['author_user_id'],'received_at':DateTime.now().toUtc().toIso8601String(),
        'applied_at':null,'server_entity_id':'','server_version':'',
      }]}),200);
    });
    final tablet=TabletController(api:FoundationApi(baseUrl:namespace,deviceIdentity:native,secrets:secrets),
      secrets:secrets,transportClient:transportClient,networkChanges:()=>network.stream);
    await tablet.initialize();
    network.add(true);
    final manual=tablet.syncOutbox();
    expect(tablet.api.personal,isNull);expect(tablet.operators!.session,isNull);
    for(var i=0;i<300 && tablet.sync!.summary.pending>0;i++) {await tester.pump(const Duration(milliseconds:100));}
    await manual;
    final diagnosticRows=await (tablet.cache! as OutboxStore).listOutbox();
    debugPrint('NATIVE_SHARED_SYNC_DIAGNOSTIC identity=${native.stages} requests=$requestStages '
      'states=${diagnosticRows.map((row)=>row.transportStatus).toList()} '
      'codes=${diagnosticRows.map((row)=>row.lastError).toSet()} busy=${tablet.sync!.busy} '
      'error=${tablet.sync!.error!=null}');
    expect(server,hasLength(7));expect(posts,1);
    expect(bearerSeen,isFalse);expect(signedProofs,isNotEmpty);
    expect(signedProofs.every((valid)=>valid),isTrue);
    expect(server.values.where((value)=>value['author_user_id']==2),hasLength(6));
    expect(server.values.where((value)=>value['author_user_id']==3),hasLength(1));
    expect(tablet.sync!.summary.pending,0);expect(tablet.sync!.summary.lastSuccess,isNotNull);
    final originals=await (tablet.cache! as OutboxStore).listOutbox();
    expect(originals.every((entry)=>entry.transportStatus=='SERVER_RECEIVED'),isTrue);
    expect(tablet.operators!.session,isNull);expect(tablet.api.personal,isNull);
    await tester.pumpWidget(MaterialApp(home:OfflineTabletScreen(controller:tablet)));
    final manualButton=find.widgetWithText(OutlinedButton,'Synchroniser maintenant');
    for(var i=0;i<300 && (manualButton.evaluate().isEmpty ||
        tester.widget<OutlinedButton>(manualButton).onPressed==null);i++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(manualButton,findsOneWidget);
    expect(find.text('0 déclarations en attente • 0 conflits à rapprocher'),findsOneWidget);
    await tester.tap(manualButton);await tester.pumpAndSettle();
    for(var i=0;i<300 && tablet.sync!.busy;i++) {await tester.pump(const Duration(milliseconds:100));}
    expect(tablet.sync!.busy,isFalse);expect(tablet.sync!.error,isNull);expect(posts,1);
    expect(bearerSeen,isFalse);expect(signedProofs.every((valid)=>valid),isTrue);
    expect(tablet.operators!.session,isNull);expect(tablet.api.personal,isNull);
    // Also exercise the real Android connectivity channel; no HTTP business call uses it here.
    final nativeState=await androidNetworkChanges().first.timeout(const Duration(seconds:10));
    expect(nativeState,isA<bool>());
    await tester.pumpWidget(const SizedBox.shrink());await network.close();
    await closeAndroidFarmDatabase(farmId:1,server:Uri.parse(namespace));
    binding.reportData={...binding.reportData??{},'stage':'COMPLETE','shared_sync_complete':true};
    debugPrint('NATIVE_SHARED_SYNC_COMPLETE jean=6 paul=1 personal_session=closed');
  },timeout:const Timeout(Duration(minutes:5)));
}

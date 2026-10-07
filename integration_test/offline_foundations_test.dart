import 'dart:convert';
import 'dart:async';
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
import 'package:app_elevage/screens/offline_tablet_screen.dart';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android Keystore encrypted shared cache Jean Paul PIN and restart', (tester) async {
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
        response={'collection':collection,'next_cursor':null,'results':[
          {'id':1,'nom':'Fixture partagée','stock':10,if(collection=='tasks')...{'title':'Fixture agenda','assigned_to':null,'version':1,'status':'TODO','report':'','date':'2026-10-07'}},
        ]};
      } else {throw StateError('Unexpected synthetic request $path');}
      return http.Response(jsonEncode(response),200);
    });
    TabletController controller()=>TabletController(api:FoundationApi(baseUrl:namespace,
      deviceIdentity:native,secrets:secrets,client:client()),secrets:secrets);
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
    for(var attempt=0;attempt<300 && find.text('Stock confirmé : 10').evaluate().isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(find.text('Profil ouvert : Jean'),findsOneWidget);
    expect(find.text('Stock confirmé : 10'),findsOneWidget);
    await tester.tap(find.text('Enregistrer un client'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first,'Client créé sans réseau');
    await tester.tap(find.text('Enregistrer sur la tablette'));
    await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.length<2;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(tablet.outboxRows,hasLength(2));
    expect(tablet.outboxRows.every((row)=>row.authorId==2),isTrue);
    expect((await tablet.readPage('clients')).map((row)=>(row['data'] as Map)['nom']),contains('Client créé sans réseau'));
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
    await tester.tap(find.byTooltip('Verrouiller / changer d’opérateur'));
    await tester.pumpAndSettle();
    expect(find.text('Profil ouvert : Jean'),findsNothing);
    expect(find.text('Jean'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await closeAndroidFarmDatabase(farmId:1,server:Uri.parse(namespace));
  },timeout:const Timeout(Duration(minutes:5)));
}

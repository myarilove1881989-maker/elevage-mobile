import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app_elevage/offline/device_identity.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/offline_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/tablet_controller.dart';

void main() {
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native encrypted queue applies real PostgreSQL business once with original authors',(tester) async {
    const base='https://10.0.2.2:9443/api';
    const certificate=String.fromEnvironment('NATIVE_TEST_CA');
    expect(certificate,isNotEmpty);
    IOClient client() {
      final context=SecurityContext(withTrustedRoots:false)
        ..setTrustedCertificatesBytes(base64Decode(certificate));
      return IOClient(HttpClient(context:context));
    }
    const secrets=AndroidOperatorSecretStore();
    final native=AndroidDeviceIdentity();
    TabletController controller()=>TabletController(api:FoundationApi(baseUrl:base,
      deviceIdentity:native,secrets:secrets,client:client()),secrets:secrets,
      transportClient:client,automaticSyncEnabled:false);
    void stage(String value) {binding.reportData={'real_business_complete':false,'stage':value};}
    stage('REAL_LOGIN');
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Validation métier isolée'))));
    var tablet=controller();
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    final fixture=await tablet.api.request('GET','/test-fixture/state/');
    await tablet.preparePrimaryTablet();
    expect(tablet.farmId,fixture['farm']);
    await tablet.signIn('native-jean','SyntheticNativeI-2026-only');
    await tablet.prepareOperator('123456');await tablet.refreshCache();
    await tablet.signIn('native-paul','SyntheticNativeI-2026-only');
    await tablet.prepareOperator('654321');
    tablet.api.personal=null;
    stage('REAL_OFFLINE_JEAN');
    await tablet.unlockProfile(fixture['jean'] as int,'Jean','123456');
    expect(tablet.api.personal,isNull);
    final clientJean=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
      payload:{'nom':'Client réel Jean'},businessOccurredAt:DateTime.now().toUtc());
    final purchase=await tablet.declare(entityType:'ACHAT',operationType:'CREATE',
      payload:{'nom_lot':'Lot natif acheté','espece':fixture['species'],'quantite':20,
        'prix_total':'20000.00','prix_unitaire':'1000.00'},businessOccurredAt:DateTime.now().toUtc());
    final sale=await tablet.declare(entityType:'VENTE_ANIMAUX',operationType:'CREATE',
      payload:{'lot_ref':{'local_uuid':purchase.declaration['local_entity_id']},
        'client_ref':{'local_uuid':clientJean.declaration['local_entity_id']},
        'quantite':3,'prix_unitaire':'10000.00'},
      dependencies:[purchase.operationId,clientJean.operationId],businessOccurredAt:DateTime.now().toUtc());
    final cash=await tablet.declare(entityType:'ENCAISSEMENT',operationType:'CREATE',
      payload:{'client_ref':{'local_uuid':clientJean.declaration['local_entity_id']},
        'vente_ref':{'local_uuid':sale.declaration['local_entity_id']},'montant_recu':'50000.00','mode':'ESPECES'},
      dependencies:[clientJean.operationId,sale.operationId],businessOccurredAt:DateTime.now().toUtc());
    final eggs=await tablet.declare(entityType:'VENTE_OEUFS',operationType:'CREATE',
      payload:{'lot_ref':{'server_id':fixture['egg_lot']},
        'client_ref':{'local_uuid':clientJean.declaration['local_entity_id']},
        'conditionnement':'UNITE','nombre_conditionnements':4,'prix_unitaire_conditionnement':'0.13'},
      dependencies:[clientJean.operationId],businessOccurredAt:DateTime.parse(fixture['egg_sale_at'] as String));
    final task=await tablet.declare(entityType:'TASK',operationType:'UPDATE',
      payload:{'task_id':fixture['task'],'status':'DONE','report':'Compte rendu réel Jean'},
      expectedServerVersion:'1',businessOccurredAt:DateTime.now().toUtc());
    tablet.lock();
    await tablet.unlockProfile(fixture['paul'] as int,'Paul','654321');
    final clientPaul=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
      payload:{'nom':'Client réel Paul'},businessOccurredAt:DateTime.now().toUtc());
    final originals=[clientJean,purchase,sale,cash,eggs,task,clientPaul];
    tablet.lock();
    stage('REAL_ENCRYPTED_RESTART');
    tablet.api.close();tablet.dispose();
    await closeAndroidFarmDatabase(farmId:fixture['farm'] as int,server:Uri.parse(base));
    tablet=controller();await tablet.initialize();
    expect(tablet.api.personal,isNull);expect(tablet.operators!.session,isNull);
    final queue=tablet.cache! as OutboxStore;
    expect((await queue.listOutbox()).length,7);
    for(final original in originals) {
      expect((await queue.listOutbox()).singleWhere((e)=>e.operationId==original.operationId).declaration,original.declaration);
    }
    stage('REAL_DEVICE_SYNC');
    await Future.wait([tablet.syncOutbox(),tablet.syncOutbox()]);
    final rows=await queue.listOutbox();
    expect(rows.every((e)=>e.transportStatus=='SERVER_RECEIVED'),isTrue);
    expect(rows.singleWhere((e)=>e.operationId==cash.operationId).businessStatus,'NEEDS_RECONCILIATION');
    expect(rows.where((e)=>e.businessStatus=='CONFIRMED'),hasLength(6));
    expect(tablet.api.personal,isNull);expect(tablet.operators!.session,isNull);
    await tablet.syncOutbox();
    stage('REAL_SERVER_VERIFICATION');
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    final verified=await tablet.api.request('POST','/test-fixture/verify/',
      data:{'operation_ids':originals.map((e)=>e.operationId).toList()});
    expect(verified['verified'],isTrue);expect(verified['device_bearer'],isFalse);
    expect(verified['fifo'],[2,2]);expect(verified['stock'],17);
    expect(verified['cash_received'],'50000.00');expect(verified['cash_allocated'],'30000.00');
    expect(verified['cash_review'],'20000.00');
    binding.reportData={'real_business_complete':true,'stage':'COMPLETE','originals':7,
      'jean':6,'paul':1,'server_verified':true,'fifo_verified':true,'cash_verified':true};
    debugPrint('REAL_NATIVE_BUSINESS_COMPLETE originals=7 jean=6 paul=1 server_verified=true');
    tablet.api.close();tablet.dispose();
    await closeAndroidFarmDatabase(farmId:fixture['farm'] as int,server:Uri.parse(base));
  });
}

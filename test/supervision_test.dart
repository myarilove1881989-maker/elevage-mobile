import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/device_identity.dart';
import 'package:app_elevage/screens/supervision_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/supervision_service.dart';

const operation='d4608303-99bc-43ef-a938-b51087277e65';
class NativeIdentityFake implements DeviceIdentity {
  Uint8List? message;
  @override
  Future<Map<String,dynamic>> publicIdentity() async=>{'installation_uuid':'fixture-installation'};
  @override
  Future<String> sign(Uint8List value) async {message=value;return 'fixture-signature';}
}
Map<String,dynamic> capabilities({bool owner=true})=>{
  'user':owner?1:2,'exploitation':1,'role':owner?'OWNER':'OPERATEUR',
  'capabilities':{'can_reconcile':true},'membership':{'username':owner?'Propriétaire':'Jean'},
  'primary_device':{'id':7,'installation_uuid':'fixture-installation'},
};
Map<String,dynamic> declaration({bool cancelled=false})=>{
  'operation_uuid':operation,'entity_type':'CLIENT','original_author_id':2,'device_id':7,
  'business_occurred_at':'2026-10-06T08:00:00Z','received_at':'2026-10-07T08:00:00Z',
  'original_payload':{'nom':'Client original, inchangé','telephone':'123'},'decision_version':cancelled?1:0,
  'receipt':{'business_status':cancelled?'NOT_APPLIED':'NEEDS_RECONCILIATION','applied_at':null,'reason_text':'','reason_code':'AUTHOR_RIGHTS_CHANGED'},
  'decisions':[],
};
http.Response response(dynamic data)=>http.Response(jsonEncode(data),200,headers:{'content-type':'application/json'});

void main() {
  setUp(() {ApiService.token='synthetic-owner-session';globalToken=null;});
  tearDown(() {ApiService.token=null;globalToken=null;});

  test('lost decision response is retried with identical UUID and payload and one effect',() async {
    final effects=<String,Map<String,dynamic>>{},bodies=<String>[];
    final api=ApiService(client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) {return response(capabilities());}
      bodies.add(request.body);
      final data=jsonDecode(request.body) as Map;
      expect(request.headers['Authorization'],'Bearer synthetic-owner-session');
      expect(data.keys, isNot(contains('access')));
      final id=data['decision_uuid'] as String;
      effects.putIfAbsent(id,()=>{'decision_uuid':id,'decision_actor_id':1,'original_author_id':2});
      if(bodies.length==1) {throw http.ClientException('synthetic lost response');}
      return response(effects[id]);
    }));
    final service=SupervisionService(api:api);await service.initialize();
    final payload={'nom':'Jean, client'};
    final pending=PendingReconciliationDecision(operationId:operation,version:0,action:'CORRECTION',reason:'Pièce vérifiée',payload:payload);
    payload['nom']='Changed after capture';
    await expectLater(service.decide(pending),throwsA(isA<ApiConnectionException>()));
    expect(bodies,hasLength(1));
    final receipt=await service.decide(pending);
    expect(bodies[0],bodies[1]);expect(effects,hasLength(1));expect(receipt['original_author_id'],2);
    expect((jsonDecode(bodies.last) as Map)['payload'],{'nom':'Jean, client'});
    api.close();
  });

  test('a changed personal session cannot publish an earlier supervision response',() async {
    final ready=Completer<void>(),release=Completer<void>();
    final api=ApiService(client:MockClient((_) async {ready.complete();await release.future;return response(capabilities());}));
    final service=SupervisionService(api:api);
    final future=service.initialize();final rejected=expectLater(future,throwsStateError);
    await ready.future;ApiService.token='another-personal-session';release.complete();await rejected;
    expect(service.capabilities,isNull);api.close();
  });

  test('owner activity rejects a foreign farm response and paginates its own endpoint',() async {
    final api=ApiService(client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) {return response(capabilities());}
      expect(request.url.queryParameters['page'],'2');expect(request.url.queryParameters['actor_user_id'],'2');
      return response({'results':[{'exploitation_id':2}],'count':1,'next':null});
    }));
    final service=SupervisionService(api:api);await service.initialize();
    await expectLater(service.activity(page:2,author:2),throwsStateError);api.close();
  });

  test('object timeline requests server-derived related history for the selected operation',() async {
    final api=ApiService(client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) {return response(capabilities());}
      expect(request.url.queryParameters['operation_id'],operation);
      expect(request.url.queryParameters['include_related_object'],'true');
      return response({'results':[{'exploitation_id':1,'source':'ONLINE'}],'count':1,'next':null});
    }));
    final service=SupervisionService(api:api);await service.initialize();
    expect((await service.activity(operationId:operation,includeRelatedObject:true))['count'],1);
    await expectLater(service.activity(includeRelatedObject:true),throwsArgumentError);
    api.close();
  });

  test('delegated decision signs actual body and path with primary installation',() async {
    final identity=NativeIdentityFake();int decisions=0;String? actualPath;
    final pending=PendingReconciliationDecision(operationId:operation,version:0,action:'CANCEL',reason:'Doublon physique vérifié.');
    final api=ApiService(client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) {return response(capabilities(owner:false));}
      if(request.url.path.endsWith('/challenge/')) {return response({'id':'fixture-challenge','device_id':7,'user_id':2,'purpose':'WRITE','signature_contract':'ELEVAGE-DEVICE-V1'});}
      decisions++;actualPath=request.url.path;expect(request.body,pending.encoded);expect(request.headers['X-Elevage-Signature'],'fixture-signature');
      return response({'decision_uuid':pending.data['decision_uuid'],'decision_actor_id':2,'original_author_id':2});
    }));
    final service=SupervisionService(api:api,identity:identity);await service.initialize();await service.decide(pending);
    expect(decisions,1);expect(utf8.decode(identity.message!),contains('\nPOST\n$actualPath\n'));
    api.close();
  });

  test('challenge for another user cannot authorize a delegated decision',() async {
    int decisions=0;
    final api=ApiService(client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) {return response(capabilities(owner:false));}
      if(request.url.path.endsWith('/challenge/')) {return response({'id':'wrong-user','device_id':7,'user_id':999,'purpose':'WRITE','signature_contract':'ELEVAGE-DEVICE-V1'});}
      decisions++;return response({});
    }));
    final service=SupervisionService(api:api,identity:NativeIdentityFake());await service.initialize();
    await expectLater(service.decide(PendingReconciliationDecision(operationId:operation,version:0,action:'CANCEL',reason:'Motif vérifié')),throwsStateError);
    expect(decisions,0);api.close();
  });

  testWidgets('narrow owner screen requires motive and keeps Jean as original author', (tester) async {
    Future<void> tapVisible(Finder target) async {
      await Scrollable.ensureVisible(tester.element(target),alignment:0.5);
      await tester.pumpAndSettle();await tester.tap(target);await tester.pumpAndSettle();
    }
    tester.view.physicalSize=const Size(320,568);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    bool cancelled=false;Map<String,dynamic>? saved;
    final api=ApiService(client:MockClient((request) async {
      final path=request.url.path;
      if(path.endsWith('/capabilities/')) {return response(capabilities());}
      if(path.endsWith('/memberships/')) {return response([{'user':1,'username':'Propriétaire'},{'user':2,'username':'Jean'}]);}
      if(path.endsWith('/audit-events/')) {return response({'count':0,'results':[],'next':null});}
      if(path.endsWith('/reconciliation/')) {return response({'count':1,'results':[declaration(cancelled:cancelled)],'next':null});}
      if(request.method=='POST') {
        saved=Map<String,dynamic>.from(jsonDecode(request.body) as Map);cancelled=true;
        return response({'decision_uuid':saved!['decision_uuid'],'decision_actor_id':1,'original_author_id':2});
      }
      return response(declaration(cancelled:cancelled));
    }));
    final service=SupervisionService(api:api);
    await tester.pumpWidget(MaterialApp(home:SupervisionScreen(service:service)));await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    await tester.tap(find.text('Client'));await tester.pumpAndSettle();
    expect(find.text('Auteur original : Jean'),findsOneWidget);
    await tester.ensureVisible(find.text('Prendre une décision avec motif'));
    await tester.tap(find.text('Prendre une décision avec motif'));await tester.pumpAndSettle();
    await tapVisible(find.descendant(of:find.byType(AlertDialog),matching:find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();await tester.tap(find.text('Annuler sans supprimer').last);await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer la décision'));await tester.pumpAndSettle();
    expect(find.text('Indiquez le motif de votre décision.'),findsOneWidget);expect(saved,isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('decision-reason')));
    await tester.enterText(find.byKey(const ValueKey('decision-reason')),'Doublon reçu vérifié avec Jean.');
    await tester.tap(find.text('Enregistrer la décision'));await tester.pumpAndSettle();
    expect(saved!['action'],'CANCEL');expect(saved!['reason'],'Doublon reçu vérifié avec Jean.');
    expect(find.text('Auteur original : Jean'),findsOneWidget);expect(find.text('Non appliqué'),findsOneWidget);
    expect(find.text('Nom : Client original, inchangé'),findsOneWidget);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());api.close();
  });
}

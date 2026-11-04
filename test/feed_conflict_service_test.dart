import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/supervision_service.dart';
import 'supervision_test.dart' show operation, capabilities, declaration, response;

void main() {
  setUp(() {ApiService.token='synthetic-owner-session';globalToken=null;});
  tearDown(() {ApiService.token=null;globalToken=null;});
  test('feed conflict cancellation retries the same decision and verifies its receipt',() async {
    final bodies=<String>[];
    var wrong=false;
    final api=ApiService(client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) {return response(capabilities());}
      if(request.method=='GET') {return response({...declaration(),'reconciliation_mode':'FEED_CANCEL_ONLY'});}
      bodies.add(request.body);
      if(bodies.length==1) {throw http.ClientException('lost response');}
      final data=jsonDecode(request.body) as Map;
      return response({'decision_uuid':wrong?'another':data['decision_uuid'],'decision_actor_id':1});
    }));
    final service=SupervisionService(api:api);await service.initialize();
    final decision=PendingReconciliationDecision(operationId:operation,version:0,action:'CANCEL',reason:'Stock épuisé, opération non appliquée.');
    await expectLater(service.closeFeedConflict(decision),throwsA(isA<ApiConnectionException>()));
    await service.closeFeedConflict(decision);
    expect(bodies[0],bodies[1]);
    wrong=true;await expectLater(service.closeFeedConflict(decision),throwsStateError);
    final correction=PendingReconciliationDecision(operationId:operation,version:0,action:'APPLY_ORIGINAL',reason:'Interdit');
    await expectLater(service.closeFeedConflict(correction),throwsStateError);
    expect(bodies,hasLength(3));api.close();
  });
  test('delegate cannot close a feed conflict',() async {
    var posts=0;
    final api=ApiService(client:MockClient((request) async {
      if(request.method=='POST')posts++;
      return response(capabilities(owner:false));
    }));
    final service=SupervisionService(api:api);await service.initialize();
    final decision=PendingReconciliationDecision(operationId:operation,version:0,action:'CANCEL',reason:'Interdit');
    await expectLater(service.closeFeedConflict(decision),throwsStateError);
    expect(posts,0);api.close();
  });
}

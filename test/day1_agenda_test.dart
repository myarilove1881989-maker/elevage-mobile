import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/farm_session.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/offline/sync_state.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';

void main() {
  testWidgets('Agenda is visible to owner with planning permission and opens real action',(tester) async {
    var opened=false;
    final rights=PermissionContract.decode({'version':1,'user':1,'exploitation':1,'role':'OWNER',
      'rights_version':1,'permissions':['finance.read','agenda.read','agenda.plan']},
      userId:1,farmId:1,role:'OWNER',rightsVersion:1);
    final session=FarmSession(userId:1,farmId:1,role:'OWNER',origin:SessionOrigin.personalHttp,
      network:NetworkState.available,sync:const SyncSummary(),permissions:rights);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FarmNavigation(session:session,
      actions:{FarmDestination.agenda:()=>opened=true}))));
    expect(find.text('Agenda'),findsOneWidget);await tester.tap(find.text('Agenda'));expect(opened,true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FarmNavigation(actions:{FarmDestination.agenda:(){}}))));
    expect(find.text('Agenda'),findsNothing);
  });
  test('task creation sends selected operator and date',() async {
    final api=ApiService(client:MockClient((request) async {
      expect(request.method,'POST');expect(request.url.path.endsWith('/tasks/'),true);
      expect(jsonDecode(request.body),{'title':'Pesée','date':'2026-11-01','assigned_to':23});
      return http.Response('{}',201);
    }));
    try {await api.createTask('Pesée',DateTime(2026,11,1),assignedTo:23);} finally {api.close();}
  });
}

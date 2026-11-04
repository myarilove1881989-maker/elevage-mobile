@TestOn('browser')
library;

import 'package:test/test.dart' show TestOn;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/terrain_entry_gate.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'auth_connection_test.dart' show AuthApiFake,authApp;
import 'egg_production_test.dart' show EggApiFake,eggTestApp;

class OwnerEggReadApi extends EggApiFake {
  @override Future<dynamic> get(String endpoint) async {
    if(endpoint!='/me/capabilities/') throw StateError('Unmocked endpoint forbidden');
    return {'user':1,'exploitation':1,'role':'OWNER','offline_policy_enabled':true,'membership':{'version':1},
      'permission_contract':{'version':1,'user':1,'exploitation':1,'role':'OWNER','rights_version':1,
        'permissions':['finance.read','egg_collections.read']}};
  }
}

class WebQualificationApi extends AuthApiFake {
  String role='OWNER'; int? assigned; String? assignedTitle; bool denyMembers=false;
  @override Future<bool> probeServer() async=>true;
  @override Future<bool> login(String username,String password) async {
    ApiService.token='synthetic-web-qualification';globalToken=ApiService.token;return true;
  }
  @override Future<dynamic> get(String endpoint) async {
    if(endpoint=='/farm-profile/') return {'id':1,'nom':'Ferme qualification'};
    if(endpoint=='/memberships/') {
      if(denyMembers) throw const ApiHttpException(403,'denied');
      return [
        {'id':5,'user':23,'username':'qa_operator','role':'OPERATEUR','exploitation':1,'is_active':true},
        {'id':6,'user':24,'username':'foreign_operator','role':'OPERATEUR','exploitation':2,'is_active':true},
        {'id':7,'user':25,'username':'inactive_operator','role':'OPERATEUR','exploitation':1,'is_active':false},
      ];
    }
    if(endpoint!='/me/capabilities/') throw StateError('No unmocked endpoint allowed: $endpoint');
    return {'user':1,'exploitation':1,'role':role,'offline_policy_enabled':true,'membership':{'version':1},
      'permission_contract':{'version':1,'user':1,'exploitation':1,'role':role,'rights_version':1,
        'permissions':role=='OWNER'?['finance.read','history.read','agenda.read','agenda.plan','users.manage']:['finance.read','egg_collections.read','egg_collections.update']}};
  }
  @override Future<void> createTask(String title,DateTime date,{int? assignedTo}) async {
    assigned=assignedTo;assignedTitle=title;
  }
}

void main() {
  setUp((){SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-web-qualification';globalToken=ApiService.token;});
  tearDown((){ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();});
  testWidgets('Chrome owner opens Agenda and assigns a task only to active same-farm operator',(tester) async {
    expect(kIsWeb,true);
    tester.view.physicalSize=const Size(1440,1100);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final api=WebQualificationApi();
    await tester.pumpWidget(authApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu).first);await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('navigation-agenda')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('navigation-agenda')));await tester.pumpAndSettle();
    await tester.tap(find.text('Attribuer une tâche'));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agendaTaskTitle')),'Contrôle de ponte J1');
    await tester.tap(find.byKey(const Key('agendaAssignee')));await tester.pumpAndSettle();
    expect(find.text('foreign_operator'),findsNothing);expect(find.text('inactive_operator'),findsNothing);
    await tester.tap(find.text('qa_operator').last);await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'Ajouter'));await tester.pumpAndSettle();
    expect(api.assigned,23);expect(api.assignedTitle,'Contrôle de ponte J1');expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('Chrome owner consults egg collections without business write controls',(tester) async {
    expect(kIsWeb,true);
    final api=OwnerEggReadApi()..sampleCollections=[{'id':90,'lot':1,
      'collecte_at':DateTime.now().toIso8601String(),'nombre_collecte':120,
      'nombre_commercialisable':117,'nombre_casses':3,'nombre_declasses':0,'nombre_consommes_donnes':0}];
    await tester.pumpWidget(eggTestApp(api));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('4 alvéoles'),250,scrollable:find.byType(Scrollable).first);
    expect(find.textContaining('117'),findsWidgets);
    expect(find.byKey(const ValueKey('edit-egg-90')),findsNothing);
    expect(find.text('Nouvelle collecte'),findsNothing);
    expect(api.collectionsCreated,0);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('Chrome operator login is refused by current policy',(tester) async {
    expect(kIsWeb,true);final api=WebQualificationApi()..role='OPERATEUR';
    await tester.pumpWidget(authApp(LoginScreen(apiService:api)));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0),'qa_operator');
    await tester.enterText(find.byType(TextField).at(1),'synthetic-only');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton,'Se connecter'));
    await tester.tap(find.widgetWithText(ElevatedButton,'Se connecter'));await tester.pumpAndSettle();
    expect(find.textContaining('L’espace opérateur nécessite'),findsOneWidget);
    expect(find.byType(DashboardScreen),findsNothing);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  test('Chrome owner cannot enter egg correction under current contract',() async {
    expect(kIsWeb,true);final api=WebQualificationApi();
    final access=await TerrainEntryAccess.read(api,{'egg_collections.update'});
    expect(access.rights.allows('egg_collections.update'),false);
    expect(access.message,contains('La saisie terrain est réservée'));
    api.close();
  });
}

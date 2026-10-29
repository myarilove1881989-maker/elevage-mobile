import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'package:app_elevage/screens/initial_password_screen.dart';
import 'package:app_elevage/screens/supervision_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/initial_password.dart';
import 'package:app_elevage/services/supervision_service.dart';
import 'package:app_elevage/widgets/operation_status.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;

class DisplayTablet extends TabletController {
  DisplayTablet({required super.api,required super.secrets});
  @override
  Future<void> initialize() async {}
}
class FailedRoleApi extends ApiService {
  bool fail=true;
  @override
  Future<dynamic> get(String endpoint) async {
    if(fail) throw const ApiHttpException(404,'sensitive response must stay hidden');
    return {'role':'OWNER'};
  }
}
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-owner';globalToken=null;});
  tearDown(() {ApiService.token=null;globalToken=null;});
  FoundationApi makeApi(TestSecretStore store,Future<http.Response> Function(http.Request) handler) =>
    FoundationApi(baseUrl:Config.apiUrl,deviceIdentity:TestIdentity(),secrets:store,client:MockClient(handler));
  test('HTTP failure preserves fixed step and status without server payload',() async {
    final api=makeApi(TestSecretStore(),(_) async=>http.Response('{"detail":"secret-test-payload"}',404));
    try {await api.logIn('synthetic','synthetic');fail('must reject');}
    on FoundationApiException catch(error) {
      final text=tabletErrorMessage(error);
      expect(text,contains('Connexion personnelle'));expect(text,contains('HTTP 404'));
      expect(text,isNot(contains('secret-test-payload')));
    }
    api.close();
  });
  testWidgets('failed role is visible and retry restores owner menu',(tester) async {
    final api=FailedRoleApi();
    await tester.pumpWidget(MaterialApp(home:SettingsScreen(apiService:api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 404'),findsOneWidget);
    expect(find.textContaining('sensitive response'),findsNothing);
    expect(find.text('Création des utilisateurs'),findsNothing);
    api.fail=false;await tester.tap(find.text('Réessayer'));await tester.pumpAndSettle();
    expect(find.text('Création des utilisateurs'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('supervision identifies failed membership request',(tester) async {
    final api=ApiService(client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) return http.Response(jsonEncode({'role':'OWNER','user':1,'exploitation':1}),200);
      return http.Response('{"detail":"must not display"}',404);
    }));
    await tester.pumpWidget(MaterialApp(home:SupervisionScreen(service:SupervisionService(api:api))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chargement des utilisateurs'),findsOneWidget);
    expect(find.textContaining('HTTP 404'),findsOneWidget);
    expect(find.textContaining('must not display'),findsNothing);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('offline enable requires explicit owner confirmation, cancellation sends nothing',(tester) async {
    var writes=0;
    final store=TestSecretStore();
    final api=makeApi(store,(request) async {
      expect(request.url.path,endsWith('/offline-policy/enable/'));
      writes++;return http.Response('{"offline_policy_enabled":true}',200);
    });
    api.personal=OnlineOperatorIdentity(userId:1,farmId:1,role:'OWNER',capabilities:{},access:'synthetic',refresh:'synthetic');
    final tablet=DisplayTablet(api:api,secrets:store)..farmId=1..deviceId=7;
    await tester.pumpWidget(MaterialApp(home:OfflineTabletScreen(controller:tablet)));
    await tester.pumpAndSettle();
    final enable=find.text('Activer le parcours hors ligne');
    await tester.scrollUntilVisible(enable, 250, scrollable:find.byType(Scrollable).first);await tester.tap(enable);await tester.pumpAndSettle();
    expect(writes,0);await tester.tap(find.text('Annuler'));await tester.pumpAndSettle();expect(writes,0);
    await tester.tap(enable);await tester.pumpAndSettle();await tester.tap(find.text('Activer'));await tester.pumpAndSettle();
    expect(writes,1);expect(tablet.offlinePolicyEnabled,isTrue);
    await tester.drag(find.byType(Scrollable).first,const Offset(0,1500));await tester.pumpAndSettle();
    expect(find.text('Activation hors ligne confirmée par le serveur.'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('operator cannot activate policy even by direct controller call',() async {
    var writes=0;final store=TestSecretStore();
    final api=makeApi(store,(_) async {writes++;return http.Response('{}',200);});
    api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',capabilities:{},access:'synthetic',refresh:'synthetic');
    final tablet=DisplayTablet(api:api,secrets:store)..farmId=1..deviceId=7;
    await expectLater(tablet.enableOfflinePolicy(),throwsA(isA<FoundationApiException>().having((e)=>e.status,'status',403)));
    expect(writes,0);tablet.dispose();api.close();
  });
  testWidgets('operator sign-in confirms success and explicitly opens online space without preparing a tablet',(tester) async {
    var opens=0,requests=0;
    final store=TestSecretStore();
    final api=makeApi(store,(request) async {
      requests++;
      if(request.url.path.endsWith('/token/')) {
        return http.Response('{"access":"synthetic-personal","refresh":"synthetic-refresh"}',200);
      }
      expect(request.url.path,endsWith('/me/capabilities/'));
      return http.Response(jsonEncode({'user':2,'exploitation':1,'role':'OPERATEUR',
        'offline_policy_enabled':false}),200);
    });
    final tablet=DisplayTablet(api:api,secrets:store);
    await tester.pumpWidget(MaterialApp(home:OfflineTabletScreen(controller:tablet,
      onOpenOnline:(access,username) async {
        expect(access,'synthetic-personal');expect(username,'synthetic');opens++;
      })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0),'synthetic');
    await tester.enterText(find.byType(TextField).at(1),'1234');
    await tester.ensureVisible(find.text('Me connecter'));
    await tester.tap(find.text('Me connecter'));await tester.pumpAndSettle();
    expect(find.textContaining('Connexion réussie.'),findsOneWidget);
    expect(find.text('Préparer mon accès par PIN'),findsNothing);
    expect(tablet.deviceId,isNull);expect(opens,0);
    expect(ApiService.token,'synthetic-owner');
    await tester.ensureVisible(find.text('Ouvrir mon espace en ligne'));
    await tester.tap(find.text('Ouvrir mon espace en ligne'));await tester.pumpAndSettle();
    expect(opens,1);expect(requests,2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('initial operator password accepts four characters and rejects three',(tester) async {
    var changes=0;
    await tester.pumpWidget(MaterialApp(home:InitialPasswordScreen(
      changeToken:'synthetic-limited',onChange:(token,password) async {
        expect(password,'4321');changes++;
      })));
    await tester.enterText(find.byType(TextField).at(0),'123');
    await tester.enterText(find.byType(TextField).at(1),'123');
    await tester.tap(find.text('Enregistrer mon code'));await tester.pumpAndSettle();
    expect(changes,0);expect(find.textContaining('Utilisez au moins 4'),findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0),'4321');
    await tester.enterText(find.byType(TextField).at(1),'4321');
    await tester.tap(find.text('Enregistrer mon code'));await tester.pumpAndSettle();
    expect(changes,1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tablet initial password flow uses personal API and requires explicit relogin',(tester) async {
    var changes=0,logins=0;final store=TestSecretStore();
    final api=makeApi(store,(request) async {
      expect(request.headers['Authorization'],isNull);
      if(request.url.path.endsWith('/token/')) {logins++;return http.Response('{"password_change_required":true,"change_token":"synthetic-limited"}',200);}
      expect(request.url.path,endsWith('/password/change-initial/'));changes++;return http.Response('{}',200);
    });
    final tablet=DisplayTablet(api:api,secrets:store);
    await tester.pumpWidget(MaterialApp(home:OfflineTabletScreen(controller:tablet)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Me connecter'));await tester.tap(find.text('Me connecter'));await tester.pumpAndSettle();
    expect(find.text('Choisir votre code personnel'),findsOneWidget);
    final fields=find.byType(TextField);
    await tester.enterText(fields.at(0),'Synthetic-Personal-492!');await tester.enterText(fields.at(1),'Synthetic-Personal-492!');
    await tester.tap(find.text('Enregistrer mon code'));await tester.pumpAndSettle();
    expect(changes,1);expect(logins,1);expect(api.personal,isNull);expect(ApiService.token,'synthetic-owner');
    expect(find.textContaining('Reconnectez votre compte personnel'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

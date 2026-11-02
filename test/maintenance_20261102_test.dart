import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'package:app_elevage/widgets/mutation_refresh.dart';
import 'auth_connection_test.dart' show AuthApiFake, authApp;

class PendingLoginApi extends AuthApiFake {
  int submissions=0;
  final result=Completer<bool>();
  @override Future<bool> login(String user,String password) {submissions++; return result.future;}
}
class RefreshProbe extends StatefulWidget {
  const RefreshProbe({super.key,required this.read});
  final VoidCallback read;
  @override State<RefreshProbe> createState()=>_RefreshProbeState();
}
class _RefreshProbeState extends State<RefreshProbe> with MutationRefresh<RefreshProbe> {
  @override Future<void> refreshAfterMutation() async {markDataFresh();widget.read();}
  @override Widget build(BuildContext context)=>Scaffold(body:TextButton(
    onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const Scaffold(body:Text('Formulaire')))),
    child:const Text('Ouvrir')));
}
void main() {
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  testWidgets('Enter submits once and preserves error feedback',(tester) async {
    final api=PendingLoginApi();
    await tester.pumpWidget(authApp(LoginScreen(apiService:api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0),'synthetic');
    await tester.enterText(find.byType(TextField).at(1),'synthetic-password');
    final password=tester.widget<TextField>(find.byType(TextField).at(1));
    expect(password.textInputAction,TextInputAction.done);
    password.onSubmitted!('synthetic-password');
    password.onSubmitted!('synthetic-password');
    await tester.pump();expect(api.submissions,1);
    api.result.complete(false);await tester.pumpAndSettle();
    expect(find.text('Identifiants invalides'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('sidebar retains billing and removes only dashboard entry',(tester) async {
    var billing=0;
    await tester.pumpWidget(MaterialApp(locale:const Locale('fr'),supportedLocales:const [Locale('fr'),Locale('en')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],home:Scaffold(body:FarmNavigation(actions:{
      FarmDestination.dashboard:(){},FarmDestination.billing:()=>billing++,FarmDestination.lots:(){}}))));
    expect(find.text('Tableau de bord'),findsNothing);
    expect(find.text('Lots'),findsOneWidget);
    await tester.tap(find.text('Facturation'));expect(billing,1);
  });
  testWidgets('writes coalesce and hidden views refresh only after returning',(tester) async {
    var reads=0;
    await tester.pumpWidget(MaterialApp(locale:const Locale('fr'),supportedLocales:const [Locale('fr'),Locale('en')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],navigatorObservers:[businessRouteObserver],home:RefreshProbe(read:()=>reads++)));
    ApiService.businessChanges.value++;ApiService.businessChanges.value++;
    await tester.pump(const Duration(milliseconds:150));expect(reads,1);
    await tester.tap(find.text('Ouvrir'));await tester.pumpAndSettle();
    ApiService.businessChanges.value++;await tester.pump(const Duration(milliseconds:150));expect(reads,1);
    Navigator.of(tester.element(find.text('Formulaire'))).pop();
    await tester.pumpAndSettle();expect(reads,2);
    await tester.pumpWidget(const SizedBox());
  });
  test('only successful mutations notify, reads and failures never do',() async {
    ApiService.token='synthetic';
    final api=ApiService(client:MockClient((request) async =>http.Response('{}',request.method=='DELETE'?403:200)));
    final before=ApiService.businessChanges.value;
    await api.get('/lots/');expect(ApiService.businessChanges.value,before);
    await api.post('/clients/create/',{'nom':'synthetic'});expect(ApiService.businessChanges.value,before+1);
    await expectLater(api.deleteDepense(1),throwsA(isA<ApiHttpException>()));
    expect(ApiService.businessChanges.value,before+1);api.close();ApiService.token=null;
  });
}

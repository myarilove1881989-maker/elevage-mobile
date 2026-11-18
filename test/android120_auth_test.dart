import 'dart:async';
import 'dart:convert';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:app_elevage/widgets/farm_login_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryTokens implements TokenStore, RefreshTokenStore {
  String? access='old', refresh='refresh';
  @override Future<void> saveToken(String value) async {access=value;}
  @override Future<String?> getToken() async => access;
  @override Future<void> clearToken() async {access=null;refresh=null;}
  @override Future<void> saveRefreshToken(String value) async {refresh=value;}
  @override Future<String?> getRefreshToken() async => refresh;
}
class SlowBody extends http.BaseClient {
  int calls=0;
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds:60));
    return http.StreamedResponse(Stream<List<int>>.fromFuture(() async {
      await Future<void>.delayed(const Duration(milliseconds:60));
      return utf8.encode('{}');
    }()),200,request:request);
  }
}
void main(){
  setUp(() {SharedPreferences.setMockInitialValues({});ApiService.token='old';globalToken='old';ApiService.farmerSession=false;});
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.farmerSession=false;});
  test('two simultaneous rejected reads share one refresh and preserve identity',() async {
    var refreshes=0,reads=0;
    final store=MemoryTokens();
    final api=ApiService(tokenStore:store,client:MockClient((r) async {
      if(r.url.path.endsWith('/token/refresh/')){
        refreshes++;await Future<void>.delayed(const Duration(milliseconds:20));
        return http.Response('{"access":"new","refresh":"rotated"}',200);
      }
      reads++;return http.Response(r.headers['Authorization']=='Bearer new'?'{}':'{}',r.headers['Authorization']=='Bearer new'?200:401);
    }));
    final identity=ApiService.sessionIdentity;
    await Future.wait([api.get('/me/'),api.get('/me/')]);
    expect(refreshes,1);expect(reads,4);expect(ApiService.sessionIdentity,identity);
    expect(store.access,'new');expect(store.refresh,'rotated');api.close();
  });
  test('a rejected business write is never replayed',() async {
    var calls=0;
    final api=ApiService(tokenStore:MemoryTokens(),client:MockClient((r)async{calls++;return http.Response('{}',401);}));
    await expectLater(api.patch('/lots/1/',{'name':'synthetic'}),throwsA(isA<ApiHttpException>()));
    expect(calls,1);api.close();
  });
  test('timeout after headers has one total deadline and no replay',()async{
    final transport=SlowBody();final api=ApiService(tokenStore:MemoryTokens(),client:transport,requestTimeout:const Duration(milliseconds:100));
    await expectLater(api.patch('/lots/1/',{'name':'synthetic'}),throwsA(isA<ApiConnectionException>().having((e)=>e.failure,'failure',ApiConnectionFailure.timeout)));
    expect(transport.calls,1);api.close();
  });
  test('farmer sessions never use online renewal',()async{
    ApiService.farmerSession=true;var calls=0;
    final api=ApiService(tokenStore:MemoryTokens(),client:MockClient((r)async{calls++;return http.Response('{}',401);}));
    await expectLater(api.get('/me/'),throwsA(isA<ApiHttpException>()));expect(calls,1);api.close();
  });
  test('rejected refresh expires the session once for simultaneous reads',()async{
    final count=ApiService.sessionExpired.value;
    final api=ApiService(tokenStore:MemoryTokens(),client:MockClient((r)async=>http.Response('{}',401)));
    await Future.wait([for(var i=0;i<2;i++) api.get('/me/').then((_)=>null,onError:(_)=>null)]);
    expect(ApiService.token,isNull);expect(ApiService.sessionExpired.value,count+1);api.close();
  });
  testWidgets('five published animals render and reduced motion stays still',(tester)async{
    for(final animal in FarmAnimal.values){
      await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(disableAnimations:true),child:FarmLoginLoading(key:ValueKey(animal),active:true,chooseAnimal:()=>animal))));
      await tester.pump(const Duration(milliseconds:301));
      expect(find.byKey(const Key('farm-login-loading')),findsOneWidget);
      expect(tester.hasRunningAnimations,isFalse);expect(tester.takeException(),isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

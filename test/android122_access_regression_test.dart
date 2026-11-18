import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/farmer_runtime.dart';
import 'package:app_elevage/screens/farmer_access_screen.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'unified_access_harness.dart';
import 'production_tracking_test.dart' show testApp;

class Access122Harness extends UnifiedAccessHarness {
  String? contextDefect;
  bool featureForbidden=false, featureUnauthorized=false, loseNetworkOnForbidden=false;
  final featureReads=<String>[];
  @override Map<String,dynamic> capabilities(int user) {
    final caps=super.capabilities(user);
    switch(contextDefect) {
      case 'farm':caps['exploitation']=2;break;
      case 'device':caps['primary_device']={'id':8,'installation_uuid':'other-installation'};break;
      case 'generation':caps['write_generation']=2;break;
      case 'credential':caps['credential_version']=2;break;
      case 'rights':caps['membership']={...caps['membership'] as Map,'version':2};break;
    }
    return caps;
  }
  Future<http.Response> read(http.Request request) async {
    featureReads.add(request.url.path);
    if(down) throw http.ClientException('Synthetic offline');
    final p=request.url.path;
    if(p.endsWith('/optional/')) {
      if(loseNetworkOnForbidden)down=true;
      return http.Response('{"detail":"Forbidden feature"}',featureUnauthorized?401:403);
    }
    if(p.endsWith('/tasks/'))return http.Response('[]',codes.contains('agenda.read')?200:403);
    if(p.endsWith('/dashboard/'))return http.Response('{"kpis":{"stock":0,"chiffre_affaires":0,"depenses":0,"marge":0}}',200);
    if(p.endsWith('/clients/total-dettes/'))return http.Response('{"total_dettes":0.0}',200);
    if(p.endsWith('/farm-profile/'))return http.Response('{"id":1,"nom":"Ferme de qualification"}',200,headers:{'content-type':'application/json; charset=utf-8'});
    return http.Response('[]',200);
  }
  Future<FarmerRuntime> open() => runtime(onlineClient:MockClient(read));
}
Future<void> cleanup(Access122Harness h,FarmerRuntime runtime)async{
  runtime.dispose();await h.db.close();
  final target=await h.directory.resolveSymbolicLinks(),temp=await Directory.systemTemp.resolveSymbolicLinks();
  expect(target.startsWith('$temp${Platform.pathSeparator}elevage-seven-day-'),isTrue);
  await h.directory.delete(recursive:true);
}
Future<void> settle(WidgetTester t)async{
  for(var i=0;i<35;i++){
    await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
    await t.pump(const Duration(milliseconds:100));
  }
}
void main(){
  setUp((){SharedPreferences.setMockInitialValues({});tz.initializeTimeZones();ApiService.token=null;globalToken=null;ApiService.farmerSession=false;ApiService.clearLocalPresentationIdentity();});
  tearDown((){ApiService.token=null;globalToken=null;ApiService.farmerSession=false;ApiService.clearLocalPresentationIdentity();});

  for(final agenda in [false,true])testWidgets('real dashboard host ${agenda?'with':'without'} agenda permission survives online and cold offline login',(t)async{
    final h=Access122Harness();if(agenda)h.codes.add('agenda.read');
    late FarmerRuntime runtime;late FarmerApiService api;
    await t.runAsync(()async{await h.start();runtime=await h.open();api=await runtime.signIn('synthetic','1234');});
    try{
      await t.pumpWidget(testApp(FarmerSessionHost(runtime:runtime,api:api)));await settle(t);
      expect(runtime.signedIn,isTrue);expect(find.byType(LoginScreen),findsNothing);
      expect(h.featureReads.any((p)=>p.endsWith('/tasks/')),agenda);
      expect(find.byKey(const Key('dashboard-agenda-unavailable')),agenda?findsNothing:findsOneWidget);
      expect(t.takeException(),isNull);
      // Recreate the runtime after a full UI close. Stored grant/code/cache remain.
      await t.pumpWidget(const SizedBox());
      await t.runAsync(()async{h.down=true;runtime=await h.open();api=await runtime.signIn('synthetic','1234');});
      await t.pumpWidget(testApp(FarmerSessionHost(runtime:runtime,api:api)));await settle(t);
      expect(runtime.signedIn,isTrue);expect(runtime.prepared,isTrue);expect(find.byType(LoginScreen),findsNothing);
      expect(t.takeException(),isNull);
    }finally{await t.pumpWidget(const SizedBox());await t.runAsync(()=>cleanup(h,runtime));}
  });

  test('optional403 stays403 and cannot block a valid signed local profile',()async{
    final h=Access122Harness();await h.start();final runtime=await h.open();
    try{
      final api=await runtime.signIn('synthetic','1234');
      await expectLater(api.get('/optional/'),throwsA(isA<ApiHttpException>().having((e)=>e.status,'status',403)));
      expect(runtime.signedIn,isTrue);expect(runtime.prepared,isTrue);
      expect(h.secrets.values.values, isNot(contains('blocked')));
      runtime.lock();h.down=true;await runtime.signIn('synthetic','1234');expect(runtime.prepared,isTrue);
    }finally{await cleanup(h,runtime);}
  });
  test('optional403 with lost recheck network never grants the feature or revokes valid offline preparation',()async{
    final h=Access122Harness();await h.start();final runtime=await h.open();
    try{
      final api=await runtime.signIn('synthetic','1234');h.loseNetworkOnForbidden=true;
      await expectLater(api.get('/optional/'),throwsA(isA<ApiHttpException>().having((e)=>e.status,'status',403)));
      expect(runtime.signedIn,isTrue);
      runtime.lock();await runtime.signIn('synthetic','1234');expect(runtime.prepared,isTrue);
    }finally{await cleanup(h,runtime);}
  });
  test('true401 invalidates the personal session and does not fall back offline',()async{
    final h=Access122Harness();await h.start();final runtime=await h.open();
    try{
      final api=await runtime.signIn('synthetic','1234');h.featureUnauthorized=true;
      await expectLater(api.get('/optional/'),throwsA(anything));expect(runtime.signedIn,isFalse);
      h.down=true;await expectLater(runtime.signIn('synthetic','1234'),throwsA(anything));
    }finally{await cleanup(h,runtime);}
  });
  for(final defect in ['disabled','farm','device','generation','credential','rights'])test('403 recheck refuses actual $defect change and preserves offline security marker',()async{
    final h=Access122Harness();await h.start();final runtime=await h.open();
    try{
      final api=await runtime.signIn('synthetic','1234');
      if(defect=='disabled'){h.disabled=true;}else{h.contextDefect=defect;}
      await expectLater(api.get('/optional/'),throwsA(anything));expect(runtime.signedIn,isFalse);
      h.down=true;await expectLater(runtime.signIn('synthetic','1234'),throwsA(anything));
      expect(h.secrets.values.values,contains('blocked'));
    }finally{await cleanup(h,runtime);}
  });
}

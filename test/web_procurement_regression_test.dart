import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/widgets/feed_supply_fields.dart';
import 'package:app_elevage/widgets/vaccine_supply_fields.dart';
import 'package:app_elevage/theme/terre_et_or_theme.dart';
import 'online_expense_form_test.dart' show OnlineExpenseServer,selectExpense;
import 'production_tracking_test.dart' show testApp;
import 'feed_purchase_form_test.dart' show fillFeed;
import 'vaccine_form_test.dart' show reveal;

Future<void> fillVaccine(WidgetTester tester) async {
  await selectExpense(tester);
  for(final entry in {'vaccine-product':'Vaccin test','vaccine-species':'Poulet'}.entries) {
    await reveal(tester,entry.key);await tester.tap(find.byKey(Key(entry.key)));await tester.pumpAndSettle();
    await tester.tap(find.text(entry.value).last);await tester.pumpAndSettle();
  }
  for(final entry in {'vaccine-count':'2','vaccine-doses':'20','vaccine-batch':'SYNTHETIC','vaccine-expiry':'2030-11-30'}.entries) {
    await reveal(tester,entry.key);await tester.enterText(find.byKey(Key(entry.key)),entry.value);
  }
  await reveal(tester,'expense-submit');
}

void main() {
  setUp((){tzdata.initializeTimeZones();SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-employee';globalToken=null;});
  tearDown((){ApiService.token=null;globalToken=null;});
  for(final vaccine in [false,true]) {
    testWidgets('${vaccine?'vaccine':'feed'} missing accounting amount reveals validation without posting',(tester) async {
      final server=OnlineExpenseServer()..feed=!vaccine..vaccine=vaccine;
      await tester.pumpWidget(testApp(AddDepenseScreen(apiService:server.api)));await tester.pumpAndSettle();
      if(vaccine) {await fillVaccine(tester);} else {await fillFeed(tester);}
      await reveal(tester,'expense-amount');await tester.enterText(find.byKey(const Key('expense-amount')),'');
      await reveal(tester,'expense-submit');await tester.tap(find.byKey(const Key('expense-submit')));await tester.pumpAndSettle();
      expect(server.posts,0);expect(find.byKey(const Key('expense-error')),findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('expense-error'))).dy,lessThan(tester.view.physicalSize.height));
      expect(tester.widget<Text>(find.byKey(const Key('expense-error'))).data,contains('lot comptable'));
      await tester.pumpWidget(const SizedBox());server.api.close();
    });
    for(final status in [400,403,500]) {
      testWidgets('${vaccine?'vaccine':'feed'} explicit $status versus uncertain response',(tester) async {
        final server=OnlineExpenseServer()..feed=!vaccine..vaccine=vaccine..refusePost=true..refusalStatus=status;
        await tester.pumpWidget(testApp(AddDepenseScreen(apiService:server.api)));await tester.pumpAndSettle();
        if(vaccine) {await fillVaccine(tester);} else {await fillFeed(tester);}
        await tester.tap(find.byKey(const Key('expense-submit')));await tester.pumpAndSettle();
        expect(server.posts,1);
        expect(find.byKey(const Key('micro-confirmation')),findsNothing);
        final original={...server.saved!};
        if(status==500) {
          await reveal(tester,'feed-retry');
          expect(find.byKey(const Key('feed-retry')),findsOneWidget);
          await reveal(tester,'expense-submit');
          expect(tester.widget<FilledButton>(find.byKey(const Key('expense-submit'))).onPressed,isNull);
          server.refusalStatus=403;await reveal(tester,'feed-retry');await tester.tap(find.byKey(const Key('feed-retry')));await tester.pumpAndSettle();
          expect(server.posts,2);expect(server.saved,original);
          await reveal(tester,'feed-retry');expect(find.byKey(const Key('feed-retry')),findsOneWidget);
          server.refusePost=false;await tester.tap(find.byKey(const Key('feed-retry')));
        } else {
          await reveal(tester,'expense-error');
          expect(tester.widget<Text>(find.byKey(const Key('expense-error'))).data,contains('Achat refusé par le serveur ($status)'));
          expect(find.byKey(const Key('feed-retry')),findsNothing);
          await reveal(tester,'expense-submit');
          expect(tester.widget<FilledButton>(find.byKey(const Key('expense-submit'))).onPressed,isNotNull);
          server.refusePost=false;await reveal(tester,'expense-submit');await tester.tap(find.byKey(const Key('expense-submit')));
        }
        await tester.pumpAndSettle();expect(server.posts,status==500?3:2);expect(server.saved,original);
        await reveal(tester,'expense-status');
        expect(find.byKey(const Key('feed-retry')),findsNothing);
        expect(tester.widget<Text>(find.byKey(const Key('expense-status'))).data,contains('confirmés'));
        await tester.pumpWidget(const SizedBox());server.api.close();
      });
    }
  }
  for(final width in [320.0,360.0,768.0,1440.0]) {
    for(final scale in [1.0,1.5]) {
      testWidgets('supply layout $width text $scale',(tester) async {
        tester.view.physicalSize=Size(width,1100);tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        final feed=FeedSupplyDraft()..species=4;
        final vaccine=VaccineSupplyDraft()..species=4;
        final catalog={'products':<dynamic>[], 'species':[{'id':4,'nom':'Poulet'}], 'lots':<dynamic>[]};
        await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Theme(data:terreEtOrTheme(context),child:MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:Scaffold(body:SingleChildScrollView(child:Column(children:[FeedSupplyFields(draft:feed,catalog:catalog,editable:true),VaccineSupplyFields(draft:vaccine,catalog:catalog,editable:true)]))))))));
        await tester.pumpAndSettle();
        for(final keys in [['feed-product','feed-species'],['feed-species','feed-lot-4'],['feed-lot-4','feed-unit'],['feed-unit','feed-quantity'],['vaccine-count','vaccine-doses']]) {
          expect(tester.getTopLeft(find.byKey(Key(keys[1]))).dy-tester.getBottomLeft(find.byKey(Key(keys[0]))).dy,greaterThanOrEqualTo(16));
        }
        expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox());feed.dispose();vaccine.dispose();
      });
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'online_expense_form_test.dart' show OnlineExpenseServer,selectExpense;
import 'production_tracking_test.dart' show testApp;

Future<void> fillFeed(WidgetTester tester)async{
  await selectExpense(tester);
  await tester.ensureVisible(find.byKey(const Key('feed-product')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('feed-product')));await tester.pumpAndSettle();
  await tester.tap(find.text('Croissance test').last);await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('feed-species')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('feed-species')));await tester.pumpAndSettle();
  await tester.tap(find.text('Poulet').last);await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('feed-quantity')),'500');
  await tester.ensureVisible(find.byKey(const Key('expense-submit')));
  await tester.pumpAndSettle();
}

void main(){
  setUp((){tzdata.initializeTimeZones();SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-employee';globalToken=null;});
  tearDown((){ApiService.token=null;globalToken=null;});
  testWidgets('renamed feed category submits one expense and physical supply',(tester)async{
    final server=OnlineExpenseServer()..feed=true;
    await tester.pumpWidget(testApp(AddDepenseScreen(apiService:server.api)));await tester.pumpAndSettle();
    await fillFeed(tester);
    await tester.tap(find.byKey(const Key('expense-submit')));
    await tester.tap(find.byKey(const Key('expense-submit')),warnIfMissed:false);
    await tester.pumpAndSettle();
    expect(server.posts,1);expect(server.saved!['montant'],'12.34');
    expect(server.saved!['feed_supply']['kg'],'500');expect(server.saved!['feed_supply']['lot'],isNull);
    expect(server.saved!['operation_uuid'],isA<String>());
    await tester.pumpWidget(const SizedBox());server.api.close();
  });
  testWidgets('lost response retry preserves original UUID and entire request',(tester)async{
    final server=OnlineExpenseServer()..feed=true..lost=true;
    await tester.pumpWidget(testApp(AddDepenseScreen(apiService:server.api)));await tester.pumpAndSettle();
    await fillFeed(tester);await tester.tap(find.byKey(const Key('expense-submit')));await tester.pumpAndSettle();
    final saved=Map<String,dynamic>.from(server.saved!);server.lost=false;
    await tester.ensureVisible(find.byKey(const Key('feed-retry')));
    await tester.tap(find.byKey(const Key('feed-retry')));await tester.pumpAndSettle();
    expect(server.posts,2);expect(server.saved,saved);expect(find.byKey(const Key('feed-retry')),findsNothing);
    await tester.pumpWidget(const SizedBox());server.api.close();
  });
  testWidgets('ordinary category never enables physical stock fields',(tester)async{
    final server=OnlineExpenseServer();
    await tester.pumpWidget(testApp(AddDepenseScreen(apiService:server.api)));await tester.pumpAndSettle();
    await selectExpense(tester);expect(find.byKey(const Key('feed-product')),findsNothing);
    await tester.pumpWidget(const SizedBox());server.api.close();
  });
}

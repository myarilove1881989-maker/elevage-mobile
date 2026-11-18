import 'dart:async';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ux_9a1_test.dart' show DisplayApiFake;
import 'production_tracking_test.dart' show testApp;

class QueuedDashboardApi extends DisplayApiFake {
  final pending = <Completer<Map<String,dynamic>>>[];
  bool queue = false;
  @override Future<Map<String,dynamic>> getDashboard({int? especeId}) {
    if (!queue) return super.getDashboard(especeId:especeId);
    final request=Completer<Map<String,dynamic>>();pending.add(request);return request.future;
  }
}
Map<String,dynamic> snapshot(int stock)=>{'kpis':{'stock':stock,'chiffre_affaires':123,'depenses':12}};
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});AppSettings.instance.languageCode='fr';ApiService.token='actor-A';});
  tearDown(() {ApiService.token=null;});
  testWidgets('late dashboard response cannot display the previous actor data',(tester) async {
    final api=QueuedDashboardApi();addTearDown(api.close);
    await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
    api.queue=true;
    final dynamic state=tester.state(find.byType(DashboardScreen));
    final Future<void> read=state.fetchDashboard();await tester.pump();
    ApiService.token='actor-B';api.pending.single.complete(snapshot(987654));
    await read;await tester.pumpAndSettle();
    expect(find.text('987654'),findsNothing);
    expect(find.text('81'),findsNothing,reason:'a previous actor snapshot must not remain on screen');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('older dashboard response cannot replace a newer refresh',(tester) async {
    final api=QueuedDashboardApi();addTearDown(api.close);
    await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
    api.queue=true;
    final dynamic state=tester.state(find.byType(DashboardScreen));
    final Future<void> older=state.fetchDashboard();
    final Future<void> newer=state.fetchDashboard();
    api.pending[1].complete(snapshot(222));await newer;await tester.pumpAndSettle();
    expect(find.text('222'),findsOneWidget);
    api.pending[0].complete(snapshot(111));await older;await tester.pumpAndSettle();
    expect(find.text('222'),findsOneWidget);expect(find.text('111'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

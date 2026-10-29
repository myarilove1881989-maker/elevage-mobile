import 'package:app_elevage/main.dart';
import 'package:app_elevage/screens/owner_operation_history_screen.dart';
import 'package:app_elevage/screens/operation_history_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/widgets/operation_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ux_9a1_test.dart' show DisplayApiFake;

class HistoryRouteApi extends DisplayApiFake {
  HistoryRouteApi(this.owner);
  final bool owner;
  final requests=<String>[];
  @override
  Future<dynamic> get(String endpoint) async {
    requests.add(endpoint);
    if(endpoint=='/me/capabilities/') {
      final role=owner?'OWNER':'OPERATEUR';
      return {'user':1,'exploitation':1,'role':role,'membership':{'version':1},
        'permission_contract':{'version':1,'user':1,'exploitation':1,'role':role,'rights_version':1,
          'permissions':['finance.read','history.read']}};
    }
    if(endpoint.startsWith('/history/')) return {'results':[],'next':null};
    throw StateError('Unexpected request');
  }
}
void main() {
  for(final owner in [true,false]) {
    testWidgets('toolbar history navigates to correct register; owner=$owner',(tester) async {
      SharedPreferences.setMockInitialValues({'username':'synthetic-history'});
      AppSettings.instance.languageCode='fr';ApiService.token='synthetic-history-session';
      tester.view.physicalSize=const Size(1280,800);tester.view.devicePixelRatio=1;
      final api=HistoryRouteApi(owner);
      addTearDown(() {ApiService.token=null;api.close();tester.view.reset();});
      await tester.pumpWidget(ElevageApp(apiService:api));await tester.pumpAndSettle();
      await tester.tap(find.text('Historique').hitTestable());await tester.pumpAndSettle();
      expect(find.byType(owner?OwnerOperationHistoryScreen:OperationHistoryScreen),findsOneWidget);
      expect(api.requests.any((p)=>p.startsWith('/history/') && p.contains(owner?'view=operations':'page=1')),isTrue);
      expect(tester.takeException(),isNull);
    });
  }
  test('sale denial is readable while unexpected internal errors remain hidden',() {
    const message='La vente n’est pas autorisée avec vos permissions actuelles. Reconnectez votre compte ou contactez le propriétaire.';
    expect(tabletErrorMessage(StateError(message)),message);
    expect(tabletErrorMessage(StateError('private diagnostic')),'Action indisponible. Les données déjà enregistrées restent conservées.');
  });
}

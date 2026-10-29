import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/owner_operation_history_screen.dart';

void main() {
  testWidgets('owner reads original, cancellation link, real status and server-side filters',(tester) async {
    final calls=<Map<String,String>>[];
    final api=ApiService(client:MockClient((request) async {
      calls.add(request.url.queryParameters);
      return http.Response(jsonEncode({'results':[{
        'id':1,'operation_id':'11111111-1111-4111-8111-111111111111',
        'entity_type':'VENTE_ANIMAUX','operation_type':'CREATE','author_name':'Paul',
        'actor_user_id':2,'business_status':'SUPERSEDED','business_occurred_at':'2026-10-13T10:00:00Z',
        'local_recorded_at':'2026-10-13T10:00:00Z','received_at':'2026-10-14T10:00:00Z',
        'payload':{'quantite':10,'prix_unitaire':'100.00'},'authorization_id':'grant-original',
        'permission':'animal_sales.create','rights_version':1,'reason_code':'BUSINESS_EFFECT_REVERSED',
        'ordinary_business_tolerance':true,'received_with_old_permissions':true,'late_sync':true,'reason_text':'',
        'cancellations':[{'operation_id':'22222222-2222-4222-8222-222222222222','reason':'Erreur de quantité','status':'CONFIRMED'}],
      }],'next':null}),200,headers:{'content-type':'application/json'});
    }));
    ApiService.token='synthetic-owner';
    tester.view.physicalSize=const Size(1000,1600);tester.view.devicePixelRatio=1;
    addTearDown(() {api.close();ApiService.token=null;tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    await tester.pumpWidget(MaterialApp(home:OwnerOperationHistoryScreen(api:api)));
    await tester.pumpAndSettle();
    expect(calls.single['view'],'operations');
    expect(find.textContaining('Annulée — original conservé'),findsOneWidget);
    await tester.enterText(find.byType(TextField).first,'2');
    await tester.enterText(find.byType(TextField).last,'42');
    await tester.tap(find.text('Appliquer les filtres'));await tester.pumpAndSettle();
    expect(calls.last['author'],'2');expect(calls.last['lot'],'42');
    await tester.tap(find.byType(ExpansionTile));await tester.pumpAndSettle();
    expect(find.textContaining('Acceptée avec les anciennes permissions'),findsOneWidget);
    expect(find.textContaining('Reçue sous une ancienne autorisation'),findsOneWidget);
    expect(find.textContaining('Quantité : 10'),findsWidgets);
    await tester.ensureVisible(find.text('Ouvrir l’annulation — Erreur de quantité'));
    await tester.tap(find.text('Ouvrir l’annulation — Erreur de quantité'));await tester.pumpAndSettle();
    expect(calls.last['operation'],'22222222-2222-4222-8222-222222222222');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

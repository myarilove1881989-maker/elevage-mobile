import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/operation_history.dart';
import 'package:app_elevage/services/history_presentation.dart';
import 'package:app_elevage/widgets/operation_history_list.dart';
OperationHistoryItem item(String kind,Map<String,dynamic> payload,{String state='CONFIRMED'})=>OperationHistoryItem(
 identity:'secret-uuid',author:'Utilisateur 32',authorId:32,type:historyTypeLabel(kind),entityType:kind,
 status:'technical-state',businessState:state,businessDate:'2026-10-29T17:00:00Z',recordedDate:'raw-iso',details:'raw json',data:payload);
void main() {
 test('business summaries retain sale total, birth losses, expense category and egg exclusions',() {
   final names=HistoryNames()..lots['30']='Pondeuses'..categories['148']='Transport'..clients['15']='Marché';
   expect(businessHistoryDetails(item('VENTE_OEUFS',{'lot_ref':{'server_id':30},'client_ref':{'server_id':15},
     'nombre_conditionnements':5,'oeufs_par_conditionnement':1,'prix_unitaire_conditionnement':'100.00'}),names),
     containsAll(['Pondeuses','Client : Marché','5 œufs','Total : 500 FCFA']));
   expect(businessHistoryDetails(item('NAISSANCE',{'total_naissances':11,'mort_nes':1}),names),containsAll(['Nés vivants : 10 animaux','Mort-nés : 1 animaux']));
   expect(businessHistoryDetails(item('DEPENSE',{'lot_ref':{'server_id':30},'categorie_id':148,'montant':'200.00'}),names),containsAll(['Pondeuses','Transport','Montant : 200 FCFA']));
   expect(businessHistoryDetails(item('COLLECTE_OEUFS',{'nombre_collecte':9,'nombre_casses':1,'nombre_declasses':1}),names),containsAll(['Collectés : 9 œufs','Écartés : 2 œufs','Commercialisables : 7 œufs']));
   expect(simpleHistoryStatus(item('DEPENSE',{},state:'UNREVIEWED')),'En attente');
   expect(simpleHistoryStatus(item('DEPENSE',{},state:'NOT_APPLIED')),'Échec');
 });
 testWidgets('tablet cards show readable business data and hide technical audit fields',(tester) async {
   tester.view.physicalSize=const Size(1280,800);tester.view.devicePixelRatio=1;
   addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
   final names=HistoryNames()..authors['32']='Paul'..lots['30']='Pondeuses';
   final entry=item('DEPENSE',{'lot_ref':{'server_id':30},'montant':'200.00','token':'never-show','note':'technical-json'});
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:OperationHistoryList(items:[entry],names:names))));
   expect(find.textContaining('Paul'),findsOneWidget);expect(find.textContaining('Pondeuses'),findsOneWidget);
   expect(find.text('Synchronisée'),findsOneWidget);
   for(final raw in ['secret-uuid','Utilisateur 32','raw-iso','raw json','never-show','technical-json','technical-state']) {
     expect(find.textContaining(raw),findsNothing);
   }
   expect(tester.takeException(),isNull);
   expect(entry.identity,'secret-uuid');expect(entry.data['token'],'never-show');
 });
}

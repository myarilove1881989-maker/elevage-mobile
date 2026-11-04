import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/vaccine_local.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/services/classic_terrain_command.dart';
const vaccine='11111111-1111-4111-8111-111111111111',vialA='22222222-2222-4222-8222-222222222222',vialB='33333333-3333-4333-8333-333333333333';
Map<String,dynamic> vaccineSnapshot({int physical=20,int revision=1,Map<String,dynamic> coverage=const {}})=>{
  'id':1,'schema':1,'exploitation':1,'vaccine_contract':1,'confirmed':true,'confirmed_business_revision':revision,
  'coverage':coverage,'as_of':'2026-10-12T12:00:00Z','products':[{'id':vaccine,'name':'Vaccin test','archived':false}],
  'species':[{'id':4,'nom':'Poulet'}],'lots':[{'id':10,'nom':'Lot','espece_id':4}],
  'vials':[for(final id in [vialA,vialB]){'id':id,'product':vaccine,'label':id,'species':4,'lot':null,'physical':physical,'usable':physical,
    'opened_at':null,'usable_seconds':null,'expires_on':'2026-11-30','usable_until':'2026-12-01T00:00:00Z'}]};
OutboxEntry vaccineOriginal({String state='UNREVIEWED'})=>OutboxEntry(declaration:{'client_operation_id':'00000000-0000-4000-8000-000000000001',
  'exploitation_id':1,'device_id':7,'author_user_id':2,'local_sequence':1,'entity_type':'VACCINATION','operation_type':'CREATE',
  'business_occurred_at':'2026-10-12T12:00:00Z','payload':{'vaccine_version':1,'lot_ref':{'server_id':10},'product':vaccine,'animals':35,
    'allocations':[{'vial':vialA,'doses':20},{'vial':vialB,'doses':15}]}},transportStatus:'LOCAL_PENDING',businessStatus:state,attemptCount:0,lastError:'');
void main(){
  test('confirmed doses and pending doses are separated and never folded twice',(){
    final original=vaccineOriginal();final snapshot=vaccineSnapshot();
    final projected=projectVaccines(snapshot,[original],1,DateTime.utc(2026,10,12,12));
    expect(projected['vials'][0]['confirmed_physical'],20);expect(projected['vials'][0]['estimated_physical'],0);
    expect(projected['vials'][1]['estimated_usable'],5);expect(original.businessStatus,'UNREVIEWED');
    final received=vaccineSnapshot(physical:5,revision:2,coverage:{'7':[[1,1]]});
    expect(projectVaccines(received,[original],1,DateTime.utc(2026,10,12))['vials'][0]['estimated_physical'],5);
  });
  test('expired doses stay physical and conflicted originals stay visible',(){
    final original=vaccineOriginal(state:'NEEDS_RECONCILIATION');
    final projected=projectVaccines(vaccineSnapshot(),[original],1,DateTime.utc(2026,12,2));
    expect(projected['vials'][0]['physical'],20);expect(projected['vials'][0]['estimated_usable'],0);
    expect(projected['review_operations'],[original.operationId]);
    expect(()=>projectVaccines(vaccineSnapshot(),[],2,DateTime.utc(2026,10,12)),throwsStateError);
  });
  test('vaccine expense, vaccination and correction preserve original UUID and signed entity',(){
    const id='00000000-0000-4000-8000-000000000001';
    final purchase=ClassicTerrainCommand.decode('POST','/depenses/create/',{'operation_uuid':id,'lot':10,'categorie':3,'montant':'1000.00','date':'2026-10-12','vaccine_supply':{'product':vaccine}})!;
    expect(purchase.kind,'DEPENSE');expect(purchase.operationId,id);expect(purchase.payload['vaccine_version'],1);
    final administration=ClassicTerrainCommand.decode('POST','/vaccinations/',{'operation_uuid':id,'lot':10,'vaccinated_at':'2026-10-12T12:00:00Z','product':vaccine,'animals':35,'allocations':[]})!;
    expect(administration.kind,'VACCINATION');expect(administration.operationId,id);expect(administration.payload['lot_ref'],{'server_id':10});
    final cancel=ClassicTerrainCommand.decode('DELETE','/vaccinations/4/',{'operation_uuid':id,'expected_version':'vac:12','reason':'Erreur vérifiée','confirm':true})!;
    expect(cancel.operation,'REVERSE');expect(cancel.payload.containsKey('confirm'),false);expect(cancel.expectedVersion,'vac:12');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/classic_terrain_command.dart';
import 'package:app_elevage/widgets/feed_distribution_fields.dart';
import 'feed_stock_projection_test.dart' show product;
void main(){
  test('procurement stays an existing DEPENSE and retains its intention UUID',(){
    final command=ClassicTerrainCommand.decode('POST','/depenses/create/',{
      'operation_uuid':'00000000-0000-4000-8000-000000000001','lot':10,'categorie':3,'montant':'1000.00',
      'date':'2026-11-03','note':'Original','feed_supply':{'product':product,'species':4,'kg':'500','received_on':'2026-11-03'}})!;
    expect(command.kind,'DEPENSE');expect(command.operationId,'00000000-0000-4000-8000-000000000001');
    expect(command.payload['stock_version'],1);expect(command.payload['lot_ref'],{'server_id':10});
    expect(command.payload.containsKey('operation_uuid'),isFalse);
  });
  test('distribution retains purchase dependencies and cannot select another reserved lot',(){
    final draft=FeedDistributionDraft()..product=product;
    final catalog={'lots':[{'id':10,'espece_id':4}],'products':[{'id':product,'positions':[
      {'species_id':4,'lot_id':null,'kg':'0','pending_kg':'500','estimated_kg':'500'}]}],
      'pending_purchases':[{'operation_id':'00000000-0000-4000-8000-000000000001','product':product,'species':4,'lot':null}]};
    final payload=draft.payload(catalog,10,'80','Distribution');
    final command=ClassicTerrainCommand.decode('POST','/alimentation/distributions/',{...payload,
      'operation_uuid':'00000000-0000-4000-8000-000000000002'})!;
    expect(command.kind,'ALIMENTATION');expect(command.payload['quantite_kg'],'80.000');
    expect(command.dependencies,['00000000-0000-4000-8000-000000000001']);
    expect(command.payload.containsKey('_feed_dependencies'),isFalse);
    expect(()=>draft.payload(catalog,10,'501',''),throwsStateError);
    (catalog['products'] as List).single['positions'].add({'species_id':4,'lot_id':20,'kg':'500'});
    draft.sourceLot=20;expect(()=>draft.payload(catalog,10,'1',''),throwsStateError);
  });
  test('versioned corrections use existing signed UPDATE and REVERSE actions',(){
    final body={'operation_uuid':'00000000-0000-4000-8000-000000000002','expected_version':'feed:12','reason':'Erreur','quantite_kg':'70'};
    final update=ClassicTerrainCommand.decode('PATCH','/alimentation/distributions/5/',body)!;
    expect(update.operation,'UPDATE');expect(update.expectedVersion,'feed:12');
    expect(update.payload['distribution_ref'],{'server_id':5});
    final cancel=ClassicTerrainCommand.decode('DELETE','/alimentation/distributions/5/',{...body,'confirm':true}..remove('quantite_kg'))!;
    expect(cancel.operation,'REVERSE');expect(cancel.payload.containsKey('confirm'),isFalse);
  });
}

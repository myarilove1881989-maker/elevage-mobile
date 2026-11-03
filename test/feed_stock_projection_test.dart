import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/feed_stock_projection.dart';
import 'package:app_elevage/offline/outbox.dart';
const product='11111111-1111-4111-8111-111111111111';
Map<String,dynamic> baseline({String kg='500',int revision=1,Map<String,dynamic> coverage=const {}})=>{
  'id':1,'schema':1,'exploitation':1,'confirmed_business_revision':revision,'coverage':coverage,
  'products':[{'id':product,'name':'Croissance','archived':false,'positions':[{'species_id':4,'lot_id':null,'kg':kg}]}]};
OutboxEntry operation(String kind,Map<String,dynamic> payload,int seq,{String state='UNREVIEWED',String? id})=>OutboxEntry(
  declaration:{'client_operation_id':id??'00000000-0000-4000-8000-${seq.toString().padLeft(12,'0')}',
    'local_sequence':seq,'author_user_id':2,'exploitation_id':1,'device_id':7,'operation_type':'CREATE','entity_type':kind,
    'payload':{'stock_version':1,...payload}},transportStatus:'LOCAL_PENDING',businessStatus:state,attemptCount:0,lastError:'');
void main(){
  test('confirmed 500 and pending 80 give estimated 420 without changing confirmed',(){
    final out=operation('ALIMENTATION',{'product':product,'species':4,'quantite_kg':'80','source_lot':null},1);
    final result=projectFeedStock(baseline(),[out],1),position=result['products'][0]['positions'][0];
    expect(position['kg'],'500');expect(position['pending_kg'],'-80.000');expect(position['estimated_kg'],'420.000');
    expect(result['pending_operations'],[out.operationId]);
  });
  test('local purchase then dependent distribution projects from the same originals',(){
    final purchase=operation('DEPENSE',{'feed_supply':{'product':product,'species':4,'bags':'10','kg_per_bag':'50'}},1);
    final out=operation('ALIMENTATION',{'product':product,'species':4,'quantite_kg':'80','supply_parent_uuid':purchase.operationId},2);
    final result=projectFeedStock(baseline(kg:'0'),[out,purchase],1);
    expect(result['products'][0]['positions'][0]['estimated_kg'],'420.000');
    expect(result['pending_purchases'][0]['operation_id'],purchase.operationId);
  });
  test('new local product is selectable before its purchase is synchronized',(){
    final snapshot=baseline(kg:'0');snapshot['products']=<dynamic>[];
    final purchase=operation('DEPENSE',{'feed_supply':{'new_product':{'id':product,'name':'Local'},'species':4,'kg':'500'}},1);
    final out=operation('ALIMENTATION',{'product':product,'species':4,'quantite_kg':'80'},2);
    final result=projectFeedStock(snapshot,[out,purchase],1);
    expect(result['products'][0]['name'],'Local');expect(result['products'][0]['positions'][0]['estimated_kg'],'420.000');
  });
  test('lost response then fresh server snapshot never adds the included effects again',(){
    final purchase=operation('DEPENSE',{'feed_supply':{'product':product,'species':4,'kg':'500'}},1);
    final out=operation('ALIMENTATION',{'product':product,'species':4,'quantite_kg':'80'},2);
    final result=projectFeedStock(baseline(kg:'420',revision:3,coverage:{'7':[[1,2]]}),[purchase,out],1);
    expect(result['products'][0]['positions'][0]['estimated_kg'],'420');
    expect(result['pending_operations'],hasLength(2));
  });
  test('conflicts are visible, preserved and excluded from available estimated stock',(){
    final out=operation('ALIMENTATION',{'product':product,'species':4,'quantite_kg':'800'},1,state:'NEEDS_RECONCILIATION');
    final before=out.declaration;
    final result=projectFeedStock(baseline(),[out],1);
    expect(result['products'][0]['positions'][0]['estimated_kg'],'500');expect(result['review_operations'],[out.operationId]);
    expect(out.declaration,before);
  });
  test('known failed parent cannot finance a dependent distribution projection',(){
    final purchase=operation('DEPENSE',{'feed_supply':{'product':product,'species':4,'kg':'500'}},1,state:'NOT_APPLIED');
    final out=operation('ALIMENTATION',{'product':product,'species':4,'quantite_kg':'80','supply_parent_uuid':purchase.operationId},2);
    final result=projectFeedStock(baseline(kg:'0'),[purchase,out],1);
    expect(result['products'][0]['positions'][0]['estimated_kg'],'0');expect(result['review_operations'],[out.operationId]);
  });
  test('snapshot isolation and exact kg validation fail closed',(){
    expect(()=>projectFeedStock(baseline(),[],2),throwsStateError);
    expect(()=>feedMilli('1.0001'),throwsStateError);
    expect(feedKg(feedMilli('500.125')-feedMilli('80.025')),'420.100');
  });
}

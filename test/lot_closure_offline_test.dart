import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'outbox_test.dart' show testOutboxGrant;

void main(){
 test('cached closure blocks new declarations but preserves and deduplicates existing originals',()async{
  final directory=await Directory.systemTemp.createTemp('lot-closure-test-');
  final now=DateTime.utc(2026,10,12);
  final db=FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),List.filled(64,'c').join()),farmId:1,serverNamespace:'closure.invalid',clock:()=>now);
  try{
   final grant=await testOutboxGrant(2,now);
   final lot={'id':7,'nom':'Cycle','stock':20,'stock_oeufs':0,'confirmed_business_revision':0};
   await db.replaceConfirmedCache('lots',[lot]);
   final payload={'lot_ref':{'server_id':7},'montant':'5.00','note':'Avant clôture'};
   const id='11111111-1111-4111-8111-111111111111';
   final original=await db.enqueue(grant:grant,isSessionCurrent:()=>true,entityType:'DEPENSE',operationType:'CREATE',payload:payload,businessOccurredAt:now,operationId:id);
   await db.replaceConfirmedCache('lots',[{...lot,'date_fin':'2026-10-12','confirmed_business_revision':1}]);
   await expectLater(db.enqueue(grant:grant,isSessionCurrent:()=>true,entityType:'DEPENSE',operationType:'CREATE',payload:payload,businessOccurredAt:now),throwsStateError);
   final repeated=await db.enqueue(grant:grant,isSessionCurrent:()=>true,entityType:'DEPENSE',operationType:'CREATE',payload:payload,businessOccurredAt:now,operationId:id);
   expect(repeated.declaration,original.declaration);expect(await db.listOutbox(),hasLength(1));
   final counter=await db.customSelect('SELECT next_sequence FROM local_sequence_counter WHERE singleton=1').getSingle();expect(counter.read<int>('next_sequence'),2);
  }finally{await db.close();await directory.delete(recursive:true);}
 });
}

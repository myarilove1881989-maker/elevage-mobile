import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/widgets/feed_supply_fields.dart';

void main() {
  test('explicit sacks retain exact inputs and a stable new-product identity',(){
    final draft=FeedSupplyDraft()..newProduct=true..sacks=true..species=4;
    draft.name.text='Croissance';draft.quantity.text='10';draft.sackWeight.text='50';
    expect(draft.payload(),draft.payload());expect(draft.payload()['bags'],'10');
    expect(draft.payload()['kg_per_bag'],'50');expect(draft.payload()['lot'],isNull);
    draft.dispose();
  });
  test('missing sack weight and fractional sacks are refused',(){
    final draft=FeedSupplyDraft()..product='test'..species=4..sacks=true;
    draft.quantity.text='10';expect(draft.payload,throwsFormatException);
    draft.sackWeight.text='50';draft.quantity.text='1.5';expect(draft.payload,throwsFormatException);
    draft.dispose();
  });
  test('kg input is exact and normalizes a decimal comma',(){
    final draft=FeedSupplyDraft()..product='test'..species=4;
    draft.quantity.text='500,125';expect(draft.payload()['kg'],'500.125');
    draft.quantity.text='500.0001';expect(draft.payload,throwsFormatException);
    draft.dispose();
  });
  testWidgets('physical destination follows species and permits shared stock',(tester)async{
    final draft=FeedSupplyDraft();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:FeedSupplyFields(
      draft:draft,editable:true,catalog:{'products':<dynamic>[],
        'species':[{'id':4,'nom':'Poulet'},{'id':5,'nom':'Canard'}],
        'lots':[{'id':7,'nom':'Lot Poulet','espece_id':4},{'id':8,'nom':'Lot Canard','espece_id':5}]})))));
    await tester.tap(find.byKey(const Key('feed-species')));await tester.pumpAndSettle();
    await tester.tap(find.text('Poulet').last);await tester.pumpAndSettle();
    expect(draft.species,4);expect(draft.lot,isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('feed-lot-4')));
    await tester.tap(find.byKey(const ValueKey('feed-lot-4')));await tester.pumpAndSettle();
    expect(find.text('Lot Poulet'),findsOneWidget);expect(find.text('Lot Canard'),findsNothing);
    await tester.tap(find.text('Stock partagé de cette espèce').last);await tester.pumpAndSettle();
    expect(draft.lot,isNull);
    await tester.pumpWidget(const SizedBox());draft.dispose();
  });
}

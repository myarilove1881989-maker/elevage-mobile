import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/widgets/v2_components.dart';
void main(){
  testWidgets('explicit returned value closes edited dialog without abandonment prompt',(tester)async{
    Object? result;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>TextButton(onPressed:()async{result=await showDialog<Object>(context:context,builder:(dialog)=>V2AlertDialog(content:const V2Field(child:TextField()),actions:[FilledButton(onPressed:()=>Navigator.pop(dialog,{'nom':'Fictif'}),child:const Text('Choisir'))]));},child:const Text('Ouvrir')))));
    await tester.tap(find.text('Ouvrir'));await tester.pumpAndSettle();await tester.tap(find.byType(TextField));await tester.enterText(find.byType(TextField),'Fictif');await tester.pump();
    final point=tester.getCenter(find.text('Choisir'));await tester.tapAt(point);await tester.tapAt(point);await tester.pumpAndSettle();expect(result,{'nom':'Fictif'});expect(find.text('Quitter la saisie ?'),findsNothing);expect(find.byType(V2AlertDialog),findsNothing);
  });
  testWidgets('busy back cannot discard an edited pending dialog',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>TextButton(onPressed:()=>showDialog<void>(context:context,builder:(dialog)=>const V2AlertDialog(content:V2Field(child:TextField()),actions:[FilledButton(onPressed:null,child:Text('Enregistrer'))])),child:const Text('Ouvrir')))));
    await tester.tap(find.text('Ouvrir'));await tester.pumpAndSettle();await tester.tap(find.byType(TextField));await tester.enterText(find.byType(TextField),'Pending');await tester.pump();await tester.binding.handlePopRoute();await tester.pumpAndSettle();expect(find.byType(V2AlertDialog),findsOneWidget);expect(find.text('Pending'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/api_service.dart';
import 'egg_production_test.dart' show EggApiFake, eggTestApp;

class EditableEggApi extends EggApiFake {
  Map<String,dynamic>? changed;
  @override Future<dynamic> get(String endpoint) async {
    final caps=await super.get(endpoint) as Map<String,dynamic>;
    caps['permission_contract']['permissions'].add('egg_collections.update');return caps;
  }
  @override Future<Map<String,dynamic>> updateEggCollection(Map<String,dynamic> original,Map<String,dynamic> values) async {
    changed=values;sampleCollections=[{...original,...values}];return values;
  }
}
void main() {
  testWidgets('existing online collection opens prefilled form and saves an update',(tester) async {
    final api=EditableEggApi()..sampleCollections=[{'id':90,'lot':1,'collecte_at':DateTime.now().toIso8601String(),
      'nombre_collecte':120,'nombre_commercialisable':117,'nombre_casses':3,'nombre_declasses':0,'nombre_consommes_donnes':0}];
    ApiService.token='synthetic';
    await tester.pumpWidget(eggTestApp(api));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('edit-egg-90')),250,scrollable:find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('edit-egg-90')));await tester.pumpAndSettle();
    expect(find.text('Modifier la collecte'),findsOneWidget);
    expect((tester.widget<TextField>(find.byKey(const Key('eggFullTrays')))).controller!.text,'4');
    await tester.enterText(find.byKey(const Key('eggFullTrays')),'3');
    await tester.tap(find.text('Enregistrer la collecte'));await tester.pumpAndSettle();
    expect(api.changed!['nombre_collecte'],90);expect(api.collectionsCreated,0);
    await tester.pumpWidget(const SizedBox());ApiService.token=null;api.close();
  });
}

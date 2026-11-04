import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/screens/production_tracking_screen.dart';
import 'package:app_elevage/screens/vaccination_screen.dart';
import 'production_tracking_test.dart' show testApp,ProductionTrackingApiFake,selectDropdown;
import 'vaccine_projection_test.dart' show vaccineSnapshot;
class VaccineNavigationApi extends ProductionTrackingApiFake {
  @override Future<dynamic> get(String path)async {
    if(path=='/vaccine-supplies/')return vaccineSnapshot();
    if(path.startsWith('/vaccinations/'))return <dynamic>[];
    return super.get(path);
  }
}
void main(){
  testWidgets('production keeps laying and feed entries and opens the fourth vaccination entry',(tester)async{
    final api=VaccineNavigationApi();await tester.pumpWidget(testApp(ProductionTrackingScreen(apiService:api)));await tester.pumpAndSettle();
    await selectDropdown(tester,const Key('productionSpeciesDropdown'),'Poulet');await selectDropdown(tester,const Key('productionLotDropdown'),'Pondeuses');
    expect(find.byKey(const Key('openEggTrackingButton')),findsOneWidget);expect(find.byKey(const Key('openFeedTrackingButton')),findsOneWidget);
    final button=find.byKey(const Key('openVaccinationTrackingButton'));await tester.scrollUntilVisible(button,250,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(button);await tester.pumpAndSettle();
    expect(find.byType(VaccinationScreen),findsOneWidget);expect(find.text('Aucune vaccination enregistrée.'),findsOneWidget);
    expect(find.byKey(const Key('add-vaccination')),findsNothing,reason:'Read access cannot invent a vaccination write permission');
    await tester.pumpWidget(const SizedBox());api.close();
  });
}

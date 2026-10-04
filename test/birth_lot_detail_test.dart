import 'package:app_elevage/screens/lot_detail_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class BirthLotApiFake extends ApiService {
  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async {
    if (lotId == 1) {
      return {
        'nom': 'Truies', 'espece_nom': 'Porc', 'stock': 5,
        'type_production': 'REPRODUCTION', 'date_debut': '2026-09-01',
        'achats': <dynamic>[], 'mouvements': <dynamic>[],
        'depenses': <dynamic>[], 'ventes_oeufs': <dynamic>[],
        'naissances_issues': [
          {'id': 9, 'date': '2026-10-01', 'total_naissances': 12,
           'mort_nes': 2, 'nes_vivants': 10,
           'nouveau_lot_id': 2, 'nouveau_lot_nom': 'Porcelets octobre'},
        ],
      };
    }
    return {
      'nom': 'Porcelets octobre', 'espece_nom': 'Porc', 'stock': 10,
      'type_production': 'CHAIR', 'date_debut': '2026-10-01',
      'achats': <dynamic>[], 'depenses': <dynamic>[],
      'ventes_oeufs': <dynamic>[], 'naissances_issues': <dynamic>[],
      'mouvements': [
        {'id': 9, 'type_mouvement': 'NAISSANCE', 'quantite': 10,
         'mort_nes': 2, 'total_naissances': 12, 'date': '2026-10-01',
         'lot_origine': 1, 'lot_origine_nom': 'Truies', 'note': ''},
      ],
    };
  }
}

void main() {
  testWidgets('Le parent affiche le nouveau lot et le lot enfant affiche son origine',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: LotDetailScreen(apiService: BirthLotApiFake(), lotId: 1),
    ));
    await tester.pumpAndSettle();
    final childLink = find.textContaining('Lots issus de naissances : Porcelets octobre');
    await tester.scrollUntilVisible(
      childLink, 200, scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(childLink, findsOneWidget);
    expect(find.textContaining('Nés vivants : 10'), findsOneWidget);
    await tester.tap(childLink);
    await tester.pumpAndSettle();
    final origin = find.textContaining('Lot d’origine : Truies');
    await tester.scrollUntilVisible(
      origin, 200, scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(origin, findsOneWidget);
    expect(find.textContaining('Nombre total de naissances : 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

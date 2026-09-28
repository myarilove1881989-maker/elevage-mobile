import 'package:app_elevage/models/lot.dart';
import 'package:app_elevage/screens/lot_detail_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ProductionTypeApiFake extends ApiService {
  ProductionTypeApiFake(this.typeProduction);

  final String typeProduction;

  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async => {
    'id': lotId,
    'nom': typeProduction == 'OEUFS' ? 'Pondeuses' : 'Poulets de chair',
    'espece_nom': 'Poulet',
    'date_debut': '2026-09-27',
    'type_production': typeProduction,
    'statut_production': typeProduction == 'OEUFS' ? 'PONTE' : 'ELEVAGE',
    'stock': 100,
    'achats': [
      {'id': 1, 'quantite': 100, 'prix_total': 100000, 'date': '2026-09-27'},
    ],
    'mouvements': <dynamic>[],
    'depenses': <dynamic>[],
  };
}

void main() {
  test('Lot conserve CHAIR par défaut pour une ancienne réponse API', () {
    final lot = Lot.fromJson({'id': 1, 'nom': 'Ancien lot', 'stock': 10});

    expect(lot.typeProduction, 'CHAIR');
    expect(lot.statutProduction, 'ELEVAGE');
  });

  test('Lot récupère les valeurs de production envoyées par l’API', () {
    final lot = Lot.fromJson({
      'id': 2,
      'nom': 'Pondeuses',
      'stock': 100,
      'type_production': 'OEUFS',
      'statut_production': 'PONTE',
    });

    expect(lot.typeProduction, 'OEUFS');
    expect(lot.statutProduction, 'PONTE');
  });

  testWidgets('Le raccourci ponte apparaît uniquement pour un lot OEUFS', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LotDetailScreen(
          key: const ValueKey('lot-oeufs'),
          apiService: ProductionTypeApiFake('OEUFS'),
          lotId: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ouvrir le suivi de ponte'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: LotDetailScreen(
          key: const ValueKey('lot-chair'),
          apiService: ProductionTypeApiFake('CHAIR'),
          lotId: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ouvrir le suivi de ponte'), findsNothing);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/widgets/operation_status.dart';
void main() {
  test('HTTP status is visible for previously indistinguishable refusals', () {
    for(final status in [400,404]) {
      expect(tabletErrorMessage(FoundationApiException(status)),contains('HTTP $status'));
    }
  });
  test('authentication and server failures use actionable safe messages',() {
    expect(tabletErrorMessage(FoundationApiException(401)),contains('Connexion personnelle'));
    expect(tabletErrorMessage(FoundationApiException(403)),contains('pas autorisée'));
    expect(tabletErrorMessage(FoundationApiException(503)),contains('indisponible'));
    expect(tabletErrorMessage(FoundationApiException(500)),contains('Erreur du serveur'));
  });
  test('missing policy and invalid PIN have actionable messages', () {
    expect(tabletErrorMessage(StateError('La préparation de cette exploitation doit être activée par son propriétaire.')),contains('propriétaire'));
    expect(tabletErrorMessage(ArgumentError('Le PIN doit contenir 6 à 12 chiffres.')),contains('6 à 12'));
  });
}

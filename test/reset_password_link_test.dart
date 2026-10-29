import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:app_elevage/screens/reset_password_link_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('link validates without consuming, confirms and never uses Authorization', (tester) async {
    final calls=<String>[];
    final api=ApiService(tokenStore: TokenService(useSecureStorage: false), client:MockClient((request) async {
      calls.add(request.url.path);
      expect(request.url.query,'');
      expect(request.headers.containsKey('Authorization'),false);
      expect(jsonDecode(request.body)['link_token'],'synthetic-link');
      return http.Response('{}',200);
    }));
    await tester.pumpWidget(MaterialApp(home:ResetPasswordLinkScreen(api:api,token:'synthetic-link')));
    await tester.pumpAndSettle();
    expect(calls,['/api/password-reset/link/']);
    await tester.enterText(find.byType(TextField).at(0),'ReplacementPassword!938');
    await tester.enterText(find.byType(TextField).at(1),'ReplacementPassword!938');
    await tester.tap(find.text('Enregistrer le nouveau mot de passe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mot de passe modifié.'),findsOneWidget);
    expect(calls,['/api/password-reset/link/','/api/password-reset/confirm/']);
    api.close();
  });
  testWidgets('expired link has no password form and offers recovery', (tester) async {
    final api=ApiService(tokenStore: TokenService(useSecureStorage: false), client:MockClient((_) async=>http.Response('{"message":"expired"}',400)));
    await tester.pumpWidget(MaterialApp(home:ResetPasswordLinkScreen(api:api,token:'expired')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField),findsNothing);
    expect(find.textContaining('Lien invalide'),findsOneWidget);
    expect(find.text('Demander un nouveau lien'),findsOneWidget);
    api.close();
  });
  testWidgets('confirmation mismatch never sends password', (tester) async {
    var calls=0;
    final api=ApiService(tokenStore: TokenService(useSecureStorage: false), client:MockClient((_) async { calls++;return http.Response('{}',200); }));
    await tester.pumpWidget(MaterialApp(home:ResetPasswordLinkScreen(api:api,token:'synthetic')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0),'ReplacementPassword!938');
    await tester.enterText(find.byType(TextField).at(1),'DifferentPassword!938');
    await tester.tap(find.text('Enregistrer le nouveau mot de passe'));
    await tester.pumpAndSettle();
    expect(find.text('Les mots de passe ne correspondent pas.'),findsOneWidget);
    expect(calls,1);api.close();
  });
}

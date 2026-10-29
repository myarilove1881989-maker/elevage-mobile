import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/screens/forgot_password_screen.dart';
import 'package:app_elevage/services/api_service.dart';

void main() {
  test('API reset flow uses public endpoints and handles success', () async {
    final paths = <String>[];
    final api = ApiService(client: MockClient((request) async {
      paths.add(request.url.path);
      final data = jsonDecode(request.body);
      expect(data['email'], 'farmer@example.com');
      expect(request.headers['Authorization'], isNull);
      if (request.url.path.endsWith('/verify/')) {
        expect(data['code'], '123456');
        return http.Response('{"reset_token":"temporary"}', 200);
      }
      if (request.url.path.endsWith('/confirm/')) {
        expect(data['reset_token'], 'temporary');
        expect(data['new_password'], 'StrongPassword!987');
      }
      return http.Response('{"message":"ok"}', 200);
    }));
    await api.requestPasswordReset('farmer@example.com');
    final token = await api.verifyPasswordReset('farmer@example.com', '123456');
    await api.confirmPasswordReset('farmer@example.com', token, 'StrongPassword!987');
    expect(paths, ['/api/password-reset/request/', '/api/password-reset/verify/', '/api/password-reset/confirm/']);
    api.close();
  });

  testWidgets('connection failure stays on request screen for retry', (tester) async {
    final api = ApiService(client: MockClient((_) async => throw http.ClientException('offline')));
    await tester.pumpWidget(MaterialApp(home: ForgotPasswordScreen(apiService: api)));
    await tester.enterText(find.byType(TextField), 'farmer@example.com');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossible de joindre le serveur'), findsOneWidget);
    expect(find.text('Envoyer le code'), findsOneWidget);
    api.close();
  });
  testWidgets('email, code, password confirmation and recovery from expiry', (tester) async {
    final calls = <String>[];
    final api = ApiService(client: MockClient((request) async {
      calls.add(request.url.path);
      expect(request.headers.containsKey('Authorization'), isFalse);
      if (request.url.path.endsWith('/verify/')) {
        return http.Response('{"reset_token":"temporary"}', 200);
      }
      if (request.url.path.endsWith('/confirm/')) {
        expect(jsonDecode(request.body)['reset_token'], 'temporary');
        return http.Response('{"message":"Session expirée. Demandez un nouveau code."}', 400);
      }
      return http.Response('{"message":"Si cette adresse existe, un code a été envoyé."}', 200);
    }));
    await tester.pumpWidget(MaterialApp(home: ForgotPasswordScreen(apiService: api)));
    await tester.enterText(find.byType(TextField), 'farmer@example.com');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Vérifier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'StrongPassword!987');
    await tester.enterText(find.byType(TextField).at(1), 'DifferentPassword!');
    await tester.ensureVisible(find.text('Modifier le mot de passe'));
    await tester.tap(find.text('Modifier le mot de passe'));
    await tester.pumpAndSettle();
    expect(find.text('Les mots de passe ne correspondent pas.'), findsOneWidget);
    expect(calls.length, 2);
    await tester.enterText(find.byType(TextField).at(1), 'StrongPassword!987');
    await tester.ensureVisible(find.text('Modifier le mot de passe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier le mot de passe'));
    await tester.pumpAndSettle();
    expect(find.text('Session expirée. Demandez un nouveau code.'), findsOneWidget);
    await tester.ensureVisible(find.text('Demander un nouveau code'));
    await tester.tap(find.text('Demander un nouveau code'));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer le code'), findsOneWidget);
    api.close();
  });

  testWidgets('invalid email is rejected without network access', (tester) async {
    final api = ApiService(client: MockClient((_) async => throw StateError('unexpected network')));
    await tester.pumpWidget(MaterialApp(home: ForgotPasswordScreen(apiService: api)));
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
    api.close();
  });
}

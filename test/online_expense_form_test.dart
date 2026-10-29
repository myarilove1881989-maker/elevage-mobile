import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'production_tracking_test.dart' show testApp;

class MemoryTokens implements TokenStore {
  @override
  Future<void> clearToken() async {}
  @override
  Future<String?> getToken() async => null;
  @override
  Future<void> saveToken(String token) async {}
}

class OnlineExpenseServer {
  bool policy = false,
      allowed = true,
      down = false,
      lost = false,
      refusePost = false;
  String role = 'OPERATEUR';
  int posts = 0, reads = 0;
  Map<String, dynamic>? saved;
  late final api = ApiService(
    tokenStore: MemoryTokens(),
    client: MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer synthetic-employee');
      if (down) throw http.ClientException('Synthetic offline');
      final path = request.url.path;
      if (path.endsWith('/capabilities/')) {
        reads++;
        return http.Response(
          jsonEncode({
            'user': 2,
            'exploitation': 1,
            'role': role,
            'offline_policy_enabled': policy,
            'membership': {'version': 1},
            'permission_contract': {
              'version': 1,
              'user': 2,
              'exploitation': 1,
              'role': role,
              'rights_version': 1,
              'permissions': [
                'finance.read',
                if (allowed && role == 'OPERATEUR') 'expenses.create',
              ],
            },
          }),
          200,
        );
      }
      if (request.method == 'GET' && path.endsWith('/lots/')) {
        return http.Response(
          jsonEncode([
            {'id': 7, 'nom': 'Lot fictif', 'exploitation': 1, 'stock': 10},
          ]),
          200,
        );
      }
      if (path.endsWith('/categories-depense/')) {
        return http.Response(
          jsonEncode([
            {'id': 3, 'nom': 'Frais fictifs', 'exploitation': 1},
          ]),
          200,
        );
      }
      if (path.endsWith('/depenses/create/')) {
        expect(request.method, 'POST');
        posts++;
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        if (lost) throw http.ClientException('Synthetic lost response');
        if (refusePost) {
          return http.Response('{"detail":"DEVICE_PROOF_REQUIRED"}', 403);
        }
        return http.Response(jsonEncode({'id': 40, ...saved!}), 201);
      }
      throw StateError('Unexpected synthetic route $path');
    }),
  );
}

Future<void> selectExpense(WidgetTester tester) async {
  final dropdowns = find.byWidgetPredicate((w) => w is DropdownButtonFormField);
  await tester.tap(dropdowns.at(0));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lot fictif').last);
  await tester.pumpAndSettle();
  await tester.tap(dropdowns.at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Frais fictifs').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('expense-amount')), '12,34');
  await tester.enterText(
    find.byKey(const Key('expense-note')),
    ' Note fictive ',
  );
}

void main() {
  setUp(() {
    tzdata.initializeTimeZones();
    SharedPreferences.setMockInitialValues({});
    ApiService.token = 'synthetic-employee';
    globalToken = null;
  });
  tearDown(() {
    ApiService.token = null;
    globalToken = null;
  });
  for (final condition in ['tablet', 'owner', 'no-right', 'offline']) {
    testWidgets(
      'HTTP expense $condition cannot initialize an unauthorized classic form',
      (tester) async {
        final server = OnlineExpenseServer();
        if (condition == 'tablet') server.policy = true;
        if (condition == 'owner') server.role = 'OWNER';
        if (condition == 'no-right') server.allowed = false;
        if (condition == 'offline') server.down = true;
        await tester.pumpWidget(
          testApp(AddDepenseScreen(apiService: server.api)),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('expense-submit')), findsNothing);
        expect(server.posts, 0);
        if (condition == 'tablet' || condition == 'offline') {
          expect(find.text('Ouvrir l’espace éleveur'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        server.api.close();
      },
    );
  }
  for (final condition in [
    'success',
    'policy-changed',
    'permission-removed',
    'lost',
    'server-device-refusal',
  ]) {
    testWidgets(
      'shared expense form online $condition uses existing endpoint once with exact amount',
      (tester) async {
        final server = OnlineExpenseServer();
        await tester.pumpWidget(
          testApp(AddDepenseScreen(apiService: server.api)),
        );
        await tester.pumpAndSettle();
        await selectExpense(tester);
        if (condition == 'policy-changed') server.policy = true;
        if (condition == 'permission-removed') server.allowed = false;
        if (condition == 'lost') server.lost = true;
        if (condition == 'server-device-refusal') server.refusePost = true;
        final submit = find.byKey(const Key('expense-submit'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        final denied = {
          'policy-changed',
          'permission-removed',
        }.contains(condition);
        expect(server.posts, denied ? 0 : 1);
        if (!denied) {
          expect(server.saved!['lot'], 7);
          expect(server.saved!['categorie'], 3);
          expect(server.saved!['montant'], '12.34');
          expect(server.saved!['note'], 'Note fictive');
          expect(server.saved!.keys.toSet(), {
            'lot',
            'categorie',
            'montant',
            'note',
            'date',
          });
        }
        if (condition == 'success') {
          expect(
            find.text('Dépense confirmée par le serveur.'),
            findsOneWidget,
          );
        }
        if (condition == 'lost' || condition == 'server-device-refusal') {
          expect(find.textContaining('Résultat non confirmé'), findsOneWidget);
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          await tester.pump(const Duration(minutes: 6));
          expect(server.posts, 1);
        }
        await tester.pumpWidget(const SizedBox());
        server.api.close();
      },
    );
  }
  testWidgets(
    'online form shares precision validation and never rounds an invalid amount',
    (tester) async {
      final server = OnlineExpenseServer();
      await tester.pumpWidget(
        testApp(AddDepenseScreen(apiService: server.api)),
      );
      await tester.pumpAndSettle();
      await selectExpense(tester);
      await tester.enterText(find.byKey(const Key('expense-amount')), '12.345');
      await tester.ensureVisible(find.byKey(const Key('expense-submit')));
      await tester.tap(find.byKey(const Key('expense-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Deux décimales au maximum.'), findsOneWidget);
      expect(server.posts, 0);
      await tester.pumpWidget(const SizedBox());
      server.api.close();
    },
  );
}

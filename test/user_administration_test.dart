import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:app_elevage/services/initial_password.dart';
import 'package:app_elevage/services/user_administration_service.dart';
import 'package:app_elevage/screens/user_management_screen.dart';
import 'package:app_elevage/screens/initial_password_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';

Map<String, dynamic> caps(String role) => {
  'user': 1,
  'exploitation': 7,
  'role': role,
  'membership': {'version': 1},
  'user_administration_contract': 1,
  'permission_contract': {
    'version': 1,
    'user': 1,
    'exploitation': 7,
    'role': role,
    'rights_version': 1,
    'permissions': ['finance.read', if (role == 'OWNER') 'users.manage'],
  },
};
Map<String, dynamic> employee({
  int version = 1,
  bool active = true,
  List<String>? rights,
}) => {
  'id': 2,
  'user': 2,
  'exploitation': 7,
  'username': 'Jean',
  'display_name': 'Jean terrain',
  'role': 'OPERATEUR',
  'is_active': active,
  'version': version,
  'password_change_required': true,
  'permissions': rights ?? ['purchases.create'],
};

class AdminApi extends ApiService {
  String role = 'OWNER';
  bool unavailable = false;
  List<Map<String, dynamic>> rows = [employee()];
  int writes = 0;
  Map<String, dynamic>? last;
  bool conflict = false;
  @override
  Future<dynamic> get(String path) async {
    if (unavailable) {
      throw const ApiConnectionException();
    }
    return path.contains('capabilities') ? caps(role) : rows;
  }

  @override
  Future<dynamic> post(String path, Map<String, dynamic> data) async {
    writes++;
    last = Map.from(data)
      ..remove('password')
      ..remove('new_password');
    return employee(
      version: 2,
      rights: List<String>.from(data['permissions'] ?? ['purchases.create']),
    );
  }

  @override
  Future<dynamic> patch(String path, Map<String, dynamic> data) async {
    if (conflict) {
      throw StateError('MEMBERSHIP_VERSION_CONFLICT');
    }
    writes++;
    last = Map.from(data);
    return employee(
      version: 2,
      active: data['is_active'] ?? true,
      rights: List<String>.from(data['permissions'] ?? ['purchases.create']),
    );
  }
}

class MemoryTokens implements TokenStore {
  String? saved;
  @override
  Future<void> saveToken(String token) async {
    saved = token;
  }

  @override
  Future<String?> getToken() async => saved;
  @override
  Future<void> clearToken() async {
    saved = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final bytes = await File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/${font.value}',
      ).readAsBytes();
      final loader = FontLoader(font.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = 'synthetic-owner';
    globalToken = null;
  });
  tearDown(() {
    ApiService.token = null;
    globalToken = null;
  });
  test(
    'administration rejects operator direct access and changed session',
    () async {
      final api = AdminApi()..role = 'OPERATEUR';
      final service = UserAdministrationService(api);
      await expectLater(service.initialize(), throwsStateError);
      await expectLater(
        service.create({'password': 'synthetic'}),
        throwsStateError,
      );
      expect(api.writes, 0);
      api.role = 'OWNER';
      await service.initialize();
      ApiService.token = 'another-person';
      await expectLater(
        service.update(employee(), {'permissions': []}),
        throwsStateError,
      );
      expect(api.writes, 0);
      api.close();
    },
  );
  test(
    'server confirmed versions creation rights deactivation and reset',
    () async {
      final api = AdminApi();
      final service = UserAdministrationService(api);
      await service.initialize();
      final created = await service.create({
        'username': 'Jean',
        'password': 'Synthetic-Initial-927!',
        'permissions': ['purchases.create'],
      });
      expect(created['version'], 2);
      final updated = await service.update(employee(), {'permissions': []});
      expect(api.last!['expected_version'], 1);
      expect(updated['permissions'], isEmpty);
      expect(
        (await service.update(employee(), {'is_active': false}))['is_active'],
        isFalse,
      );
      expect(
        (await service.update(employee(active: false), {
          'is_active': true,
        }))['is_active'],
        isTrue,
      );
      expect(
        (await service.reset(
          employee(),
          'Synthetic-Reset-832!',
        ))['password_change_required'],
        isTrue,
      );
      expect(api.last, isNot(contains('new_password')));
      api.conflict = true;
      await expectLater(
        service.update(employee(), {'permissions': []}),
        throwsStateError,
      );
      api.close();
    },
  );
  test(
    'initial login stores neither password nor limited authorization',
    () async {
      final store = MemoryTokens();
      final api = ApiService(
        tokenStore: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/token/')) {
            return http.Response(
              '{"password_change_required":true,"change_token":"synthetic-limited"}',
              200,
            );
          }
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode(request.body)['change_token'], 'synthetic-limited');
          return http.Response(
            '{"password_changed":true,"login_required":true}',
            200,
          );
        }),
      );
      await expectLater(
        api.login('Jean', 'Synthetic-Initial-827!'),
        throwsA(isA<InitialPasswordRequired>()),
      );
      expect(store.saved, isNull);
      expect(ApiService.token, isNull);
      await api.changeInitialPassword(
        'synthetic-limited',
        'Synthetic-Personal-836!',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(store.saved, isNull);
      api.close();
    },
  );
  test('explicit personal online transition replaces owner access with only the authenticated operator token', () async {
    SharedPreferences.setMockInitialValues({});
    final store=TokenService(useSecureStorage:false);
    final api=ApiService(tokenStore:store);
    ApiService.token='synthetic-owner';globalToken='synthetic-owner';
    await api.usePersonalOnlineSession('synthetic-operator',' operator ');
    expect(ApiService.token,'synthetic-operator');
    expect(globalToken,'synthetic-operator');
    expect(await store.getToken(),'synthetic-operator');
    expect((await SharedPreferences.getInstance()).getString('username'),'operator');
    await api.logout();api.close();
  });
  test('generation uses four digit operator codes', () {
    final values = List.generate(
      20,
      (_) => UserAdministrationService.generatePassword(),
    );
    expect(values.every((value) => RegExp(r'^\d{4}$').hasMatch(value)), isTrue);
    expect(values.every((value) => value.length == 4), isTrue);
  });
  testWidgets(
    'direct operator screen has no employee data or enabled administration',
    (tester) async {
      final api = AdminApi()..role = 'OPERATEUR';
      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementScreen(service: UserAdministrationService(api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Jean terrain'), findsNothing);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Ajouter un utilisateur'),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(const ValueKey('adminError')), findsOneWidget);
      api.close();
    },
  );
  testWidgets(
    'owner list remains visible offline and versions are not falsely updated',
    (tester) async {
      final api = AdminApi();
      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementScreen(service: UserAdministrationService(api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Jean terrain'), findsOneWidget);
      api.unavailable = true;
      await tester.tap(find.byTooltip('Actualiser'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jean terrain'), findsOneWidget);
      expect(find.byKey(const ValueKey('adminError')), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.close();
    },
  );
  testWidgets('settings exposes management only to authenticated owner', (
    tester,
  ) async {
    final api = AdminApi()..role = 'OPERATEUR';
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(apiService: api)));
    await tester.pumpAndSettle();
    expect(find.text('Création des utilisateurs'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.role = 'OWNER';
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(apiService: api)));
    await tester.pumpAndSettle();
    expect(find.text('Création des utilisateurs'), findsOneWidget);
    api.close();
  });
  testWidgets('responsive phone and landscape tablet with synthetic preview', (
    tester,
  ) async {
    final api = AdminApi();
    final boundary = GlobalKey();
    for (final size in [const Size(360, 740), const Size(740, 360), const Size(800, 1280), const Size(1280, 800)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(primarySwatch: Colors.green),
          home: RepaintBoundary(
            key: boundary,
            child: UserManagementScreen(
              service: UserAdministrationService(api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 1280) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../reports/9a2b-interface-utilisateurs.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
    api.close();
  });
  testWidgets(
    'creation grouped permissions and no clear text password retained',
    (tester) async {
      final api = AdminApi();
      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementScreen(service: UserAdministrationService(api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Ajouter un utilisateur'),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Paul');
      await tester.enterText(fields.at(1), 'Paul');
      await tester.enterText(fields.at(3), 'Synthetic-Initial-273!');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: fields.at(3),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tester.ensureVisible(find.text('Achats'));
      await tester.tap(find.text('Achats'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('permission:purchases.create')),
      );
      await tester.tap(
        find.byKey(const ValueKey('permission:purchases.create')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continuer'));
      await tester.pumpAndSettle();
      expect(api.last!['permissions'], ['purchases.create']);
      expect(api.last, isNot(contains('password')));
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
      api.close();
    },
  );
  testWidgets(
    'initial password screen keeps business access out until explicit relogin',
    (tester) async {
      final api = ApiService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InitialPasswordScreen(
            api: api,
            changeToken: 'synthetic-limited',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).obscureText,
        isTrue,
      );
      expect(find.text('Choisissez le code personnel que vous utiliserez pour vous connecter.'), findsOneWidget);
      api.close();
    },
  );
  testWidgets(
    'revocation is confirmed and conflicting update retains previous rights',
    (tester) async {
      final api = AdminApi();
      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementScreen(service: UserAdministrationService(api)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> editAndConfirm() async {
        await tester.tap(find.text('Modifier les droits'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Achats'));
        await tester.tap(find.text('Achats'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('permission:purchases.create')),
        );
        await tester.tap(
          find.byKey(const ValueKey('permission:purchases.create')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vérifier et appliquer'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmer'));
        await tester.pumpAndSettle();
      }

      await editAndConfirm();
      expect(find.textContaining('0 droits attribués'), findsOneWidget);
      expect(api.last!['expected_version'], 1);
      api.conflict = true;
      await editAndConfirm();
      expect(find.textContaining('0 droits attribués'), findsOneWidget);
      expect(find.byKey(const ValueKey('adminError')), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.close();
    },
  );
  testWidgets('deactivate and reactivate only after confirmation', (
    tester,
  ) async {
    final api = AdminApi();
    await tester.pumpWidget(
      MaterialApp(
        home: UserManagementScreen(service: UserAdministrationService(api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Désactiver'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmer'));
    await tester.pumpAndSettle();
    expect(find.text('Réactiver'), findsOneWidget);
    await tester.tap(find.text('Réactiver'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmer'));
    await tester.pumpAndSettle();
    expect(find.text('Désactiver'), findsOneWidget);
    expect(api.writes, 2);
    expect(tester.takeException(), isNull);
    api.close();
  });
}

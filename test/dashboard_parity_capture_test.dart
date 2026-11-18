import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/theme/design_system_v2.dart';

class ParityApi extends ApiService {
  ParityApi()
    : super(client: MockClient((_) async => http.Response('{}', 503)));
  final reads = <String>[];
  @override
  Future<bool> probeServer() async => true;
  @override
  Future<Map<String, dynamic>> getDashboard({int? especeId}) async => {
    'kpis': {
      'stock': 120,
      'chiffre_affaires': 245000,
      'depenses': 87000,
      'marge': 158000,
    },
  };
  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async => getDashboard();
  @override
  Future<List<dynamic>> getLots() async => [
    {
      'id': 11,
      'nom': 'Lot fictif',
      'espece': 4,
      'espece_nom': 'Poulet',
      'type_production': 'CHAIR',
      'stock': 120,
    },
  ];
  @override
  Future<List<dynamic>> getEspeces() async => [
    {'id': 4, 'nom': 'Poulet'},
  ];
  @override
  Future<List<dynamic>> getTasks() async => [];
  @override
  Future<double> getTotalDettes() async => 12000;
  @override
  Future<dynamic> get(String path) async {
    reads.add(path);
    if (path == '/farm-profile/')
      return {'nom': 'Ferme fictive — comparaison locale'};
    if (path == '/me/capabilities/')
      return {
        'user': 1,
        'exploitation': 1,
        'role': 'OWNER',
        'membership': {'version': 1},
        'permission_contract': {
          'version': 2,
          'user': 1,
          'exploitation': 1,
          'role': 'OWNER',
          'rights_version': 1,
          'permissions': PermissionContract.catalogue
              .where((p) => p != 'agenda.progress')
              .toList(),
        },
      };
    if (path.startsWith('/feed-supplies/'))
      return {
        'exploitation': 1,
        'as_of': '2026-11-16T12:00:00Z',
        'products': [
          {
            'id': 'feed',
            'name': 'Croissance',
            'archived': false,
            'alert_threshold': '50.000',
            'positions': [
              {
                'species_id': 4,
                'lot_id': null,
                'kg': '250.000',
                'pending_kg': '0.000',
              },
            ],
          },
        ],
      };
    if (path == '/vaccine-supplies/')
      return {
        'exploitation': 1,
        'as_of': '2026-11-16T12:00:00Z',
        'products': [],
        'vials': [],
      };
    if (path == '/tasks/') return [];
    throw StateError('Unmocked endpoint: $path');
  }
}

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await fonts.load();
    final sdk = Platform.environment['FLUTTER_ROOT'];
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
  });
  for (final size in [
    const Size(1280, 800),
    const Size(800, 1280),
    const Size(1024, 768),
    const Size(640, 400),
  ]) {
    testWidgets('synthetic dashboard ${size.width}x${size.height}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'username': 'Démonstration locale',
      });
      AppSettings.instance.languageCode = 'fr';
      ApiService.token = 'synthetic-parity-only';
      globalToken = ApiService.token;
      final api = ParityApi(), key = GlobalKey();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: designSystemV2(),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RepaintBoundary(
            key: key,
            child: DashboardScreen(apiService: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Future<void> capture(String suffix) async {
        final dir = Platform.environment['PARITY_CAPTURE_DIR'];
        if (dir == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$dir/${size.width.toInt()}x${size.height.toInt()}-$suffix.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      await capture('dashboard');
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -480),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('agenda');
      await tester.tap(find.byIcon(Icons.menu).first);
      await tester.pumpAndSettle();
      await capture('menu');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.close();
      ApiService.token = null;
      globalToken = null;
    });
  }
}

import 'package:app_elevage/services/app_settings.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/aquatic_revenue_screen.dart';
import 'package:app_elevage/pisciculture/aquatic_expense_screen.dart';
import 'package:app_elevage/pisciculture/aquatic_clients_screen.dart';
import 'package:app_elevage/theme/design_system_v2.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic;

class DetailService extends FakeAquatic {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> read(String path) async {
    calls.add(path);
    if (path.startsWith('finance-detail/'))
      return {
        'billed_revenue': '1850000.00',
        'cohorts': [
          {
            'id': 'a',
            'name': 'Tilapia A',
            'revenue': '1850000.00',
            'investment': null,
          },
        ],
        'categories': [
          {'name': 'Aliments', 'amount': '400000.00'},
          {'name': 'Entretien', 'amount': '120000.00'},
          {'name': 'Énergie', 'amount': '100000.00'},
        ],
      };
    return super.read(path);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    calls.add(path);
    if (path.startsWith('finance-client-ledger/'))
      return [
        for (final n in [1, 2, 3])
          {
            'id': '$n',
            'sale_id': n,
            'date': '2026-11-20',
            'client': n,
            'client_name': 'Client Démo $n',
            'client_phone': '000 000 00$n',
            'amount': '750000.10',
            'paid_as_of': '600000.00',
            'balance_as_of': '150000.10',
            'payments': [],
          },
      ];
    return super.list(path);
  }
}

class CatalogDetailService extends DetailService {
  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    if (path.startsWith('commerce-clients/'))
      return [
        {'id': 9, 'nom': 'Client sans facture', 'telephone': '000 000 009'},
      ];
    return super.list(path);
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('money projection is exact and invalid values are never zero', () {
    expect(aquaticCents('0.10') + aquaticCents('0.20'), BigInt.from(30));
    expect(() => aquaticCents(null), throwsFormatException);
    expect(() => aquaticCents('1.001'), throwsFormatException);
    AppSettings.instance.languageCode = 'fr';
    AppSettings.instance.currencyCode = 'XAF';
    expect(
      aquaticMoney(BigInt.parse('9007199254740993')),
      '90\u202f071\u202f992\u202f547\u202f409,93 FCFA',
    );
  });
  testWidgets(
    'client menu retains identities without aquatic invoices and creates no synthetic invoice',
    (t) async {
      final service = CatalogDetailService();
      await t.pumpWidget(
        MaterialApp(
          theme: designSystemV2(),
          home: AquaticClientsScreen(
            service: service,
            filters: const {},
            canPay: false,
            includeAllClients: true,
            canCreate: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byTooltip('Nouveau client'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'sans facture');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Client sans facture'));
      await t.tap(find.text('Client sans facture'));
      await t.pumpAndSettle();
      expect(find.textContaining('FAC-null'), findsNothing);
      expect(find.text('Client sans facture'), findsOneWidget);
      expect(service.writes, isEmpty);
    },
  );
  for (final size in [
    const Size(1910, 1000),
    const Size(1366, 900),
    const Size(768, 1100),
    const Size(390, 1000),
  ]) {
    for (final kind in ['revenue', 'expenses', 'clients']) {
      testWidgets('$kind responsive $size', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final service = DetailService(), boundary = GlobalKey();
        final screen = kind == 'revenue'
            ? AquaticRevenueScreen(service: service, filters: const {})
            : kind == 'expenses'
            ? AquaticExpenseScreen(
                service: service,
                filters: const {},
                lotNom: 'Tilapia A',
              )
            : AquaticClientsScreen(
                service: service,
                filters: const {},
                canPay: false,
              );
        await t.pumpWidget(
          MaterialApp(
            theme: designSystemV2().copyWith(
              splashFactory: InkRipple.splashFactory,
            ),
            home: RepaintBoundary(key: boundary, child: screen),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (kind == 'revenue') {
          expect(find.text('Investissement'), findsNWidgets(2));
          expect(find.text('—'), findsNWidgets(3));
          expect(find.text('Comparaison par cohorte'), findsOneWidget);
        }
        if (kind == 'expenses')
          expect(find.text('Dépenses de la cohorte'), findsOneWidget);
        if (kind == 'clients') {
          expect(find.text('Total facturé'), findsOneWidget);
          expect(find.text('Rechercher par nom ou téléphone'), findsWidgets);
          await t.enterText(find.byType(TextField), 'absent');
          await t.pumpAndSettle();
          expect(find.text('Aucun client.'), findsOneWidget);
          await t.enterText(find.byType(TextField), '');
          await t.pumpAndSettle();
        }
        final output = Directory('D:/ElevAge-Final-20261120/screenshots');
        output.createSync(recursive: true);
        if (kind == 'clients' && size.width == 390) {
          final billed = t.getRect(
            find.text(aquaticMoney(BigInt.from(75000010))).first,
          );
          final paid = t.getRect(
            find.text(aquaticMoney(BigInt.from(60000000))).first,
          );
          final due = t.getRect(
            find.text(aquaticMoney(BigInt.from(15000010))).first,
          );
          expect(paid.left - billed.right, greaterThanOrEqualTo(7));
          expect(due.left - paid.right, greaterThanOrEqualTo(7));
        }
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${output.path}/$kind-${size.width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}

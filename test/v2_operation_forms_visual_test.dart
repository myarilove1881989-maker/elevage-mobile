import 'package:flutter/foundation.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/screens/add_achat_screen.dart';
import 'package:app_elevage/screens/add_mouvement_screen.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/client_detail_screen.dart';
import 'package:app_elevage/screens/client_list_screen.dart';
import 'package:app_elevage/screens/egg_production_screen.dart';
import 'package:app_elevage/screens/growth_tracking_screen.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'package:app_elevage/screens/vaccination_screen.dart';
import 'package:app_elevage/screens/health_agenda_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/theme/design_system_v2.dart';
import 'mobile_layout_test.dart' show MobileApiFake;
import 'production_tracking_test.dart' show testApp;
import 'sale_product_test.dart' show SaleApiFake;
import 'online_expense_form_test.dart' show OnlineExpenseServer, selectExpense;
import 'feed_purchase_form_test.dart' show fillFeed;
import 'web_procurement_regression_test.dart' show fillVaccine;
import 'health_agenda_form_test.dart' show HealthAgendaApi;
import 'vaccine_form_test.dart' show VaccineApi;
import 'feed_distribution_test.dart' show FeedApiFake;

const captureEnabled = bool.fromEnvironment(
  'AUDIT_CAPTURE',
  defaultValue: false,
);
const phase = String.fromEnvironment('AUDIT_PHASE', defaultValue: 'after');

class AuditApi extends MobileApiFake {
  bool owner = false;
  int writes = 0;
  @override
  Future<dynamic> get(String path) async {
    if(path=='/memberships/')return [{'user':2,'username':'jean-fictif','role':'OPERATEUR','is_active':true,'exploitation':1}];
    if (path == '/farm-profile/') return {'id': 1, 'nom': 'Ferme fictive'};
    if (path == '/me/capabilities/') {
      final role = owner ? 'OWNER' : 'OPERATEUR';
      return {
        'user': 1,
        'exploitation': 1,
        'role': role,
        'offline_policy_enabled': false,
        'membership': {'version': 1},
        'permission_contract': {
          'version': owner ? 2 : 1,
          'user': 1,
          'exploitation': 1,
          'role': role,
          'rights_version': 1,
          'permissions': [
            'finance.read',
            'purchases.create',
            'expenses.create',
            'egg_collections.create',
            'egg_sales.create',
            'weights.create',
            'cash.create',
            'clients.create',
            'history.read','agenda.plan',
          ],
        },
      };
    }
    return super.get(path);
  }

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    writes++;
    throw StateError('Visual audit forbids writes');
  }
}

Widget app(Widget child) {
  final base = testApp(child) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: designSystemV2(ThemeData(fontFamily: 'Roboto')),
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    home: child,
  );
}

Future<void> visible(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty)
    await t.scrollUntilVisible(
      finder,
      100,
      maxScrolls: 100,
      scrollable: find.byType(Scrollable).first,
    );
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await visible(t, finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String family, double width) async {
  final initialError = t.takeException();
  if (phase == 'after') {
    expect(initialError, isNull, reason: '$family initial viewport');
  } else if (initialError != null) {
    print('RECORDED_BASELINE_RENDER_ERROR $family $width: $initialError');
  }
  // Full form at the actual phone/desktop width, with the screen also tested at 1000 px height.
  if (find.byType(Dialog).evaluate().isEmpty &&
      find.byType(BottomSheet).evaluate().isEmpty) {
    final candidates = t
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((s) => s.position.axis == Axis.vertical)
        .toList();
    if (candidates.isNotEmpty) {
      final extent = candidates
          .map((s) => s.position.maxScrollExtent)
          .fold<double>(0, (a, b) => a > b ? a : b);
      if (extent > 0) {
        t.view.physicalSize = Size(
          width,
          (1000 + extent + 80).clamp(1000, 3000),
        );
        await t.pumpAndSettle();
      }
    }
  }
  for (final state in t.stateList<ScrollableState>(find.byType(Scrollable))) {
    if (state.position.axis == Axis.vertical) state.position.jumpTo(0);
  }
  await t.pumpAndSettle();
  final fullError = t.takeException();
  if (phase == 'after') expect(fullError, isNull, reason: '$family full form');
  if (captureEnabled)
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        Uri.file(
          'D:/ElevAge-Dev/mobile/.local/form-audit/$phase/$family-${width.toInt()}.png',
        ),
      ),
    );
  if (phase == 'after') {
    final inputs = t
        .widgetList<InputDecorator>(find.byType(InputDecorator))
        .toList();
    if (family != 'facturation')
      expect(
        inputs,
        isNotEmpty,
        reason: 'Real operation fields must be rendered: $family',
      );
    for (final field in inputs) {
      final border = field.decoration.enabledBorder;
      expect(border, isA<OutlineInputBorder>(), reason: family);
      final outline = border! as OutlineInputBorder;
      expect(outline.borderRadius, BorderRadius.circular(16), reason: family);
      expect(outline.borderSide.color, V2Colors.border, reason: family);
      expect(outline.borderSide.width, 1.25, reason: family);
      expect(
        field.decoration.labelText,
        isNotEmpty,
        reason: 'Permanent readable label: $family',
      );
    }
  }
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    if(!kIsWeb){
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = 'synthetic-employee';
    globalToken = null;
    AppSettings.instance.languageCode = 'fr';
  });
  tearDown(() {
    ApiService.token = null;
    globalToken = null;
    ApiService.clearLocalPresentationIdentity();
  });
  for (final width in [360.0, 768.0, 1440.0]) {
    void screen(String family, Future<void> Function(WidgetTester) body) {
      testWidgets('$phase $family $width', (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await body(t);
        await capture(t, family, width);
      });
    }

    for (final family in ['lot_creation', 'achat_animaux'])
      screen(family, (t) async {
        final api = AuditApi();
        addTearDown(api.close);
        await t.pumpWidget(app(AddAchatScreen(apiService: api)));
        await t.pumpAndSettle();
        await t.enterText(
          find.byType(TextFormField).first,
          family == 'lot_creation' ? 'Lot CH-100 fictif' : 'Nouveau lot acheté',
        );
        await t.enterText(find.byType(TextFormField).at(1), 'Poulet');
        await t.pumpAndSettle();
        await tap(t, find.text('Poulet').last);
      });
    for (final family in ['depense', 'achat_aliment', 'achat_vaccin'])
      screen(family, (t) async {
        final server = OnlineExpenseServer()
          ..feed = family == 'achat_aliment'
          ..vaccine = family == 'achat_vaccin';
        addTearDown(server.api.close);
        await t.pumpWidget(app(AddDepenseScreen(apiService: server.api)));
        await t.pumpAndSettle();
        if (family == 'achat_aliment') {
          await fillFeed(t);
        } else if (family == 'achat_vaccin') {
          await fillVaccine(t);
        } else {
          await selectExpense(t);
        }
        expect(server.posts, 0);
      });
    screen('distribution', (t) async {
      final api = FeedApiFake();
      addTearDown(api.close);
      await t.pumpWidget(
        app(
          FeedDistributionFormScreen(
            apiService: api,
            lotId: 1,
            lotName: 'Lot CH-100 fictif',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('feedQuantityField')), '20');
    });
    screen('vaccination', (t) async {
      final api = VaccineApi();
      addTearDown(api.close);
      await t.pumpWidget(app(VaccinationForm(api: api, lotId: 10)));
      await t.pumpAndSettle();
      await tap(t, find.byKey(const Key('vaccination-product')));
      await tap(t, find.text('Vaccin test').last);
    });
    screen('ponte_collecte', (t) async {
      final api = AuditApi();
      addTearDown(api.close);
      await t.pumpWidget(
        app(
          EggProductionScreen(
            apiService: api,
            lotId: 10,
            lotName: 'Pondeuses fictives',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Nouvelle collecte'));
    });
    screen('production_pesee', (t) async {
      final api = AuditApi();
      addTearDown(api.close);
      await t.pumpWidget(
        app(
          GrowthTrackingScreen(
            apiService: api,
            lotId: 11,
            lotName: 'Lot CH-100 fictif',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Ajouter une pesée'));
    });
    screen('mouvement', (t) async {
      final api = SaleApiFake();
      addTearDown(api.close);
      await t.pumpWidget(app(AddMouvementScreen(apiService: api)));
      await t.pumpAndSettle();
    });
    screen('vente', (t) async {
      final api = SaleApiFake();
      addTearDown(api.close);
      await t.pumpWidget(app(AddMouvementScreen(apiService: api)));
      await t.pumpAndSettle();
      await tap(t, find.byKey(const Key('movementLotDropdown')));
      await tap(t, find.textContaining('Chair A').last);
    });
    if (phase == 'after') {
      for (final entry in {
        'mortalite': 'MORTALITE',
        'naissance': 'NAISSANCE',
        'don': 'DON',
        'vol': 'VOL',
      }.entries) {
        screen(entry.key, (t) async {
          final api = SaleApiFake();
          addTearDown(api.close);
          await t.pumpWidget(app(AddMouvementScreen(apiService: api)));
          await t.pumpAndSettle();
          final field = find.byKey(const Key('movementTypeDropdown'));
          final label = {
            'MORTALITE': 'Mortalité',
            'NAISSANCE': 'Naissance',
            'DON': 'Don',
            'VOL': 'Vol',
          }[entry.value]!;
          await tap(t, field);
          await tap(t, find.text(label).last);
          await tap(t, find.byKey(const Key('movementLotDropdown')));
          await tap(
            t,
            find
                .text(entry.key == 'naissance' ? 'Reproduction' : 'Chair A')
                .last,
          );
          expect(api.movementType, isNull);
          expect(api.birthLot, isNull);
        });
      }
      screen('vente_oeufs', (t) async {
        final api = SaleApiFake();
        addTearDown(api.close);
        await t.pumpWidget(app(AddMouvementScreen(apiService: api)));
        await t.pumpAndSettle();
        await tap(t, find.byKey(const Key('saleProductDropdown')));
        await tap(t, find.text('Œufs').last);
        await tap(t, find.byKey(const Key('movementLotDropdown')));
        await tap(t, find.text('Pondeuses A').last);
        await tap(t, find.byKey(const Key('movementClientDropdown')));
        await tap(t, find.text('Restaurant').last);
        expect(api.eggLot, isNull);
      });
    }
    for (final family in ['paiement', 'facturation'])
      screen(family, (t) async {
        final api = AuditApi();
        addTearDown(api.close);
        await t.pumpWidget(
          app(
            ClientDetailScreen(
              apiService: api,
              clientId: 1,
              nom: 'Client fictif',
              telephone: '0000000000',
            ),
          ),
        );
        await t.pumpAndSettle();
        await tap(
          t,
          family == 'paiement'
              ? find.text('Payer').last
              : find.text('Facture partielle').last,
        );
      });
    if(phase=='after')screen('agenda_general',(t)async{
      final api=AuditApi()..owner=true;addTearDown(api.close);
      await t.pumpWidget(app(DashboardScreen(apiService:api)));await t.pumpAndSettle();
      await tap(t,width<1100?find.byTooltip('Ajouter une tâche'):find.text('Ajouter').last);await tap(t,find.text('Répéter sur plusieurs jours'));
      await t.enterText(find.byKey(const Key('agendaTaskTitle')),'Contrôle fictif des abreuvoirs');
      expect(api.writes,0);
    });
    screen('agenda_sanitaire', (t) async {
      final api = HealthAgendaApi();
      addTearDown(api.close);
      await t.pumpWidget(app(HealthPlanForm(api: api, lotId: 10)));
      await t.pumpAndSettle();
    });
    screen('parametres', (t) async {
      final api = AuditApi()..owner = true;
      addTearDown(api.close);
      await t.pumpWidget(app(SettingsScreen(apiService: api)));
      await t.pumpAndSettle();
    });
    screen('client_creation', (t) async {
      final api = AuditApi();
      addTearDown(api.close);
      await t.pumpWidget(app(ClientListScreen(apiService: api)));
      await t.pumpAndSettle();
      await tap(t, find.byType(FloatingActionButton));
    });
  }
}

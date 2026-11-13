import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/finance_agenda_panel.dart';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'package:app_elevage/services/api_service.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic, installations, cohorts;
import 'production_tracking_test.dart' show testApp;

const linkId = '91000000-0000-4000-8000-000000000001',
    taskId = '92000000-0000-4000-8000-000000000001',
    actId = '93000000-0000-4000-8000-000000000001';
final categories = <Map<String, dynamic>>[
  {'id': 6, 'name': 'Entretien'},
];
Map<String, dynamic> cost() => {
  'id': linkId,
  'expense_id': 65,
  'amount': '10.25',
  'date': '2026-11-13',
  'category': 6,
  'category_name': 'Entretien',
  'scope': 'COHORT',
  'cohort': cohorts.first['id'],
  'cohort_name': 'Novembre',
  'installation': null,
  'note': 'Données fictives',
  'version': 1,
  'economic_editable': true,
  'source': 'MANUAL_EXPENSE',
};
Map<String, dynamic> task() => {
  'id': taskId,
  'task_id': 42,
  'version': 1,
  'title': 'Contrôle libre',
  'kind': 'OTHER',
  'date': '2026-11-15',
  'scheduled_at': null,
  'reminder_at': null,
  'cohort': cohorts.first['id'],
  'installation': installations.first['id'],
  'description': 'Données fictives de qualification',
  'status': 'TODO',
  'actor': 1,
  'actor_name': 'Éleveur fictif',
  'actual_id': null,
  'report': '',
};
final totals = <String, dynamic>{
  'billed_revenue': '187.50',
  'aquatic_expenses': '40.25',
  'direct_expenses': '10.25',
  'estimated_result': '147.25',
  'received_payments': '75.00',
  'client_balance_as_of': '112.50',
  'aquatic_common_expenses': '30.00',
  'farm_common_expenses': '20.00',
  'limits': [
    'Résultat indicatif, pas un bénéfice net comptable.',
    'Les coûts communs restent séparés et ne sont jamais répartis automatiquement.',
  ],
  'categories': [
    {'name': 'Entretien', 'amount': '40.25'},
  ],
};

class FakePlanning extends FakeAquatic {
  bool interrupt = false;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> read(String p) async {
    paths.add(p);
    if (offline) throw const ApiConnectionException();
    if (p.startsWith('finance-summary/')) return totals;
    if (p.startsWith('finance-categories/')) return {'categories': categories};
    return super.read(p);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String p) async {
    paths.add(p);
    if (offline) throw const ApiConnectionException();
    if (p.startsWith('finance-expenses/')) {
      return [
        cost(),
        {
          ...cost(),
          'id': null,
          'expense_id': 66,
          'scope': 'FARM',
          'cohort': null,
          'installation': null,
          'source': 'SUPPLY_RECEIPT',
          'economic_editable': false,
          'amount': '20.00',
        },
      ];
    }
    if (p.startsWith('finance-revenues/')) {
      return [
        {
          'id': 'sale',
          'invoice_reference': 'FAC-2026-00123',
          'date': '2026-11-13',
          'client_name': 'Client fictif',
          'amount': '187.50',
          'paid_as_of': '75.00',
          'balance_as_of': '112.50',
          'cohort_name': 'Novembre',
          'installation_name': 'Bassin Nord',
          'payments': [
            {'date': '2026-11-13', 'amount': '75.00'},
          ],
        },
      ];
    }
    if (p.startsWith('agenda/')) return [task()];
    if (p.startsWith('agenda-history/') || p.startsWith('finance-history/')) {
      return [
        {
          'id': 1,
          'actor': 1,
          'reason': 'Motif conservé',
          'date': '2026-11-13T10:00:00Z',
          'before': {'title': 'Ancien titre'},
          'after': {'title': 'Nouveau titre'},
        },
      ];
    }
    if (p.startsWith('water-readings/')) {
      return [
        {
          'id': actId,
          'occurred_at': '2026-11-13T09:00:00Z',
          'installation_name': 'Bassin Nord',
          'note': 'Relevé réel',
        },
      ];
    }
    return super.list(p);
  }

  @override
  Future<Map<String, dynamic>> send(String p, Map<String, dynamic> body) async {
    paths.add(p);
    writes.add(Map<String, dynamic>.from(body));
    if (interrupt) throw const ApiConnectionException();
    return {'id': 'accepted'};
  }
}

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> fill(WidgetTester t, String label, String value) async {
  final f = input(label);
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> click(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, String label, String text) async {
  final f = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == label,
  );
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Widget app(Widget home, {double scale = 1}) {
  final base = testApp(home) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    home: Scaffold(
      backgroundColor: const Color(0xFFFCF7FF),
      body: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: home,
        ),
      ),
    ),
  );
}

Widget editor(FakePlanning f, String mode, {double scale = 1}) => app(
  PlanningEditor(
    service: f,
    mode: mode,
    owner: true,
    installations: installations,
    cohorts: cohorts,
    categories: categories,
    row: mode == 'EXPENSE_EDIT' || mode == 'ASSIGN'
        ? cost()
        : mode == 'TASK_EDIT' || mode == 'STATUS'
        ? task()
        : null,
    initialCohort: cohorts.first['id'] as String,
  ),
  scale: scale,
);
Future<void> size(WidgetTester t, double w, {double h = 1100}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> capture(WidgetTester t, String name) async {
  final dir = Platform.environment['ELEVAGE_PHASE3D_CAPTURES'];
  if (dir == null) return;
  await t.runAsync(() async {
    final image = await t
        .renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first)
        .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    for (final pair in [
      ['Roboto', 'Roboto-Regular.ttf'],
      ['MaterialIcons', 'MaterialIcons-Regular.otf'],
    ]) {
      final font = FontLoader(pair[0])
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '$root/bin/cache/artifacts/material_fonts/${pair[1]}',
              ).readAsBytes(),
            ),
          ),
        );
      await font.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final mode in [
    'EXPENSE',
    'EXPENSE_EDIT',
    'ASSIGN',
    'TASK',
    'TASK_EDIT',
    'STATUS',
  ]) {
    for (final width in [360.0, 1080.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$mode $width text $scale', (t) async {
          final f = FakePlanning();
          await size(t, width);
          await t.pumpWidget(
            RepaintBoundary(child: editor(f, mode, scale: scale)),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          if (scale == 1) await capture(t, '$mode-${width.toInt()}');
          f.api.close();
        });
      }
    }
  }
  testWidgets(
    'expense actual save at 360 text2 has no stock or duplicated purchase',
    (t) async {
      final f = FakePlanning();
      await size(t, 360, h: 800);
      await t.pumpWidget(editor(f, 'EXPENSE', scale: 2));
      await t.pumpAndSettle();
      await choose(t, 'Catégorie', 'Entretien');
      await fill(t, 'Montant (XAF)', '10,25');
      await fill(t, 'Motif', 'Coût réellement connu');
      await click(t, 'Enregistrer');
      expect(f.paths.last, 'finance-expenses/');
      expect(f.writes.single['amount'], '10.25');
      expect(f.writes.single['scope'], 'COHORT');
      expect(f.writes.single['installation'], isNull);
      expect(f.writes.single.containsKey('quantity_kg'), false);
      f.api.close();
    },
  );
  testWidgets('shared attribution changes only scope of existing expense', (
    t,
  ) async {
    final f = FakePlanning();
    await t.pumpWidget(editor(f, 'ASSIGN'));
    await choose(t, 'Périmètre', 'Commun à toute l’exploitation');
    await fill(t, 'Motif', 'Usage commun confirmé');
    await click(t, 'Enregistrer');
    expect(f.writes.single['expense'], 65);
    expect(f.writes.single['scope'], 'FARM');
    expect(f.writes.single['cohort'], isNull);
    expect(f.writes.single.containsKey('amount'), false);
    f.api.close();
  });
  testWidgets('new task date only reminder absent and no operation executed', (
    t,
  ) async {
    final f = FakePlanning();
    await size(t, 360, h: 800);
    await t.pumpWidget(editor(f, 'TASK', scale: 2));
    await fill(t, 'Titre', 'Prévoir un contrôle');
    await click(t, 'Enregistrer');
    expect(f.paths.last, 'agenda/');
    expect(f.writes.single['scheduled_at'], isNull);
    expect(f.writes.single['reminder_at'], isNull);
    expect(f.writes.single['kind'], 'OTHER');
    expect(f.writes.single.containsKey('amount'), false);
    f.api.close();
  });
  testWidgets('task completion alone never chooses an actual reference', (
    t,
  ) async {
    final f = FakePlanning();
    await t.pumpWidget(editor(f, 'STATUS'));
    await fill(t, 'Motif', 'Opération vérifiée');
    await click(t, 'Enregistrer');
    expect(f.writes.single['status'], 'DONE');
    expect(f.writes.single['actual_id'], isNull);
    expect(f.writes.single['actual_kind'], '');
    expect(f.paths.last, 'agenda-status/');
    f.api.close();
  });
  testWidgets('chosen existing real act link stays explicit', (t) async {
    final f = FakePlanning();
    await t.pumpWidget(
      app(
        PlanningEditor(
          service: f,
          mode: 'STATUS',
          owner: true,
          installations: installations,
          cohorts: cohorts,
          categories: categories,
          row: {...task(), 'kind': 'WATER'},
        ),
      ),
    );
    await fill(t, 'Motif', 'Relevé réellement effectué');
    await click(t, 'Relier un acte déjà enregistré (facultatif)');
    await click(t, 'Charger les actes existants');
    final fnd = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Acte réalisé',
    );
    await t.ensureVisible(fnd);
    await t.tap(fnd);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Bassin Nord').last);
    await t.pumpAndSettle();
    await click(t, 'Enregistrer');
    expect(f.writes.single['actual_id'], actId);
    expect(f.writes.single['actual_kind'], 'WATER');
    f.api.close();
  });
  testWidgets('reminder toggle does not invent a frequency or date', (t) async {
    final f = FakePlanning();
    await t.pumpWidget(editor(f, 'TASK'));
    await fill(t, 'Titre', 'Contrôle choisi');
    await click(t, 'Rappel visible dans l’application');
    await click(t, 'Enregistrer');
    expect(f.writes, isEmpty);
    expect(find.textContaining('Choisissez explicitement'), findsOneWidget);
    f.api.close();
  });
  testWidgets(
    'unknown network answer retries identical UUID and refuses other author',
    (t) async {
      ApiService.setLocalPresentationIdentity('plan-A');
      addTearDown(ApiService.clearLocalPresentationIdentity);
      final f = FakePlanning()..interrupt = true;
      await t.pumpWidget(editor(f, 'TASK'));
      await fill(t, 'Titre', 'À faire');
      await click(t, 'Enregistrer');
      await click(t, 'Réessayer la même opération');
      expect(f.writes.length, 2);
      expect(f.writes.first, f.writes.last);
      ApiService.setLocalPresentationIdentity('plan-B');
      await click(t, 'Réessayer la même opération');
      expect(f.writes.length, 2);
      f.api.close();
    },
  );
  for (final agenda in [false, true]) {
    for (final width in [360.0, 1080.0]) {
      testWidgets('panel $agenda $width', (t) async {
        final f = FakePlanning();
        await size(t, width);
        await t.pumpWidget(
          RepaintBoundary(
            child: app(
              SingleChildScrollView(
                child: FinanceAgendaPanel(
                  service: f,
                  agenda: agenda,
                  owner: true,
                  rights: const [],
                  installations: installations,
                  cohorts: cohorts,
                  species: const [
                    {'id': 42, 'name': 'Tilapia'},
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await capture(t, '${agenda ? 'agenda' : 'summary'}-${width.toInt()}');
        await click(t, agenda ? 'Rappels' : 'Coûts communs');
        expect(t.takeException(), isNull);
        await capture(t, '${agenda ? 'reminders' : 'common'}-${width.toInt()}');
        f.api.close();
      });
    }
  }
  testWidgets('failed finance reload clears previous private totals', (
    t,
  ) async {
    final f = FakePlanning();
    await t.pumpWidget(
      app(
        SingleChildScrollView(
          child: FinanceAgendaPanel(
            service: f,
            agenda: false,
            owner: false,
            rights: const [],
            installations: installations,
            cohorts: cohorts,
            species: const [],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('187.50 XAF'), findsOneWidget);
    expect(find.text('Ajouter une dépense'), findsNothing);
    f.offline = true;
    await click(t, 'Actualiser');
    expect(find.text('187.50 XAF'), findsNothing);
    expect(find.textContaining('Lecture impossible'), findsOneWidget);
    f.api.close();
  });
  testWidgets('workspace exposes separate existing expense permission', (
    t,
  ) async {
    final f = FakePlanning();
    await t.pumpWidget(
      app(
        AquaticWorkspace(
          service: f,
          capabilities: const {
            'can_enable': false,
            'write': ['aquatic.finances.manage'],
            'finance_write': ['expenses.create'],
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    t
        .state<AquaticWorkspaceState>(find.byType(AquaticWorkspace))
        .showPage('finances');
    await t.pumpAndSettle();
    final p = t.widget<FinanceAgendaPanel>(find.byType(FinanceAgendaPanel));
    expect(p.rights, contains('expenses.create'));
    expect(find.text('Ajouter une dépense'), findsOneWidget);
    f.api.close();
  });
}

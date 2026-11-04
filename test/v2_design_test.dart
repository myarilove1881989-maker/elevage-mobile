import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/widgets/v2_components.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/theme/design_system_v2.dart';
import 'online_expense_form_test.dart' show OnlineExpenseServer;
import 'feed_purchase_form_test.dart' show fillFeed;
import 'web_procurement_regression_test.dart' show fillVaccine;
import 'vaccine_form_test.dart' show reveal;
import 'production_tracking_test.dart' show testApp;

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
  testWidgets(
    'Home protects edited draft, cancellation keeps data, confirmation returns to dashboard',
    (tester) async {
      final input = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => V2Scaffold(
              isDashboard: true,
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => V2Scaffold(
                        protectDraft: true,
                        appBar: const V2AppBar(title: Text('Saisie')),
                        body: V2Field(child: TextField(controller: input)),
                      ),
                    ),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Brouillon');
      await tester.tap(find.text('Accueil'));
      await tester.pumpAndSettle();
      expect(find.text('Quitter la saisie ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      expect(input.text, 'Brouillon');
      await tester.tap(find.text('Accueil'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Quitter'));
      await tester.pumpAndSettle();
      expect(find.text('Ouvrir'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    },
  );
  testWidgets(
    'edited modal confirms cancel and retains the draft when declined',
    (tester) async {
      final input = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialog) => V2AlertDialog(
                    title: const Text('Edition'),
                    content: V2Field(child: TextField(controller: input)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Annuler'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Brouillon');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Quitter la saisie ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      expect(input.text, 'Brouillon');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Quitter'));
      await tester.pumpAndSettle();
      expect(find.text('Edition'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    },
  );
  testWidgets('Home cannot leave an in-flight save', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => V2Scaffold(
            isDashboard: true,
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const V2Scaffold(
                    busy: true,
                    appBar: V2AppBar(title: Text('En cours')),
                  ),
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();
    expect(find.text('En cours'), findsOneWidget);
    expect(find.text('Enregistrement en cours…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final vaccine in [false, true])
    for (final lose in [false, true]) {
      testWidgets(
        '${vaccine ? 'vaccine' : 'feed'} ${lose ? 'uncertain stays' : 'confirmed returns'}',
        (tester) async {
          final server = OnlineExpenseServer()
            ..feed = !vaccine
            ..vaccine = vaccine
            ..lost = lose;
          await tester.pumpWidget(
            testApp(
              Builder(
                builder: (context) => V2Scaffold(
                  isDashboard: true,
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AddDepenseScreen(apiService: server.api),
                        ),
                      ),
                      child: const Text('Nouvel achat'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Nouvel achat'));
          await tester.pumpAndSettle();
          if (vaccine) {
            await fillVaccine(tester);
          } else {
            await fillFeed(tester);
          }
          await tester.tap(find.byKey(const Key('expense-submit')));
          await tester.pumpAndSettle();
          expect(server.posts, 1);
          if (lose) {
            expect(find.byType(AddDepenseScreen), findsOneWidget);
            await reveal(tester, 'feed-retry');
            expect(find.byKey(const Key('feed-retry')), findsOneWidget);
          } else {
            expect(find.byType(AddDepenseScreen), findsNothing);
            expect(find.text('Nouvel achat'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox());
          server.api.close();
        },
      );
    }
  testWidgets(
    'multi-date calendar selects and removes dates without a time field',
    (tester) async {
      var selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          home: StatefulBuilder(
            builder: (context, update) => V2Scaffold(
              body: V2DateSelection(
                selected: selected,
                onChanged: (value) => update(() => selected = value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').first);
      await tester.pumpAndSettle();
      expect(selected.length, 2);
      expect(find.byType(InputChip), findsNWidgets(2));
      tester.widget<InputChip>(find.byType(InputChip).first).onDeleted!();
      await tester.pumpAndSettle();
      expect(selected.length, 1);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'date presentation preserves original instant and hides seconds',
    (tester) async {
      final controller = TextEditingController(
        text: '2026-11-04T12:34:56.123Z',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: V2DateField(
              controller: controller,
              label: 'Date',
              withTime: true,
            ),
          ),
        ),
      );
      expect(controller.text, '2026-11-04T12:34:56.123Z');
      final text = tester
          .widget<EditableText>(find.byType(EditableText))
          .controller
          .text;
      expect(text, contains('04/11/2026'));
      expect(text, isNot(contains(':56')));
      expect(text, isNot(contains('123')));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  for (final width in [320.0, 360.0, 768.0, 1440.0])
    for (final scale in [1.0, 1.5]) {
      testWidgets('V2 header and fields remain bounded at $width / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: designSystemV2(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1000),
                textScaler: TextScaler.linear(scale),
              ),
              child: V2Scaffold(
                appBar: FarmTopBar(
                  actions: {FarmDestination.production: () {}},
                  connection: const Icon(Icons.wifi),
                  onRefresh: () {},
                  onLogout: () {},
                ),
                body: const SingleChildScrollView(
                  child: Column(
                    children: [
                      V2Field(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: 'Quantité distribuée (kg) *',
                          ),
                        ),
                      ),
                      V2Field(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: 'Note facultative',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(AppBar)).height, 64);
        expect(
          find.byKey(const ValueKey('navigation-lots-horizontal')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('navigation-history-horizontal')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
}

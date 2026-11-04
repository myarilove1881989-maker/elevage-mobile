import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/screens/cycle_balance_screen.dart';

Map<String, dynamic> balance({bool closed = false}) => {
  'version': 1,
  'lot': {'id': 7, 'name': 'Poulets A'},
  'closed': closed,
  'start': '2026-09-01',
  'end': '2026-10-30',
  'generated_at': '2026-11-04T12:00:00Z',
  'financial': {
    'revenue': '1000',
    'charges': '700',
    'result': '300',
    'result_percent': '42.86',
    'receivables_to_date': '200',
  },
  'technical': {
    'duration_days': 60,
    'initial_animals': 100,
    'deaths': null,
    'feed_kg': '125.5',
    'mean_weight_kg': null,
  },
  'expense_breakdown': [
    {'category': 'Aliments', 'amount': '200'},
  ],
  'formula':
      'Ventes actives − achats actifs d’animaux − dépenses actives du lot.',
  'warnings': ['Consommables partagés : vérifier l’affectation.'],
  'valuation': {
    'status': 'unavailable',
    'feed_cost': null,
    'vaccine_cost': null,
    'loss_cost': null,
    'method': 'CMP mobile',
    'explanation':
        'Analyse informative, jamais ajoutée aux charges enregistrées.',
  },
  'candidates': [
    {'id': 8, 'nom': 'Poulets B', 'date_debut': '2026-06-01'},
  ],
};

class BalanceApi extends ApiService {
  bool closed = false, cached = false, fail = false, pending = false;
  Completer<dynamic>? delayed;
  final requests = <String>[];
  @override
  List<OutboxEntry> get localOperations => pending
      ? [
          OutboxEntry(
            declaration: const {},
            transportStatus: 'LOCAL_PENDING',
            businessStatus: 'UNREVIEWED',
            attemptCount: 0,
            lastError: '',
          ),
        ]
      : [];
  @override
  Future<dynamic> get(String endpoint) async {
    requests.add(endpoint);
    if (delayed != null) return delayed!.future;
    if (fail) throw StateError('offline');
    lastReadWasCached = cached;
    final result = balance(closed: closed);
    if (endpoint.contains('?compare=8')) {
      final other = balance(closed: true);
      other['lot'] = {'id': 8, 'name': 'Poulets B'};
      other['financial']['result_percent'] = '32.86';
      result['comparison'] = {
        'reference': other,
        'warnings': ['Durées et tailles à vérifier.'],
        'differences': {
          for (final section in ['financial', 'technical'])
            for (final k in (result[section] as Map).keys)
              k: {
                'absolute': k == 'deaths' ? null : '10.00',
                'relative_percent': k == 'result_percent' ? null : '10.00',
                'unit': k == 'result_percent' ? 'points' : 'value',
              },
        },
      };
    }
    return result;
  }
}

Future<void> open(WidgetTester tester, BalanceApi api) async {
  await tester.pumpWidget(
    MaterialApp(home: CycleBalanceScreen(api: api, lotId: 7)),
  );
  await tester.pumpAndSettle();
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    450,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = 'synthetic-cycle-session';
  });
  tearDown(() {
    ApiService.token = null;
  });

  test('missing and percentage formatting', () {
    expect(cycleValue('result_percent', '42.86'), '42,86 %');
    expect(cycleValue('mean_weight_kg', null), 'Non calculable');
    expect(cycleValue('feed_kg', '125.5'), '125,500 kg');
  });
  testWidgets('open cycle and recorded financial result', (tester) async {
    final api = BalanceApi();
    await open(tester, api);
    expect(find.text('Bilan provisoire'), findsOneWidget);
    expect(find.text('Résultat économique'), findsOneWidget);
    expect(find.text('42,86 %'), findsOneWidget);
    expect(api.requests.single, '/lots/7/cycle-report/');
  });
  testWidgets('closed cycle and date reference', (tester) async {
    await open(tester, BalanceApi()..closed = true);
    expect(find.text('Bilan de fin de cycle'), findsOneWidget);
    expect(find.text('Du 01/09/2026 au 30/10/2026'), findsOneWidget);
  });
  testWidgets('cached data and pending operations remain provisional', (
    tester,
  ) async {
    await open(
      tester,
      BalanceApi()
        ..cached = true
        ..pending = true,
    );
    expect(find.textContaining('Données mémorisées'), findsOneWidget);
    expect(find.textContaining('restent à confirmer'), findsOneWidget);
  });
  testWidgets('unavailable request has retry and no invented result', (
    tester,
  ) async {
    final api = BalanceApi()..fail = true;
    await open(tester, api);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Résultat économique'), findsNothing);
    api.fail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Résultat économique'), findsOneWidget);
  });
  testWidgets('late response from another session is discarded', (
    tester,
  ) async {
    final api = BalanceApi()..delayed = Completer<dynamic>();
    await tester.pumpWidget(
      MaterialApp(home: CycleBalanceScreen(api: api, lotId: 7)),
    );
    ApiService.token = 'other-session';
    api.delayed!.complete(balance());
    await tester.pumpAndSettle();
    expect(find.text('Poulets A'), findsNothing);
    expect(find.textContaining('session a changé'), findsOneWidget);
  });
  testWidgets(
    'comparison uses compatible server candidates and percentage points',
    (tester) async {
      final api = BalanceApi();
      await open(tester, api);
      await scrollTo(tester, find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Poulets B').last);
      await tester.pumpAndSettle();
      expect(api.requests.last, '/lots/7/cycle-report/?compare=8');
      await scrollTo(tester, find.text('Écart : 10.00 points'));
      expect(find.text('Écart : 10.00 points'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('responsive report at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, BalanceApi());
      await scrollTo(tester, find.text('Comparer deux cycles'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('financial change refreshes the report', (tester) async {
    final api = BalanceApi();
    await open(tester, api);
    ApiService.businessChanges.value++;
    await tester.pumpAndSettle();
    expect(api.requests.length, 2);
  });
}

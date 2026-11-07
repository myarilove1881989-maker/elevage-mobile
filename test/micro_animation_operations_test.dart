import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/widgets/micro_feedback.dart';
import 'feed_stock_form_test.dart' show StockApi;
import 'production_tracking_test.dart' show testApp;

class FeedbackStockApi extends StockApi {
  FeedbackStockApi(this.result);
  final String result;
  @override
  Future<dynamic> post(String path, Map<String, dynamic> data) async {
    requests.add({...data});
    if (result == 'refused') throw StateError('Refus synthétique');
    if (result == 'uncertain') return <String, dynamic>{};
    if (result == 'offline') return {'local_only': true};
    return {'id': 3};
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.animationsEnabled = true;
  });
  for (final outcome in ['confirmed', 'refused', 'uncertain', 'offline']) {
    testWidgets(
      'real distribution form $outcome celebrates only confirmed receipt',
      (t) async {
        final api = FeedbackStockApi(outcome);
        await t.pumpWidget(
          testApp(
            FeedDistributionFormScreen(
              apiService: api,
              lotId: 1,
              lotName: 'Lot fictif',
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('distribution-stock-product')));
        await t.pumpAndSettle();
        await t.tap(find.text('Aliment suivi').last);
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('feedQuantityField')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('feedQuantityField')), '20');
        await t.scrollUntilVisible(
          find.byKey(const Key('saveFeedDistribution')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('saveFeedDistribution')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(api.requests, hasLength(1));
        expect(
          find.byKey(const Key('micro-confirmation')),
          outcome == 'confirmed' ? findsOneWidget : findsNothing,
        );
        if (outcome == 'offline') {
          expect(
            find.text('Enregistré sur l’appareil — synchronisation en attente'),
            findsOneWidget,
          );
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 3));
        expect(t.binding.transientCallbackCount, 0);
        api.close();
      },
    );
  }
  testWidgets(
    'turning motion off and back on safely recreates a transient controller',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => MicroFeedback.confirmed(context),
              child: const Text('Confirmé'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Confirmé'));
      await t.pump();
      await AppSettings.instance.setAnimationsEnabled(false);
      await t.pump();
      expect(
        t.widget<ConfirmationFrame>(find.byType(ConfirmationFrame)).confetti,
        false,
      );
      await AppSettings.instance.setAnimationsEnabled(true);
      await t.pump();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      expect(t.binding.transientCallbackCount, 0);
    },
  );
}

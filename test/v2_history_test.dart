import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/physical_stock_cards.dart';
import 'auth_connection_test.dart' show authApp;
import 'consumables_ux_test.dart' show ConsumablesApi;

class DestinationHistoryApi extends ConsumablesApi {
  @override
  Future<dynamic> get(String path) async {
    if (path.contains('/history/'))
      return {
        'unit': 'kg',
        'next_before': null,
        'results': [
          {
            'kind': 'DISTRIBUTION',
            'quantity': '-20.000',
            'at': '2026-11-04T12:00:00Z',
            'species': 4,
            'lot': null,
            'destination_lot': 10,
          },
          {
            'kind': 'DISTRIBUTION',
            'quantity': '-5.000',
            'at': '2026-11-04T12:00:00Z',
            'species': 4,
            'lot': null,
            'destination_lot': null,
          },
          {
            'kind': 'CORRECTION',
            'quantity': '-2.000',
            'at': '2026-11-04T12:00:00Z',
            'species': 4,
            'lot': null,
            'destination_lot': null,
          },
        ],
      };
    return super.get(path);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = 'synthetic-destination';
  });
  tearDown(() => ApiService.token = null);
  testWidgets(
    'shared-stock history shows actual recipient, preserves correction sign and unknown destinations',
    (tester) async {
      final api = DestinationHistoryApi();
      await tester.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: true, lot: 10)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('consumable-history')));
      await tester.tap(find.byKey(const Key('consumable-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Croissance').last);
      await tester.pumpAndSettle();
      expect(find.text('Distribution — Croissance — 20 kg'), findsOneWidget);
      expect(
        find.textContaining('Poules · Lot A · 04/11/2026'),
        findsOneWidget,
      );
      expect(find.textContaining('Destinataire non renseigné'), findsOneWidget);
      expect(find.textContaining('— -2 kg'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}

import 'package:app_elevage/screens/stock_detail_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class BirthStockApiFake extends ApiService {
  @override
  Future<Map<String, dynamic>> getStockDetail(int lotId) async => {
    'stock_initial': 22,
    'stock_restant': 17,
    'naissances': 12,
    'vendu': 3,
    'perdu': 2,
    'mortalite': 2,
    'don': 0,
    'vol': 0,
  };
}

void main() {
  testWidgets('Le détail du stock comprend les naissances sans les confondre '
      'avec les ventes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StockDetailScreen(apiService: BirthStockApiFake(), lotId: 1),
    ));
    await tester.pumpAndSettle();
    expect(find.text('17'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.textContaining('Naissance : 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

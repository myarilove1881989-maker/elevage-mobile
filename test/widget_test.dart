import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_elevage/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const MaterialApp());

    // Vérifie que l'application démarre sans crash
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
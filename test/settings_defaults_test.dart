import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/theme/design_system_v2.dart';

class SettingsApi extends ApiService {
  int writes = 0;
  @override
  Future<dynamic> get(String path) async => {'nom': 'Exploitation synthétique'};
  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    writes++;
    return {};
  }
}

void main() {
  testWidgets(
    'reset defaults requires confirmation and preserves protected storage',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'settings_language': 'en',
        'settings_currency': 'EUR',
        'settings_country': 'FR',
        'settings_city': 'Paris',
        'settings_micro_animations': false,
        'token': 'synthetic-protected-token',
        'offline_pin': 'synthetic-protected-pin',
        'outbox': 'synthetic-outbox',
      });
      final settings = AppSettings.instance;
      await settings.load();
      final api = SettingsApi();
      await t.pumpWidget(
        MaterialApp(
          theme: designSystemV2(),
          home: SettingsScreen(apiService: api),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Configurations initiales'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.tap(find.text('Configurations initiales'));
      await t.pumpAndSettle();
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(settings.currencyCode, 'EUR');
      await t.tap(find.text('Configurations initiales'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rétablir'));
      await t.pumpAndSettle();
      final choices = t
          .stateList<FormFieldState<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .map((s) => s.value)
          .toList();
      expect(choices, ['', 'fr', 'XAF']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_currency'), 'XAF');
      expect(settings.currencyCode, 'XAF');
      expect(prefs.getBool('settings_micro_animations'), true);
      expect(prefs.getString('token'), 'synthetic-protected-token');
      expect(prefs.getString('offline_pin'), 'synthetic-protected-pin');
      expect(prefs.getString('outbox'), 'synthetic-outbox');
      expect(api.writes, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
}

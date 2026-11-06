import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'package:app_elevage/screens/user_management_screen.dart';
import 'package:app_elevage/services/user_administration_service.dart';
import 'package:app_elevage/services/api_service.dart';
import 'terrain_forms_validation_test.dart' as terrain;
import 'user_administration_test.dart' show AdminApi;
import 'v2_operation_forms_visual_test.dart' show capture, app;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = 'synthetic-extra-audit';
  });
  tearDown(() => ApiService.token = null);
  for (final width in [360.0, 1440.0]) {
    for (final family in [
      'terrain_operation',
      'terrain_vente',
      'terrain_client',
      'terrain_agenda',
    ]) {
      testWidgets('$family $width', (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final fixture = terrain.FormFixture();
        await t.runAsync(fixture.start);
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.runAsync(fixture.finish);
        });
        await t.pumpWidget(
          app(OfflineTabletScreen(controller: fixture.tablet)),
        );
        await terrain.flush(t, fixture);
        if (family == 'terrain_agenda') {
          await terrain.choose(t, 'Consulter', 'Agenda');
          await terrain.flush(t, fixture);
          await terrain.tap(t, find.text('Tâche fictive'));
        } else {
          await terrain.tap(
            t,
            find.text(
              {
                'terrain_operation': 'Enregistrer une opération terrain',
                'terrain_vente': 'Enregistrer une vente ou un encaissement',
                'terrain_client': 'Enregistrer un client',
              }[family]!,
            ),
          );
        }
        await terrain.flush(t, fixture);
        await capture(t, family, width);
        expect((await t.runAsync(() => fixture.db.listOutbox()))!, isEmpty);
      });
    }
    testWidgets('utilisateur_creation $width', (t) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = AdminApi();
      addTearDown(api.close);
      await t.pumpWidget(
        app(UserManagementScreen(service: UserAdministrationService(api))),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.widgetWithText(FilledButton, 'Ajouter un utilisateur'),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Ajouter un utilisateur'));
      await t.pumpAndSettle();
      await capture(t, 'utilisateur_creation', width);
      expect(api.writes, 0);
    });
  }
}

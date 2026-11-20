import 'package:app_elevage/services/app_settings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'package:app_elevage/pisciculture/aquatic_revenue_screen.dart';
import 'package:app_elevage/pisciculture/aquatic_forms.dart';
import 'package:app_elevage/widgets/dashboard_kpi_card.dart';
import 'package:app_elevage/screens/user_management_screen.dart';
import 'package:app_elevage/theme/design_system_v2.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic;

class DashboardService extends FakeAquatic {
  final reads = <String>[];
  bool financeFails = false;
  @override
  Future<Map<String, dynamic>> read(String path) async {
    reads.add(path);
    if (path.startsWith('finance-summary/')) {
      if (financeFails) throw StateError('offline');
      return {
        'billed_revenue': '12345.67',
        'aquatic_expenses': '876.50',
        'client_balance_as_of': '0.00',
      };
    }
    if(path.startsWith('finance-detail/'))return {'cohorts':[],'categories':[]};
    return super.read(path);
  }
}

void main() {
  setUpAll(()async {
    await initializeDateFormatting('fr_FR');
    await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((b)=>ByteData.sublistView(b)))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [
    const Size(1910, 1000),
    const Size(1366, 900),
    const Size(768, 1024),
    const Size(390, 844),
  ]) {
    testWidgets('five aquatic cards, stock details and responsive layout $size', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = DashboardService(),
          key = GlobalKey<AquaticWorkspaceState>(),
          boundary = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: designSystemV2().copyWith(splashFactory:InkRipple.splashFactory),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ColoredBox(color:const Color(0xFFFCF7FF),child:AquaticWorkspace(
                key: key,
                service: service,
                capabilities: {'can_enable':true,'read':['aquatic.read'],'write':[],'finance_write':[],'commerce_write':[]},
                farmName: 'Exploitation de recette',
              )),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(DashboardKpiCard), findsNWidgets(5));
      final titles = t
          .widgetList<DashboardKpiCard>(find.byType(DashboardKpiCard))
          .map((c) => c.title)
          .toList();
      expect(titles, [
        'Stock total',
        "Chiffre d'affaires",
        'Dépenses',
        'Solde clients',
        'Gestion',
      ]);
      expect(find.text(AppSettings.instance.formatMoney('12345.67',decimals:2)), findsOneWidget);
      expect(find.textContaining('Exploitation de recette',findRichText:true), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'D:/ElevAge-Final-20261120/screenshots/dashboard-${size.width.toInt()}.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      });
      await t.tap(find.text('Stock total'));
      await t.pumpAndSettle();
      expect(find.text('Stock piscicole'), findsOneWidget);
      expect(service.writes, isEmpty);
      key.currentState!.showPage('management_hub');
      await t.pumpAndSettle();
      key.currentState!.goBack();
      await t.pumpAndSettle();
      expect(find.text('Stock piscicole'),findsOneWidget);
      key.currentState!.showDashboard();
      await t.pumpAndSettle();
      expect(find.byType(DashboardKpiCard), findsNWidgets(5));
    });
  }
  testWidgets('finance failure does not erase stock or create zero amounts', (
    t,
  ) async {
    final service = DashboardService()..financeFails = true;
    await t.pumpWidget(
      MaterialApp(
        theme: designSystemV2().copyWith(splashFactory:InkRipple.splashFactory),
        home: Scaffold(
          body: AquaticWorkspace(service: service, capabilities: {'can_enable':true,'read':['aquatic.read'],'write':[],'finance_write':[],'commerce_write':[]}),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Indisponible'), findsNWidgets(3));
    expect(find.text('1000'), findsOneWidget);
    expect(service.writes, isEmpty);
  });
  testWidgets(
    'select all changes only editable permissions and preserves other codes',
    (t) async {
      final selected = <String>{'users.manage'};
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => PermissionEditor(
                  selected: selected,
                  onChanged: (code, value) => setState(() {
                    if (value) {
                      selected.add(code);
                    } else {
                      selected.remove(code);
                    }
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('permissions-select-all')));
      await t.pumpAndSettle();
      expect(selected.containsAll(PermissionEditor.selectable), isTrue);
      expect(selected.contains('users.manage'), isTrue);
      await t.tap(find.byKey(const Key('permissions-select-all')));
      await t.pumpAndSettle();
      expect(selected, {'users.manage'});
    },
  );
 testWidgets('stock and finance use the same population filters and details retain species',(t)async{
   final service=DashboardService(),key=GlobalKey<AquaticWorkspaceState>();
   await t.pumpWidget(MaterialApp(theme:designSystemV2().copyWith(splashFactory:InkRipple.splashFactory),home:Scaffold(body:AquaticWorkspace(key:key,service:service,capabilities:{'can_enable':true,'write':[]}))));
   await t.pumpAndSettle();
   key.currentState!..speciesFilter='42'..installationFilter='10000000-0000-4000-8000-000000000001'..cohortFilter='30000000-0000-4000-8000-000000000001';
   await key.currentState!.reload();await t.pumpAndSettle();
   for(final prefix in ['dashboard/','finance-summary/']){
     final query=Uri.parse(service.reads.lastWhere((p)=>p.startsWith(prefix))).queryParameters;
     expect(query['species'],'42');expect(query['installation'],'10000000-0000-4000-8000-000000000001');expect(query['cohort'],'30000000-0000-4000-8000-000000000001');
   }
   await t.ensureVisible(find.text("Chiffre d'affaires"));await t.tap(find.text("Chiffre d'affaires"));await t.pumpAndSettle();
   final panel=t.widget<AquaticRevenueScreen>(find.byType(AquaticRevenueScreen));
   expect(panel.filters['species'],'42');expect(panel.filters['installation'],'10000000-0000-4000-8000-000000000001');expect(service.writes,isEmpty);
 });
 testWidgets('purchases open the existing cohort form directly without a write',(t)async{
   final service=DashboardService(),key=GlobalKey<AquaticWorkspaceState>();
   await t.pumpWidget(MaterialApp(theme:designSystemV2().copyWith(splashFactory:InkRipple.splashFactory),home:Scaffold(body:AquaticWorkspace(key:key,service:service,capabilities:{'can_enable':true,'write':['aquatic.cohorts.manage','aquatic.installations.manage']}))));
   await t.pumpAndSettle();key.currentState!.showPage('purchases_hub');await t.pumpAndSettle();
   expect(find.byType(AquaticForm),findsOneWidget);expect(find.text('Poissons et alevins'),findsNothing);expect(service.writes,isEmpty);
 });

}

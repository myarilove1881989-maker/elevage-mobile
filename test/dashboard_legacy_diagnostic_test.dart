import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'dashboard_history_route_test.dart' as history;
import 'ux_9a1_test.dart' as ux;
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);
  setUp(() {
    // Simulate an unavailable native version lookup; no network and no timeout.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('elevage/app_version'),(_ )async=>null);
  });
  tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('elevage/app_version'),null));
  history.main();ux.main();
}

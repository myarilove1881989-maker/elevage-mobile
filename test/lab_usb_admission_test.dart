import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/lab_network_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Config.current.isLab && Config.current.labHost == '127.0.0.1';
  testWidgets('offline startup admits automatically only after the approved server returns', (tester) async {
    var available = false;
    final gate = LabNetworkGate(serverProbe: (_, _) async => available);
    expect(await gate.initializeFromBuild(Config.current), isFalse);
    expect(gate.enabled,isFalse);
    available = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(gate.enabled,isTrue);
    gate.stop(); gate.dispose();
  }, skip: !enabled);

  testWidgets('a late admission probe cannot undo an explicit stop', (tester) async {
    final response = Completer<bool>();
    final entered = Completer<void>();
    final gate = LabNetworkGate(serverProbe: (_, _) { entered.complete(); return response.future; });
    final initialization = gate.initializeFromBuild(Config.current);
    await tester.pump();
    expect(entered.isCompleted,isTrue);
    gate.stop();response.complete(true);
    expect(await initialization,isFalse);
    await tester.pump(const Duration(seconds: 4));
    expect(gate.enabled,isFalse);
    gate.dispose();
  }, skip: !enabled);
}

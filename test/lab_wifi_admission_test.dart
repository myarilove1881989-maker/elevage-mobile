import 'dart:async';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/lab_network_gate.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
 const available=String.fromEnvironment('LAB_ISOLATION_JSON')!='';
 test('Wi-Fi approved build still waits for the exact server probe',() async {
  var probes=0;final gate=LabNetworkGate(serverProbe:(_,id) async {probes++;expect(id,'b2b4414074414508a0e6666f8a7d5958');return false;});
  expect(await gate.initializeFromBuild(Config.current),isFalse);expect(probes,1);expect(gate.enabled,isFalse);gate.dispose();
 },skip:!available);
 test('Wi-Fi approved build admits verified server and refuses another destination',() async {
  final gate=LabNetworkGate(serverProbe:(_,_) async=>true);
  expect(await gate.initializeFromBuild(Config.current),isTrue);
  expect(gate.permits(Config.current,Uri.parse('https://192.168.1.100:8443/api/me/capabilities/')),isTrue);
  expect(gate.permits(Config.current,Uri.parse('https://192.168.1.101:8443/api/me/capabilities/')),isFalse);
  gate.stop();expect(gate.enabled,isFalse);expect(await gate.initializeFromBuild(Config.current),isFalse);gate.dispose();
 },skip:!available);
 test('late Wi-Fi probe cannot undo stop',() async {
  final entered=Completer<void>(),reply=Completer<bool>();
  final gate=LabNetworkGate(serverProbe:(_,_) {entered.complete();return reply.future;});
  final future=gate.initializeFromBuild(Config.current);await entered.future;gate.stop();reply.complete(true);
  expect(await future,isFalse);expect(gate.enabled,isFalse);gate.dispose();
 },skip:!available);
}

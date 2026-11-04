import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../offline/outbox.dart';

Map<String,dynamic> eggValues(Map item) => {
  'nombre_collecte': item['nombre_collecte'] ?? ((item['nombre_alveoles'] ?? 0) * 30 + (item['oeufs_restants'] ?? 0)),
  'nombre_casses': item['nombre_casses'] ?? 0,
  'nombre_declasses': item['nombre_declasses'] ?? 0,
  'nombre_consommes_donnes': item['nombre_consommes_donnes'] ?? 0,
  'note': item['note'] ?? '',
};
Future<String> eggVersion(Map item) async {
  final digest=await Sha256().hash(utf8.encode(canonicalDeclaration(eggValues(item))));
  return digest.bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
}
int eggAvailable(Map item) { final v=eggValues(item); return (v['nombre_collecte'] as int) -
  (v['nombre_casses'] as int) - (v['nombre_declasses'] as int) - (v['nombre_consommes_donnes'] as int); }

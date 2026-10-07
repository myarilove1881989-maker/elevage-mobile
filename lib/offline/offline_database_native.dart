import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'farm_database.dart';
export 'farm_database.dart';

final _openDatabases = <String, Future<FarmDatabase>>{};

Future<FarmDatabase> openAndroidFarmDatabase({required int farmId, required Uri server}) {
  final identity = '${server.toString()}#$farmId';
  return _openDatabases.putIfAbsent(identity, () async {
    try { return await _openAndroidFarmDatabase(farmId: farmId, server: server); }
    catch (_) { _openDatabases.remove(identity); rethrow; }
  });
}

Future<void> closeAndroidFarmDatabase({required int farmId, required Uri server}) async {
  final pending = _openDatabases.remove('${server.toString()}#$farmId');
  if (pending != null) await (await pending).close();
}

Future<FarmDatabase> _openAndroidFarmDatabase({required int farmId, required Uri server}) async {
  if (!Platform.isAndroid || farmId < 1 || server.scheme != 'https' || server.userInfo.isNotEmpty) {
    throw StateError('Une exploitation Android et un serveur HTTPS sont requis.');
  }
  final namespaceHash = await Sha256().hash(utf8.encode(server.toString()));
  final namespace = namespaceHash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/farm_${namespace}_$farmId.db');
  const secrets = FlutterSecureStorage();
  final keyName = 'farm_db_key_${namespace}_$farmId';
  var key = await secrets.read(key: keyName);
  if (key == null) {
    if (await file.exists()) throw StateError('Clé perdue : récupération explicite requise.');
    final random = Random.secure();
    key = List.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await secrets.write(key: keyName, value: key);
  }
  final database = FarmDatabase(encryptedExecutor(file, key), farmId: farmId, serverNamespace: namespace);
  try {
    await database.customSelect('SELECT singleton FROM farm_identity').getSingle();
    return database;
  } catch (_) {
    await database.close();
    rethrow;
  }
}

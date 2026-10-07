import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// Release-mode checks: SQLite silently ignores unknown PRAGMAs, so never assert.
void configureEncryptedDatabase(sql.Database database, String hexKey) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) {
    throw ArgumentError('Clé de base invalide.');
  }
  if (database.select('PRAGMA cipher').isEmpty) {
    throw StateError('Le moteur chiffrant est indisponible.');
  }
  database.execute("PRAGMA key = '$hexKey'");
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA secure_delete = ON');
  database.execute('PRAGMA temp_store = MEMORY');
  database.select('SELECT count(*) FROM sqlite_master');
}

QueryExecutor encryptedExecutor(File file, String key) => NativeDatabase.createInBackground(
  file, setup: (db) => configureEncryptedDatabase(db, key),
);

/// A shared encrypted farm database. Personal PIN/grant/JWT remain elsewhere.
class FarmDatabase extends GeneratedDatabase {
  FarmDatabase(QueryExecutor executor, {required this.farmId, required this.serverNamespace})
      : super(executor);
  final int farmId;
  final String serverNamespace;

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('CREATE TABLE farm_identity '
          '(singleton INTEGER PRIMARY KEY CHECK(singleton=1), farm_id INTEGER NOT NULL, '
          'server_namespace TEXT NOT NULL)');
      await customStatement('INSERT INTO farm_identity VALUES(1,?,?)', [farmId, serverNamespace]);
      await customStatement('CREATE TABLE confirmed_cache '
          '(collection TEXT NOT NULL, entity_id TEXT NOT NULL, payload TEXT NOT NULL, '
          'received_at INTEGER NOT NULL, PRIMARY KEY(collection,entity_id))');
      await customStatement('CREATE TABLE local_operator_profiles '
          '(user_id INTEGER PRIMARY KEY, membership_id INTEGER NOT NULL UNIQUE, '
          'display_name TEXT NOT NULL, rights_version INTEGER NOT NULL, '
          'write_generation INTEGER NOT NULL)');
    },
    beforeOpen: (_) async {
      final identity = await customSelect('SELECT farm_id,server_namespace FROM farm_identity').getSingle();
      if (identity.read<int>('farm_id') != farmId ||
          identity.read<String>('server_namespace') != serverNamespace) {
        throw StateError('Cette base appartient à une autre exploitation.');
      }
    },
  );

  static const cacheCollections = {'lots', 'clients', 'species', 'tasks', 'dashboard'};

  Future<void> replaceConfirmedCache(String collection, List<Map<String, dynamic>> rows) async {
    if (!cacheCollections.contains(collection)) throw ArgumentError('Collection non autorisée.');
    for (final row in rows) {
      _rejectSecrets(row);
      if (row['id'] == null) throw ArgumentError('Identifiant serveur requis.');
    }
    await transaction(() async {
      await customStatement('DELETE FROM confirmed_cache WHERE collection=?', [collection]);
      final received = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final row in rows) {
        await customStatement('INSERT INTO confirmed_cache VALUES(?,?,?,?)',
            [collection, row['id'].toString(), jsonEncode(row), received]);
      }
    });
  }

  Future<List<Map<String, dynamic>>> cachedPage(String collection, {int offset = 0, int limit = 50}) async {
    if (!cacheCollections.contains(collection) || offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Page invalide.');
    }
    final rows = await customSelect('SELECT payload,received_at FROM confirmed_cache '
        'WHERE collection=? ORDER BY entity_id LIMIT ? OFFSET ?',
        variables: [Variable(collection), Variable(limit), Variable(offset)]).get();
    return rows.map((row) => {
      'data': jsonDecode(row.read<String>('payload')),
      'confirmed_received_at': row.read<int>('received_at'),
    }).toList();
  }

  static void _rejectSecrets(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (RegExp(r'(^|_)(token|jwt|password|pin|secret|authorization|private_key|refresh)(_|$)',
            caseSensitive: false).hasMatch(entry.key.toString())) {
          throw ArgumentError('Secret interdit dans la base métier.');
        }
        _rejectSecrets(entry.value);
      }
    } else if (value is List) {
      for (final item in value) { _rejectSecrets(item); }
    }
  }
}

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

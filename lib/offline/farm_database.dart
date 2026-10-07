import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'farm_cache.dart';
import 'offline_grant.dart';
import 'outbox_database.dart';
import 'terrain_projection.dart';

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
class FarmDatabase extends GeneratedDatabase with OutboxDatabaseMethods, TerrainProjection implements FarmCache {
  FarmDatabase(super.executor, {required this.farmId, required this.serverNamespace,DateTime Function()? clock})
    :outboxClock=clock??DateTime.now;
  final int farmId;
  final String serverNamespace;
  @override
  int get outboxFarmId=>farmId;
  @override
  final DateTime Function() outboxClock;

  @override
  int get schemaVersion => 4;
  @override
  Future<void> applyProjectionReceipt(Map<String,dynamic> receipt)=>projectReceipt(receipt);
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
      await _createStaging();
      await createOutboxSchema();
      await createTerrainMappings();
    },
    onUpgrade: (_,from,to) async {
      if(from<2) await _createStaging();
      if(from<3) await createOutboxSchema();
      if(from<4) await createTerrainMappings();
    },
    beforeOpen: (_) async {
      final identity = await customSelect('SELECT farm_id,server_namespace FROM farm_identity').getSingle();
      if (identity.read<int>('farm_id') != farmId ||
          identity.read<String>('server_namespace') != serverNamespace) {
        throw StateError('Cette base appartient à une autre exploitation.');
      }
      await recoverInterruptedOutbox();
    },
  );

  static const cacheCollections = {'lots', 'clients', 'species', 'tasks', 'dashboard'};

  Future<void> _createStaging() => customStatement('CREATE TABLE confirmed_cache_staging '
      '(collection TEXT NOT NULL,entity_id TEXT NOT NULL,payload TEXT NOT NULL, '
      'received_at INTEGER NOT NULL,PRIMARY KEY(collection,entity_id))');

  @override
  Future<void> beginCacheRefresh(String collection) async {
    if(!cacheCollections.contains(collection)) throw ArgumentError('Collection non autorisée.');
    await customStatement('DELETE FROM confirmed_cache_staging WHERE collection=?',[collection]);
  }

  @override
  Future<void> stageConfirmedPage(String collection,List<Map<String,dynamic>> rows) async {
    if(!cacheCollections.contains(collection) || rows.length>200) throw ArgumentError('Page invalide.');
    for(final row in rows) {
      _rejectSecrets(row);
      if(row['id']==null) throw ArgumentError('Identifiant requis.');
    }
    await transaction(() async {
      final received=DateTime.now().toUtc().millisecondsSinceEpoch;
      for(final row in rows) {
        await customStatement('INSERT OR REPLACE INTO confirmed_cache_staging VALUES(?,?,?,?)',
          [collection,row['id'].toString(),jsonEncode(row),received]);
      }
    });
  }

  @override
  Future<void> commitCacheRefresh(String collection,{int? taskUserId}) async {
    if(!cacheCollections.contains(collection) || (taskUserId!=null && taskUserId<1)) throw ArgumentError('Contexte invalide.');
    await transaction(() async {
      if(collection=='tasks' && taskUserId!=null) {
        await customStatement("DELETE FROM confirmed_cache WHERE collection=? AND "
          "(json_extract(payload,'\$.assigned_to') IS NULL OR json_extract(payload,'\$.assigned_to')=?)",
          [collection,taskUserId]);
      } else {
        await customStatement('DELETE FROM confirmed_cache WHERE collection=?',[collection]);
      }
      await customStatement('INSERT OR REPLACE INTO confirmed_cache '
        'SELECT collection,entity_id,payload,received_at FROM confirmed_cache_staging WHERE collection=?',[collection]);
      await customStatement('DELETE FROM confirmed_cache_staging WHERE collection=?',[collection]);
    });
  }

  @override
  Future<void> saveOperatorProfile(VerifiedOfflineGrant grant,String displayName) async {
    if(grant.farmId!=farmId || displayName.isEmpty || displayName.length>150) {
      throw ArgumentError('Profil de cette exploitation requis.');
    }
    await customStatement('INSERT INTO local_operator_profiles '
      '(user_id,membership_id,display_name,rights_version,write_generation) VALUES(?,?,?,?,?) '
      'ON CONFLICT(user_id) DO UPDATE SET membership_id=excluded.membership_id, '
      'display_name=excluded.display_name,rights_version=excluded.rights_version, '
      'write_generation=excluded.write_generation',
      [grant.userId,grant.claims['membership_id'],displayName,grant.rightsVersion,grant.generation]);
  }

  @override
  Future<List<Map<String,dynamic>>> operatorProfiles() async =>
      (await customSelect('SELECT * FROM local_operator_profiles ORDER BY display_name').get())
          .map((row)=>Map<String,dynamic>.from(row.data)).toList();

  @override
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

  @override
  Future<List<Map<String, dynamic>>> cachedPage(String collection, {int offset = 0, int limit = 50,int? taskUserId}) async {
    if (!cacheCollections.contains(collection) || offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Page invalide.');
    }
    final taskFilter=collection=='tasks' && taskUserId!=null
      ? " AND (json_extract(payload,'\$.assigned_to') IS NULL OR json_extract(payload,'\$.assigned_to')=?)" : '';
    final rows = await customSelect('SELECT payload,received_at FROM confirmed_cache '
        'WHERE collection=?$taskFilter ORDER BY entity_id LIMIT ? OFFSET ?',
        variables: [Variable(collection),if(taskFilter.isNotEmpty)Variable(taskUserId!),Variable(limit),Variable(offset)]).get();
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


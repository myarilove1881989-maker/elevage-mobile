import 'dart:convert';
import 'package:drift/drift.dart';
import 'screen_snapshot_store.dart';

/// Stored in the same encrypted, farm-bound database as the durable outbox.
/// A snapshot is a past confirmed read, never a grant or a future write receipt.
mixin ScreenSnapshotsSql on GeneratedDatabase implements ScreenSnapshotStore {
  Future<void> createScreenSnapshots()=>customStatement('CREATE TABLE screen_snapshots ('
    'user_id INTEGER NOT NULL, credential_version INTEGER NOT NULL, path TEXT NOT NULL,'
    'payload TEXT NOT NULL, PRIMARY KEY(user_id,credential_version,path))');
  void _validate(int user,int version,String path,Object payload) {
    if(user<1 || version<1 || !path.startsWith('/') || path.contains('://') ||
       path.contains('token') || path.contains('password') || path.contains('devices') ||
       path.contains('memberships') || path.contains('capabilities')) throw ArgumentError('Lecture non conservable.');
    void scan(Object? value) {
      if(value is Map) {
        for(final entry in value.entries) {
          if(RegExp(r'^(password|pin|access|refresh|authorization|private_key|change_token|reset_token)$',caseSensitive:false).hasMatch(entry.key.toString())) {
            throw ArgumentError('Un secret ne peut pas être conservé dans une vue.');
          }
          scan(entry.value);
        }
      } else if(value is List) {for(final item in value) {scan(item);}}
    }
    scan(payload);
    if(utf8.encode(jsonEncode(payload)).length>2*1024*1024) throw ArgumentError('Vue trop volumineuse.');
  }
  @override
  Future<void> saveScreenSnapshot({required int userId,required int credentialVersion,required String path,required Object payload}) async {
    _validate(userId,credentialVersion,path,payload);
    await customStatement('INSERT INTO screen_snapshots(user_id,credential_version,path,payload) VALUES(?,?,?,?) '
      'ON CONFLICT(user_id,credential_version,path) DO UPDATE SET payload=excluded.payload',
      [userId,credentialVersion,path,jsonEncode(payload)]);
  }
  @override
  Future<Object?> screenSnapshot({required int userId,required int credentialVersion,required String path}) async {
    _validate(userId,credentialVersion,path,const {});
    final row=await customSelect('SELECT payload FROM screen_snapshots WHERE user_id=? AND credential_version=? AND path=?',
      variables:[Variable.withInt(userId),Variable.withInt(credentialVersion),Variable.withString(path)]).getSingleOrNull();
    return row==null?null:jsonDecode(row.read<String>('payload'));
  }
}

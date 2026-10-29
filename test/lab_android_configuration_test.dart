import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:app_elevage/offline/farm_database.dart';

class MissingCipher extends Fake implements sql.Database {
  bool executed = false;
  @override
  sql.ResultSet select(
    String statement, [
    List<Object?> parameters = const [],
  ]) => sql.ResultSet([], null, []);
  @override
  void execute(String statement, [List<Object?> parameters = const []]) {
    executed = true;
  }
}

void main() {
  test('cipher absence fails before any key or schema write', () {
    final database = MissingCipher();
    expect(
      () => configureEncryptedDatabase(database, 'c' * 64),
      throwsStateError,
    );
    expect(database.executed, isFalse);
    expect(
      () => configureEncryptedDatabase(database, 'invalid'),
      throwsArgumentError,
    );
  });
  test(
    'lab TLS trusts only its dedicated public CA and refuses cleartext',
    () {
      final policy = File(
        'android/app/src/lab/res/xml/lab_network_security_config.xml',
      ).readAsStringSync();
      expect(policy, contains('cleartextTrafficPermitted="false"'));
      expect(policy, contains('certificates src="@raw/elevage_lab_ca"'));
      expect(policy, isNot(contains('src="system"')));
      expect(policy, isNot(contains('src="user"')));
      expect(policy, isNot(contains('debug-overrides')));
      final manifest = File(
        'android/app/src/lab/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('@xml/lab_network_security_config'));
      expect(manifest, contains('@xml/lab_backup_rules'));
      expect(manifest, contains('@xml/lab_data_extraction_rules'));
    },
  );
}

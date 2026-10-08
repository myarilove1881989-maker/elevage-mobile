import 'dart:io';
import 'dart:math';
import 'package:app_elevage/offline/farm_database.dart';

Future<void> main() async {
  final random=Random.secure();
  final key=List.generate(32,(_)=>random.nextInt(256))
      .map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
  final directory=Directory('.dart_tool/encryption-proof');
  await directory.create(recursive:true);
  final file=File('${directory.path}/fixture.db');
  if (await file.exists()) throw StateError('Encryption proof requires a fresh synthetic fixture.');
  final db=FarmDatabase(encryptedExecutor(file,key),farmId:1,serverNamespace:'ci-test-only');
  await db.replaceConfirmedCache('clients',[{'id':1,'name':'synthetic-test-only'}]);
  await db.close();
}

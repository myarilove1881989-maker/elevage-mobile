import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/device_identity.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/outbox_transport.dart';
import 'outbox_test.dart' show testOutboxGrant;

class TransportIdentity implements DeviceIdentity {
  final messages=<String>[];
  @override
  Future<Map<String,dynamic>> publicIdentity() async=>{
    'installation_uuid':'00000000-0000-4000-8000-000000000007',
    'private_key_exportable':false,'algorithm':'P256-SHA256-DER'};
  @override
  Future<String> sign(Uint8List message) async {messages.add(utf8.decode(message));return 'synthetic-native-proof';}
}

void main() {
  late Directory directory;late FarmDatabase db;late DateTime clock;
  late TransportIdentity identity;late OutboxEntry entry;
  setUp(() async {
    directory=await Directory.systemTemp.createTemp('elevage-outbox-transport-');
    final key=List.generate(32,(_)=>Random.secure().nextInt(256)).map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    clock=DateTime.utc(2026,10,7);
    db=FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),key),farmId:1,serverNamespace:'transport',clock:()=>clock);
    identity=TransportIdentity();
    entry=await db.enqueue(grant:await testOutboxGrant(2,clock),isSessionCurrent:()=>true,
      entityType:'CLIENT',operationType:'CREATE',payload:{'nom':'Original Jean'},businessOccurredAt:clock);
  });
  tearDown(() async {await db.close();await directory.delete(recursive:true);});

  Map<String,dynamic> receipt(Map operation,{int? author})=>{
    'client_operation_id':operation['client_operation_id'],'transport_status':'SERVER_RECEIVED',
    'business_status':'UNREVIEWED','author_user_id':author??operation['author_user_id'],
    'received_at':clock.toIso8601String(),'reason_code':'','server_entity_id':'','server_version':'','applied_at':null};
  Map<String,dynamic> challenge(Map data,{int farm=1})=>{
    'id':'00000000-0000-4000-8000-000000000099','device_id':7,'exploitation_id':farm,
    'device_generation':1,'purpose':data['purpose'],'method':'POST',
    'path':data['purpose']=='RECEIVE'?'/api/offline/submissions/':'/api/offline/submissions/status/',
    'signature_contract':'ELEVAGE-DEVICE-TRANSPORT-V1'};
  DeviceOutboxApi api(MockClient client)=>DeviceOutboxApi(baseUrl:'https://synthetic.invalid/api',
    identity:identity,deviceId:7,farmId:1,generation:1,client:client);

  test('lost POST response retries the same UUID with no bearer and one server effect',() async {
    final server=<String,Map<String,dynamic>>{};var lost=true;var posts=0;
    final client=MockClient((request) async {
      expect(request.headers.keys.map((k)=>k.toLowerCase()),isNot(contains('authorization')));
      final body=jsonDecode(request.body) as Map;
      if(request.url.path.endsWith('/transport-challenge/')) return http.Response(jsonEncode(challenge(body)),201);
      posts++;
      final operation=(body['operations'] as List).single as Map;
      final hash=await Sha256().hash(request.bodyBytes);
      final hex=hash.bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
      expect(identity.messages.last,'ELEVAGE-DEVICE-TRANSPORT-V1\n00000000-0000-4000-8000-000000000099\n7\n1\n1\nRECEIVE\nPOST\n/api/offline/submissions/\n$hex');
      server.putIfAbsent(operation['client_operation_id'] as String,()=>receipt(operation));
      if(lost) {lost=false;throw http.ClientException('Synthetic lost response');}
      return http.Response(jsonEncode({'receipts':server.values.toList()}),200);
    });
    final transport=OutboxTransport(store:db,api:api(client));
    await expectLater(transport.syncOnce(),throwsA(isA<DeviceTransportException>()));
    expect((await db.listOutbox()).single.transportStatus,'RETRY_WAIT');
    clock=clock.add(const Duration(minutes:1));
    await transport.syncOnce();
    expect(posts,2);expect(server,hasLength(1));
    final received=(await db.listOutbox()).single;
    expect(received.operationId,entry.operationId);expect(received.authorId,2);
    expect(received.transportStatus,'SERVER_RECEIVED');expect(received.businessStatus,'UNREVIEWED');
    expect(received.attemptCount,2);
    transport.api.close();
  });

  test('parallel triggers share one flight, including expired original grant',() async {
    clock=clock.add(const Duration(days:4));var posts=0;
    final client=MockClient((request) async {
      final body=jsonDecode(request.body) as Map;
      if(request.url.path.endsWith('/transport-challenge/')) return http.Response(jsonEncode(challenge(body)),201);
      posts++;await Future<void>.delayed(const Duration(milliseconds:20));
      final operation=(body['operations'] as List).single as Map;
      return http.Response(jsonEncode({'receipts':[receipt(operation)]}),200);
    });
    final transport=OutboxTransport(store:db,api:api(client));
    await Future.wait([transport.syncOnce(),transport.syncOnce()]);
    expect(posts,1);expect((await db.listOutbox()).single.transportStatus,'SERVER_RECEIVED');
    transport.api.close();
  });

  test('revoked device blocks transport while preserving declaration and author',() async {
    final transport=OutboxTransport(store:db,api:api(MockClient((_) async=>http.Response('{}',403))));
    await expectLater(transport.syncOnce(),throwsA(isA<DeviceTransportException>()));
    final preserved=(await db.listOutbox()).single;
    expect(preserved.transportStatus,'TRANSPORT_BLOCKED');expect(preserved.declaration,entry.declaration);
    transport.api.close();
  });

  test('expired transport challenge is retryable rather than permanently blocking tablet',() async {
    final client=MockClient((request) async {
      if(request.url.path.endsWith('/transport-challenge/')) return http.Response(jsonEncode(challenge(jsonDecode(request.body) as Map)),201);
      return http.Response('{"detail":"DEVICE_CHALLENGE_EXPIRED_OR_USED"}',403);
    });
    final transport=OutboxTransport(store:db,api:api(client));
    await expectLater(transport.syncOnce(),throwsA(isA<DeviceTransportException>()));
    final retained=(await db.listOutbox()).single;
    expect(retained.transportStatus,'RETRY_WAIT');expect(retained.lastError,'CHALLENGE_EXPIRED');
    expect(retained.operationId,entry.operationId);
    transport.api.close();
  });

  test('wrong author receipt and foreign farm challenge cannot confirm an operation',() async {
    final client=MockClient((request) async {
      final body=jsonDecode(request.body) as Map;
      if(request.url.path.endsWith('/transport-challenge/')) return http.Response(jsonEncode(challenge(body)),201);
      return http.Response(jsonEncode({'receipts':[receipt((body['operations'] as List).single as Map,author:3)]}),200);
    });
    final transport=OutboxTransport(store:db,api:api(client));
    await expectLater(transport.syncOnce(),throwsA(isA<DeviceTransportException>()));
    expect((await db.listOutbox()).single.transportStatus,'RETRY_WAIT');
    expect((await db.listOutbox()).single.businessStatus,'UNREVIEWED');
    transport.api.close();
    clock=clock.add(const Duration(minutes:1));
    final foreign=OutboxTransport(store:db,api:api(MockClient((request) async=>
      http.Response(jsonEncode(challenge(jsonDecode(request.body) as Map,farm:2)),201))));
    await expectLater(foreign.syncOnce(),throwsA(isA<DeviceTransportException>()));
    expect((await db.listOutbox()).single.businessStatus,'UNREVIEWED');
    foreign.api.close();
  });
}

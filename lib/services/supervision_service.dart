import 'dart:convert';
import 'dart:typed_data';
import '../offline/device_identity.dart';
import '../offline/outbox.dart' show newOperationUuid;
import 'api_service.dart';

/// The exact decision survives a lost response; a retry never changes its UUID.
class PendingReconciliationDecision {
  PendingReconciliationDecision({required this.operationId,required int version,
    required String action,required String reason,Map<String,dynamic> payload=const {},
    String expectedEntityVersion=''}) : encoded=jsonEncode({
      'decision_uuid':newOperationUuid(),'expected_decision_version':version,
      'action':action,'reason':reason.trim(),'payload':payload,
      'expected_entity_version':expectedEntityVersion,
    });
  final String operationId,encoded;
  Map<String,dynamic> get data=>jsonDecode(encoded) as Map<String,dynamic>;
}

class SupervisionService {
  SupervisionService({required this.api,DeviceIdentity? identity})
    : identity=identity??AndroidDeviceIdentity();
  final ApiService api;
  final DeviceIdentity identity;
  Map<String,dynamic>? capabilities;
  String? _session;
  bool get owner=>capabilities?['role']=='OWNER';
  int get farmId=>capabilities!['exploitation'] as int;
  String? get _currentSession=>ApiService.token??globalToken;
  void _guard() {
    if(_session==null || _session!=_currentSession) {
      capabilities=null;
      throw StateError('La session a changé. Rouvrez la supervision.');
    }
  }
  Future<void> initialize() async {
    _session=_currentSession;
    _guard();
    final result=Map<String,dynamic>.from(await api.get('/me/capabilities/') as Map);
    _guard();
    if(result['user'] is! int || result['exploitation'] is! int ||
      (result['role']!='OWNER' && (result['capabilities'] as Map?)?['can_reconcile']!=true)) {
      throw StateError('La supervision n’est pas autorisée pour ce compte.');
    }
    capabilities=Map.unmodifiable(result);
  }
  Future<Map<String,dynamic>> _get(String path) async {
    _guard();
    final result=Map<String,dynamic>.from(await api.get(path) as Map);
    _guard();
    return result;
  }
  Future<Map<String,dynamic>> declarations({String state='NEEDS_RECONCILIATION',int page=1}) async {
    if(page<1) {throw ArgumentError('Page invalide.');}
    final query=Uri(queryParameters:{'state':state,'page':'$page'}).query;
    final result=await _get('/offline/reconciliation/?$query');
    final rows=result['results'];
    if(rows is! List || rows.length>50 || result['count'] is! int) {
      throw StateError('Réponse de supervision invalide.');
    }
    return result;
  }
  Future<Map<String,dynamic>> detail(String operationId,{int page=1}) async {
    if(!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(operationId) || page<1) {throw ArgumentError('Opération invalide.');}
    final result=await _get('/offline/reconciliation/$operationId/?decision_page=$page');
    if(result['decisions'] is! List || (result['decisions'] as List).length>50) {throw StateError('Historique de décisions invalide.');}
    return result;
  }
  Future<Map<String,dynamic>> cashSales(String operationId,{int page=1}) async {
    if(!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(operationId) || page<1) {throw ArgumentError('Opération invalide.');}
    return _get('/offline/reconciliation/$operationId/cash-sales/?page=$page');
  }
  Future<Map<String,dynamic>> task(int taskId) async {
    if(taskId<1) {throw ArgumentError('Tâche invalide.');}
    return _get('/tasks/$taskId/');
  }
  Future<Map<String,dynamic>> activity({int page=1,String? operationId,String? action,
    int? author,int? decider,DateTime? since,DateTime? until}) async {
    if(!owner || page<1) {throw StateError('Journal réservé au propriétaire.');}
    final query=Uri(queryParameters:{'page':'$page',if(operationId!=null)'operation_id':operationId,
      if(action!=null && action.isNotEmpty)'action':action,
      if(author!=null)'actor_user_id':'$author',if(decider!=null)'decision_actor_id':'$decider',
      if(since!=null)'since':since.toUtc().toIso8601String(),if(until!=null)'until':until.toUtc().toIso8601String(),
    }).query;
    final result=await _get('/audit-events/?$query');
    final rows=result['results'];
    if(rows is! List || rows.length>100 || rows.any((row)=>row is! Map || row['exploitation_id']!=farmId)) {
      throw StateError('Le journal ne correspond pas à cette exploitation.');
    }
    return result;
  }
  Future<Map<int,String>> memberNames() async {
    _guard();
    if(!owner) {return {capabilities!['user'] as int:(capabilities!['membership'] as Map?)?['username']?.toString()??'Vous'};}
    final rows=await api.get('/memberships/');
    _guard();
    if(rows is! List) {throw StateError('Liste des membres invalide.');}
    return {for(final row in rows.take(200))if(row is Map && row['user'] is int)
      row['user'] as int:row['username']?.toString()??'Utilisateur ${row['user']}'};
  }
  Future<Map<String,dynamic>> decide(PendingReconciliationDecision decision) async {
    _guard();
    if(!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(decision.operationId)) {throw ArgumentError('Opération invalide.');}
    final path='/offline/reconciliation/${decision.operationId}/';
    final data=decision.data;
    Map<String,String> proof={};
    if(!owner) {
      final device=capabilities?['primary_device'];
      if(device is! Map || device['id'] is! int) {throw StateError('Tablette principale active requise.');}
      final local=await identity.publicIdentity();_guard();
      if(local['installation_uuid']!=device['installation_uuid']) {throw StateError('Utilisez la tablette principale.');}
      final challenge=Map<String,dynamic>.from(await api.post('/devices/challenge/',
        {'device_id':device['id'],'purpose':'WRITE'}) as Map);_guard();
      if(challenge['device_id']!=device['id'] || challenge['user_id']!=capabilities!['user'] ||
        challenge['purpose']!='WRITE' || challenge['signature_contract']!='ELEVAGE-DEVICE-V1') {
        throw StateError('Challenge de tablette invalide.');
      }
      proof=await deviceProofHeaders(identity:identity,challengeId:challenge['id'] as String,
        deviceId:device['id'] as int,userId:capabilities!['user'] as int,purpose:'WRITE',method:'POST',
        pathAndQuery:'${Uri.parse(ApiService.baseUrl).path.replaceFirst(RegExp(r'/+$'),'')}$path',
        body:Uint8List.fromList(utf8.encode(jsonEncode(data))));_guard();
    }
    final result=Map<String,dynamic>.from(await api.postWithProof(path,data,proof) as Map);_guard();
    if(result['decision_uuid']!=data['decision_uuid'] || result['decision_actor_id']!=capabilities!['user']) {
      throw StateError('La confirmation ne correspond pas à votre décision.');
    }
    return result;
  }
}

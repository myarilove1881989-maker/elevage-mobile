import 'dart:convert';
import 'package:drift/drift.dart';
import 'outbox.dart';
import 'package:timezone/timezone.dart' as tz;
import '../services/health_notifications.dart';

bool healthTaskOverdue(Map task,DateTime now) {
  final health=task['health'];
  if(health is! Map || health['fulfilled']==true || task['status']=='CANCELLED')return false;
  final at=DateTime.tryParse('${health['planned_at']}');
  if(at!=null)return now.isAfter(at);
  try {
    final local=tz.TZDateTime.from(now,tz.getLocation(health['timezone'] as String));
    final planned=DateTime.parse('${task['date']}');
    return DateTime.utc(local.year,local.month,local.day).isAfter(DateTime.utc(planned.year,planned.month,planned.day));
  }catch(_){return health['overdue']==true;}
}

bool sameTaskField(String key,Object? a,Object? b) {
  Object? stable(Object? value) {
    if(key!='health' || value is! Map)return value;
    final data={...value}..remove('overdue')..remove('vaccine')..remove('lot_name')..remove('lot_closed');
    if(data['actual'] is Map)data['actual']={...data['actual'] as Map}..remove('operator_name');
    return data;
  }
  return canonicalDeclaration(stable(a))==canonicalDeclaration(stable(b));
}

List<Map<String,dynamic>> projectHealthTasks(List<dynamic> baseline,List<OutboxEntry> originals,int farm,int user) {
  final rows=[for(final raw in baseline)Map<String,dynamic>.from(raw as Map)];
  for(final row in rows) {
    final health=row['health'];
    if(health!=null && (health is! Map || health['exploitation']!=farm))throw StateError('Rendez-vous hors exploitation.');
    row['_health_pending']=false;row['_health_conflict']=false;row['_health_vaccination_pending']=false;
    for(final original in originals) {
      final d=original.declaration,p=d['payload'] as Map;
      if(d['exploitation_id']!=farm)throw StateError('Déclaration hors exploitation.');
      if(d['author_user_id']!=user || {'CONFIRMED','NOT_APPLIED','SUPERSEDED'}.contains(original.businessStatus))continue;
      if(p['task_id']!=row['id'])continue;
      if(d['entity_type']=='TASK')row['_health_pending']=true;
      if(d['entity_type']=='VACCINATION')row['_health_vaccination_pending']=true;
      if({'TASK','VACCINATION'}.contains(d['entity_type']) && original.businessStatus=='NEEDS_RECONCILIATION')row['_health_conflict']=true;
    }
  }
  return rows;
}

mixin HealthTaskCacheSql on GeneratedDatabase {
  Future<void> healthTaskReceipt(Map<String,dynamic> receipt,int farm) async {
    final task=receipt['health_task_snapshot'];if(task==null)return;
    final original=await customSelect('SELECT declaration FROM outbox WHERE operation_id=?',variables:[Variable(receipt['client_operation_id'] as String)]).getSingle();
    final d=jsonDecode(original.read<String>('declaration')) as Map;
    if(task is! Map)throw StateError('État sanitaire invalide.');
    final vaccination=receipt['vaccination_snapshot'];
    final validSource=d['entity_type']=='VACCINATION' && (d['payload'] as Map)['vaccine_version']==1 && vaccination is Map && vaccination['exploitation']==farm && '${vaccination['id']}'==receipt['server_entity_id'] && vaccination['planned_task']?['id']==task['id'];
    final taskSource=d['entity_type']=='TASK' && (d['payload'] as Map)['task_id']==task['id'];
    if((!validSource && !taskSource) || d['exploitation_id']!=farm ||
        task['id'] is! int || task['version'] is! int || task['health'] is! Map || task['health']['exploitation']!=farm)throw StateError('Confirmation sanitaire hors contexte.');
    final prior=await customSelect("SELECT payload FROM confirmed_cache WHERE collection='tasks' AND entity_id=?",variables:[Variable('${task['id']}')]).getSingleOrNull();
    if(prior!=null) {
      final old=jsonDecode(prior.read<String>('payload')) as Map;
      if((old['version'] as int? ?? 0)>task['version'])return;
      if(old['version']==task['version'] && old.keys.any((key)=>task.containsKey(key) && !sameTaskField(key,old[key],task[key])))throw StateError('Version de tâche contradictoire.');
    }
    await customStatement("INSERT OR REPLACE INTO confirmed_cache VALUES('tasks',?,?,?)",['${task['id']}',jsonEncode(task),DateTime.now().toUtc().millisecondsSinceEpoch]);
    HealthReminderCoordinator.current?.taskReceived(Map<String,dynamic>.from(task),farm);
  }
}

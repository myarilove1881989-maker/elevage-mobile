import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

abstract interface class HealthNotificationSink {
  Future<bool> allowed({bool request=false});
  Future<void> cancel(int id);
  Future<void> schedule(int id,String title,DateTime at);
}
class PluginHealthNotificationSink implements HealthNotificationSink {
  PluginHealthNotificationSink(this.plugin);
  final FlutterLocalNotificationsPlugin plugin;
  @override Future<bool> allowed({bool request=false})async {
    final android=plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if(android==null)return false;
    if(request)return await android.requestNotificationsPermission()??false;
    return await android.areNotificationsEnabled()??false;
  }
  @override Future<void> cancel(int id)=>plugin.cancel(id);
  @override Future<void> schedule(int id,String title,DateTime at)=>plugin.zonedSchedule(id,'Rendez-vous sanitaire',title,
    tz.TZDateTime.from(at,tz.local),const NotificationDetails(android:AndroidNotificationDetails('tasks','Tasks',importance:Importance.high,priority:Priority.high)),
    androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,uiLocalNotificationDateInterpretation:UILocalNotificationDateInterpretation.absoluteTime);
}

/// Local optional reminders over existing Tasks. This is not a transport queue.
class HealthReminderCoordinator {
  HealthReminderCoordinator({required this.sink,required this.preferences,DateTime Function()? clock}):clock=clock??DateTime.now;
  static HealthReminderCoordinator? current;
  final HealthNotificationSink sink;
  final Future<SharedPreferences> preferences;
  final DateTime Function() clock;
  Future<void> _tail=Future.value();int _epoch=0;
  int? _farm,_user;DateTime? _until;bool Function()? _valid;
  List<Map<String,dynamic>> _tasks=[];
  String scope(int farm,int user)=>'$farm:$user';
  Future<T> _serial<T>(Future<T> Function() task) {
    final result=_tail.then((_)=>task());_tail=result.then<void>((_) {},onError:(Object e,StackTrace s){});return result;
  }
  Future<bool> enabled(int farm,int user)async=>(await preferences).getBool('health_reminders:${scope(farm,user)}')??false;
  Future<bool> setEnabled(int farm,int user,bool value) async {
    final permitted=!value || await sink.allowed(request:true);
    await (await preferences).setBool('health_reminders:${scope(farm,user)}',value && permitted);
    if(!value || !permitted)await suspend();return value && permitted;
  }
  Future<void> suspend() {
    _epoch++;_farm=null;_user=null;_valid=null;_tasks=[];
    return _serial(() async {
      final prefs=await preferences;final registry=_registry(prefs);
      for(final id in registry.values)await sink.cancel(id);
    });
  }
  Map<String,int> _registry(SharedPreferences prefs) {
    final raw=prefs.getString('health_notification_ids');if(raw==null)return {};
    final data=jsonDecode(raw) as Map;return data.map((k,v)=>MapEntry(k as String,v as int));
  }
  Future<void> sync({required int farm,required int user,required List<dynamic> tasks,required bool Function() isCurrent,DateTime? validUntil}) {
    final epoch=++_epoch;_farm=farm;_user=user;_valid=isCurrent;_until=validUntil;
    _tasks=[for(final task in tasks)Map<String,dynamic>.from(task as Map)];
    return _serial(() async {
      bool valid()=>epoch==_epoch && isCurrent() && (validUntil==null || clock().isBefore(validUntil));
      final prefs=await preferences;final registry=_registry(prefs),wanted=<int>{};
      if(valid() && await enabled(farm,user) && await sink.allowed() && valid()) {
        for(final task in _tasks) {
          final health=task['health'];
          if(health is! Map || health['exploitation']!=farm || task['assigned_to']!=user || task['status']=='CANCELLED' || health['fulfilled']==true || health['planned_at']==null)continue;
          final at=DateTime.tryParse('${health['planned_at']}');
          if(at==null || !at.isAfter(clock()) || (validUntil!=null && !at.isBefore(validUntil)))continue;
          final key='${scope(farm,user)}:${task['id']}';
          int id;
          if(registry.containsKey(key)) {id=registry[key]!;} else {
            id=(prefs.getInt('health_notification_next')??1);
            if(id<1 || id>=2147483647 || registry.values.contains(id))throw StateError('Identifiant de rappel indisponible.');
            registry[key]=id;await prefs.setInt('health_notification_next',id+1);await prefs.setString('health_notification_ids',jsonEncode(registry));
          }
          if(!valid())break;
          await sink.schedule(id,'${task['title']}',at);wanted.add(id);
        }
      }
      // Cancel stale profile, postponed, cancelled, fulfilled or unauthorized reminders.
      for(final entry in registry.entries)if(!wanted.contains(entry.value) || !valid())await sink.cancel(entry.value);
    });
  }
  void tasksRefreshed(List<Map<String,dynamic>> tasks,int farm) {
    if(_farm!=farm || _user==null || _valid==null)return;
    final valid=_valid!,user=_user!,until=_until;
    unawaited(sync(farm:farm,user:user,tasks:tasks,isCurrent:valid,validUntil:until).catchError((Object _){}));
  }
  void taskReceived(Map<String,dynamic> task,int farm) {
    if(_farm!=farm || _user==null || _valid==null)return;
    final index=_tasks.indexWhere((row)=>row['id']==task['id']);
    if(index<0)return;
    if((_tasks[index]['version'] as int? ?? 0)>(task['version'] as int? ?? 0))return;
    _tasks[index]=task;
    final valid=_valid!,user=_user!,until=_until,tasks=[..._tasks];
    unawaited(sync(farm:farm,user:user,tasks:tasks,isCurrent:valid,validUntil:until).catchError((Object _){}));
  }
}

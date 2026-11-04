import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/health_notifications.dart';

class FakeHealthSink implements HealthNotificationSink {
  bool permission=true;int requests=0;Completer<void>? hold;
  final scheduled=<int,Map<String,dynamic>>{},cancelled=<int>[];
  @override Future<bool> allowed({bool request=false})async {if(request)requests++;return permission;}
  @override Future<void> cancel(int id)async {cancelled.add(id);scheduled.remove(id);}
  @override Future<void> schedule(int id,String title,DateTime at)async {if(hold!=null)await hold!.future;scheduled[id]={'title':title,'at':at};}
}
Map<String,dynamic> reminderTask(int id,{int farm=1,int user=2,String status='TODO',bool fulfilled=false,String? at='2026-11-04T09:00:00Z'})=>{
  'id':id,'title':'Rendez-vous $id','version':1,'assigned_to':user,'status':status,
  'health':{'exploitation':farm,'fulfilled':fulfilled,'planned_at':at}};
void main(){
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('explicit opt-in and OS permission are required, and date-only appointments invent no time',()async{
    final sink=FakeHealthSink(),service=HealthReminderCoordinator(sink:FakeHealthSink(),preferences:SharedPreferences.getInstance(),clock:()=>DateTime.utc(2026,11,3));
    await service.sync(farm:1,user:2,tasks:[reminderTask(1)],isCurrent:()=>true);expect((service.sink as FakeHealthSink).scheduled,isEmpty);
    final enabled=HealthReminderCoordinator(sink:sink,preferences:SharedPreferences.getInstance(),clock:()=>DateTime.utc(2026,11,3));
    sink.permission=false;expect(await enabled.setEnabled(1,2,true),false);await enabled.sync(farm:1,user:2,tasks:[reminderTask(1)],isCurrent:()=>true);expect(sink.scheduled,isEmpty);
    sink.permission=true;expect(await enabled.setEnabled(1,2,true),true);
    await enabled.sync(farm:1,user:2,tasks:[reminderTask(1,at:null)],isCurrent:()=>true);expect(sink.scheduled,isEmpty);
  });
  test('multiple task IDs and farm/user scopes never collide and remain stable after restart',()async{
    final sink=FakeHealthSink(),prefs=SharedPreferences.getInstance();
    final first=HealthReminderCoordinator(sink:sink,preferences:prefs,clock:()=>DateTime.utc(2026,11,3));await first.setEnabled(1,2,true);
    await first.sync(farm:1,user:2,tasks:[reminderTask(1),reminderTask(2)],isCurrent:()=>true);
    final ids=sink.scheduled.keys.toSet();expect(ids,hasLength(2));expect(ids.contains(0),false);
    await first.sync(farm:1,user:2,tasks:[reminderTask(1),reminderTask(2)],isCurrent:()=>true);expect(sink.scheduled.keys.toSet(),ids);
    final restarted=HealthReminderCoordinator(sink:sink,preferences:prefs,clock:()=>DateTime.utc(2026,11,3));
    await restarted.sync(farm:1,user:2,tasks:[reminderTask(1),reminderTask(2)],isCurrent:()=>true);expect(sink.scheduled.keys.toSet(),ids);
    await restarted.setEnabled(2,2,true);await restarted.sync(farm:2,user:2,tasks:[reminderTask(1,farm:2)],isCurrent:()=>true);
    expect(sink.scheduled,hasLength(1));expect(ids.intersection(sink.scheduled.keys.toSet()),isEmpty);
  });
  test('DONE without vaccination keeps its reminder; actual vaccination or cancellation removes it',()async{
    final sink=FakeHealthSink(),service=HealthReminderCoordinator(sink:FakeHealthSink(),preferences:SharedPreferences.getInstance(),clock:()=>DateTime.utc(2026,11,3));
    final coordinator=HealthReminderCoordinator(sink:sink,preferences:service.preferences,clock:service.clock);await coordinator.setEnabled(1,2,true);
    await coordinator.sync(farm:1,user:2,tasks:[reminderTask(1,status:'DONE')],isCurrent:()=>true);expect(sink.scheduled,hasLength(1));
    await coordinator.sync(farm:1,user:2,tasks:[reminderTask(1,status:'DONE',fulfilled:true)],isCurrent:()=>true);expect(sink.scheduled,isEmpty);
    await coordinator.sync(farm:1,user:2,tasks:[reminderTask(1,status:'CANCELLED')],isCurrent:()=>true);expect(sink.scheduled,isEmpty);
  });
  test('postponing replaces the same ID, past times and deadlines are not scheduled',()async{
    final sink=FakeHealthSink(),service=HealthReminderCoordinator(sink:FakeHealthSink(),preferences:SharedPreferences.getInstance(),clock:()=>DateTime.utc(2026,11,3));
    final coordinator=HealthReminderCoordinator(sink:sink,preferences:service.preferences,clock:service.clock);await coordinator.setEnabled(1,2,true);
    await coordinator.sync(farm:1,user:2,tasks:[reminderTask(1)],isCurrent:()=>true);final id=sink.scheduled.keys.single;
    await coordinator.sync(farm:1,user:2,tasks:[reminderTask(1,at:'2026-11-05T10:00:00Z')],isCurrent:()=>true);
    expect(sink.scheduled.keys.single,id);expect(sink.scheduled[id]!['at'],DateTime.utc(2026,11,5,10));
    await coordinator.sync(farm:1,user:2,tasks:[reminderTask(1,at:'2026-11-02T10:00:00Z')],isCurrent:()=>true);expect(sink.scheduled,isEmpty);
    await coordinator.sync(farm:1,user:2,tasks:[reminderTask(1)],isCurrent:()=>true,validUntil:DateTime.utc(2026,11,4));expect(sink.scheduled,isEmpty);
  });
  test('revocation while scheduling cannot leave a late notification behind',()async{
    final sink=FakeHealthSink(),coordinator=HealthReminderCoordinator(sink:FakeHealthSink(),preferences:SharedPreferences.getInstance(),clock:()=>DateTime.utc(2026,11,3));
    final service=HealthReminderCoordinator(sink:sink,preferences:coordinator.preferences,clock:coordinator.clock);await service.setEnabled(1,2,true);
    sink.hold=Completer<void>();bool current=true;
    final scheduled=service.sync(farm:1,user:2,tasks:[reminderTask(1)],isCurrent:()=>current);
    await Future<void>.delayed(const Duration(milliseconds:20));current=false;final stopped=service.suspend();sink.hold!.complete();
    await scheduled;await stopped;expect(sink.scheduled,isEmpty);
  });
}

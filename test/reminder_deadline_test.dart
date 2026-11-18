import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/health_notifications.dart';
import 'health_notifications_test.dart' show FakeHealthSink,reminderTask;
void main(){
  test('unknown and expired HTTP token lifetimes never authorize future reminders',(){
    final now=DateTime.utc(2026,11,3);
    for(final token in [null,'synthetic','a.e30.b','a.b.c'])expect(httpReminderDeadline(token,now),now);
    String token(Object exp)=>'a.${base64Url.encode(utf8.encode(jsonEncode({'exp':exp}))).replaceAll('=','')}.b';
    expect(httpReminderDeadline(token(now.millisecondsSinceEpoch~/1000-1),now),now);
    expect(httpReminderDeadline(token('2099'),now),now);
    final until=now.add(const Duration(hours:1));expect(httpReminderDeadline(token(until.millisecondsSinceEpoch~/1000),now),until);
  });
  test('sanitary native IDs do not replace the existing ordinary reminder ID zero',()async{
    SharedPreferences.setMockInitialValues({});final sink=FakeHealthSink();
    final service=HealthReminderCoordinator(sink:sink,preferences:SharedPreferences.getInstance(),clock:()=>DateTime.utc(2026,11,3));
    await service.setEnabled(1,2,true);await service.sync(farm:1,user:2,tasks:[reminderTask(1)],isCurrent:()=>true);
    expect(sink.scheduled.keys.single,lessThan(0));await service.suspend();expect(sink.cancelled, isNot(contains(0)));
  });
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/sync_coordinator.dart';

class MemorySyncState implements SyncStateStore {
  SyncSummary value=const SyncSummary(pending:2,conflicts:1);
  int successes=0;
  @override
  Future<SyncSummary> syncSummary() async=>value;
  @override
  Future<void> recordSyncSuccess(DateTime time) async {
    successes++;
    value=SyncSummary(pending:value.pending,conflicts:value.conflicts,lastSuccess:time);
  }
}

void main() {
  testWidgets('startup, manual and network triggers share one request without a personal session',(tester) async {
    final state=MemorySyncState(),network=StreamController<bool?>.broadcast(sync:true);
    final response=Completer<bool>();int requests=0;
    final sync=SyncCoordinator(store:state,networkChanges:()=>network.stream,
      synchronize:(){requests++;return response.future;});
    sync.setForeground(true);
    final manual=sync.trigger(manual:true);
    network.add(true);network.add(true);
    expect(requests,1);expect(sync.busy,true);
    response.complete(true);await tester.pump();await manual;
    expect(state.successes,1);expect(sync.summary.pending,2);expect(sync.summary.conflicts,1);
    sync.dispose();await network.close();await tester.pump(const Duration(minutes:6));
    expect(requests,1);
  });

  testWidgets('offline suppresses automatic retries and a restored network retries after cooldown',(tester) async {
    final state=MemorySyncState(),network=StreamController<bool?>.broadcast(sync:true);
    var now=DateTime.utc(2026,10,7);int requests=0;
    final sync=SyncCoordinator(store:state,networkChanges:()=>network.stream,clock:()=>now,
      synchronize:() async {requests++;throw StateError('synthetic connection unavailable');});
    sync.setForeground(true);await tester.pump();
    network.add(false);now=now.add(const Duration(minutes:5));await tester.pump(const Duration(minutes:5));
    expect(requests,1);expect(state.successes,0);expect(sync.summary.pending,2);
    network.add(true);await tester.pump();expect(requests,2);
    network.add(false);network.add(true);await tester.pump();expect(requests,2);
    now=now.add(const Duration(seconds:15));await tester.pump(const Duration(seconds:15));
    expect(requests,3);expect(sync.error,isNotNull);
    sync.dispose();await network.close();
  });

  testWidgets('pausing cancels timers and observers, resuming restarts one scheduler',(tester) async {
    final state=MemorySyncState(),network=StreamController<bool?>.broadcast(sync:true);
    var now=DateTime.utc(2026,10,7);int requests=0;
    final sync=SyncCoordinator(store:state,networkChanges:()=>network.stream,clock:()=>now,
      synchronize:() async {requests++;return true;});
    sync.setForeground(true);await tester.pump();expect(requests,1);
    sync.setForeground(false);network.add(true);
    now=now.add(const Duration(minutes:10));await tester.pump(const Duration(minutes:10));
    expect(requests,1);expect(network.hasListener,false);
    sync.setForeground(true);sync.setForeground(true);await tester.pump();expect(requests,2);
    sync.dispose();await network.close();
  });

  testWidgets('manual retry works offline and no server contact cannot invent last success',(tester) async {
    final state=MemorySyncState(),network=StreamController<bool?>.broadcast(sync:true);
    int requests=0;
    final sync=SyncCoordinator(store:state,networkChanges:()=>network.stream,
      synchronize:() async {requests++;return false;});
    sync.setForeground(true);await tester.pump();network.add(false);
    await sync.trigger(manual:true);
    expect(requests,2);expect(state.successes,0);expect(sync.summary.lastSuccess,isNull);
    sync.dispose();await network.close();
  });

  testWidgets('network observer error is bounded and does not expose raw details',(tester) async {
    final state=MemorySyncState(),network=StreamController<bool?>.broadcast(sync:true);
    final sync=SyncCoordinator(store:state,networkChanges:()=>network.stream,
      synchronize:() async {throw StateError('secret-url-should-not-be-shared');});
    sync.setForeground(true);await tester.pump();network.addError(StateError('native unavailable'));
    await tester.pump();expect(sync.networkAvailable,isNull);
    expect(sync.error,isNot(contains('secret-url')));expect(sync.summary.pending,2);
    sync.dispose();await network.close();
  });
}

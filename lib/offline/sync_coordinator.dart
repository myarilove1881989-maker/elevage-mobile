import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'sync_state.dart';
export 'sync_state.dart';

Stream<bool?> androidNetworkChanges()=>const EventChannel('elevage/network_state')
  .receiveBroadcastStream().map((value)=>value is bool?value:null);

/// One foreground scheduler, shared by all personal profiles of this device.
class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({required this.synchronize,required this.store,
    required this.networkChanges,this.interval=const Duration(minutes:5),
    this.cooldown=const Duration(seconds:15),DateTime Function()? clock}) :clock=clock??DateTime.now;
  final Future<bool> Function() synchronize;
  final SyncStateStore store;
  final Stream<bool?> Function() networkChanges;
  final Duration interval,cooldown;
  final DateTime Function() clock;
  SyncSummary summary=const SyncSummary();
  bool? networkAvailable;
  bool busy=false,foreground=false;
  String? error;
  bool _disposed=false;
  Timer? _timer;
  Timer? _deferred;
  StreamSubscription<bool?>? _subscription;
  Future<void>? _running;
  DateTime? _lastAttempt;
  int _networkEpoch=0;
  bool _automaticPending=false;

  void _notify() {if(!_disposed) notifyListeners();}
  Future<void> refreshSummary() async {
    final result=await store.syncSummary();
    if(_disposed) return;
    summary=result;_notify();
  }

  void setForeground(bool value) {
    if(_disposed || foreground==value) return;
    foreground=value;
    final epoch=++_networkEpoch;
    _timer?.cancel();_timer=null;
    _deferred?.cancel();_deferred=null;
    final previous=_subscription;_subscription=null;
    if(previous!=null) unawaited(previous.cancel());
    if(!value) {_notify();return;}
    // A resumed app must sample its new default network rather than retain an old value.
    networkAvailable=null;
    try {
      _subscription=networkChanges().listen((value) {
        if(_disposed || !foreground || epoch!=_networkEpoch) return;
        final restored=value==true && networkAvailable!=true;
        networkAvailable=value;_notify();
        if(restored) unawaited(trigger());
      },onError:(Object _) {
        if(!_disposed && foreground && epoch==_networkEpoch) {networkAvailable=null;_notify();}
      });
    } catch (_) {networkAvailable=null;}
    _timer=Timer.periodic(interval,(_)=>unawaited(trigger()));
    unawaited(trigger());
  }

  Future<void> trigger({bool manual=false}) {
    if(_disposed) return Future.value();
    if(_running!=null) {
      if(!manual) _automaticPending=true;
      return _running!;
    }
    final now=clock().toUtc();
    if(!manual && (!foreground || networkAvailable==false)) return Future.value();
    if(!manual && _lastAttempt!=null && now.difference(_lastAttempt!)<cooldown) {
      _deferred?.cancel();
      _deferred=Timer(cooldown-now.difference(_lastAttempt!),()=>unawaited(trigger()));
      return Future.value();
    }
    _deferred?.cancel();_deferred=null;
    _lastAttempt=now;
    final task=_run().whenComplete(() {
      _running=null;
      final pending=_automaticPending;_automaticPending=false;
      if(pending && foreground && !_disposed) unawaited(trigger());
    });
    _running=task;return task;
  }

  Future<void> _run() async {
    busy=true;error=null;_notify();
    try {
      if(await synchronize()) {
        await store.recordSyncSuccess(clock().toUtc());
        // A response started earlier must not overwrite a later Android loss event.
        networkAvailable??=true;
      }
    } catch (_) {
      // Keep credentials, URLs and raw server errors out of the shared tablet status.
      error='Synchronisation indisponible. Les déclarations restent conservées.';
    } finally {
      try {await refreshSummary();} catch (_) {
        error='État de synchronisation indisponible. Les déclarations restent conservées.';
      }
      busy=false;_notify();
    }
  }

  @override
  void dispose() {
    _disposed=true;foreground=false;_networkEpoch++;_timer?.cancel();_deferred?.cancel();
    final subscription=_subscription;
    if(subscription!=null) unawaited(subscription.cancel());
    super.dispose();
  }
}

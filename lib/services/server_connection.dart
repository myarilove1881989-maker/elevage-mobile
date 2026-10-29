import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/guarded_api_client.dart';

/// Android connectivity is a hint. Only an Élev'Age health response establishes
/// availability. A stale response cannot overwrite a newer foreground epoch.
class ServerConnection extends ChangeNotifier {
  ServerConnection({required this.baseUrl,http.Client? client,
    this.interval=const Duration(seconds:20),this.timeout=const Duration(seconds:5),this.check,
    DateTime Function()? clock}):_client=GuardedApiClient(client),clock=clock??DateTime.now;
  final Future<bool> Function()? check;
  final String baseUrl;
  final http.Client _client;
  final Duration interval,timeout;
  final DateTime Function() clock;
  bool? available;
  DateTime? lastSuccess;
  final _changes=StreamController<bool?>.broadcast();
  StreamSubscription<bool?>? _hints;
  Timer? _timer;
  Future<bool>? _flight;
  int _epoch=0;
  bool _disposed=false,_foreground=false;
  Stream<bool?> changes()=>Stream<bool?>.multi((sink) {
    final subscription=_changes.stream.listen(sink.add,onError:sink.addError);
    sink.add(available);sink.onCancel=subscription.cancel;
  });
  void start({Stream<bool?>? networkHints}) {
    if(_disposed || _foreground) return;
    _foreground=true;_epoch++;
    if(networkHints!=null) _hints=networkHints.listen((_) {unawaited(probe());},onError:(_){unawaited(probe());});
    _timer=Timer.periodic(interval,(_)=>unawaited(probe()));
    unawaited(probe());
  }
  void pause() {
    _foreground=false;_epoch++;_timer?.cancel();_timer=null;
    final sub=_hints;_hints=null;if(sub!=null) unawaited(sub.cancel());
    _flight=null;
  }
  Future<bool> probe() {
    if(_disposed) return Future.value(false);
    if(_flight!=null) return _flight!;
    final epoch=_epoch;
    final future=_probe(epoch);
    _flight=future;
    return future.whenComplete(() {if(epoch==_epoch) _flight=null;});
  }
  Future<bool> _probe(int epoch) async {
    var result=false;
    try {
      if(check!=null) {
        result=await check!().timeout(timeout);
      } else {
      final response=await _client.get(Uri.parse('$baseUrl/health/'),headers:{'Cache-Control':'no-cache'}).timeout(timeout);
      final body=jsonDecode(response.body);
      result=response.statusCode==200 && body is Map && body['status']=='ok';
      }
    } catch (_) {result=false;}
    if(!_disposed && epoch==_epoch) {
      available=result;
      if(result) lastSuccess=clock().toUtc();
      _changes.add(result);notifyListeners();
    }
    return result;
  }
  @override
  void dispose() {
    if(_disposed) return;
    pause();_disposed=true;_client.close();unawaited(_changes.close());super.dispose();
  }
}

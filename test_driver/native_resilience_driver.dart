import 'package:integration_test/integration_test_driver.dart';
Future<void> main()=>integrationDriver(timeout:const Duration(minutes:5),writeResponseOnFailure:true,
  responseDataCallback:(data) async {
    await writeResponseData(data);
    if(data?['stage']=='UPDATE_PENDING') {
      if(data?['update_pending_ready']!=true || data?['pending']!=2 ||
        data?['write_crash_rollback']!=true || data?['native_identity_preserved']!=true) {
        throw StateError('Incomplete update preparation');
      }
      return;
    }
    if(data?['stage']!='COMPLETE' || data?['resilience_complete']!=true ||
      data?['write_crash_rollback']!=true || data?['apk_update_preserved']!=true ||
      data?['native_identity_preserved']!=true || data?['backend_unavailable_preserved']!=true ||
      data?['sync_crash_recovered']!=true || data?['lost_response_idempotent']!=true ||
      data?['mid_sync_network_interrupted']!=true ||
      data?['originals']!=2 || data?['effects']!=2) {
      throw StateError('Native resilience incomplete: ${data?['stage']}');
    }
  });

import 'package:integration_test/integration_test_driver.dart';
Future<void> main()=>integrationDriver(timeout:const Duration(minutes:5),writeResponseOnFailure:true,
  responseDataCallback:(data) async {
    await writeResponseData(data);
    if(data?['real_business_complete']!=true || data?['stage']!='COMPLETE' ||
      data?['originals']!=7 || data?['jean']!=6 || data?['paul']!=1 ||
      data?['server_verified']!=true || data?['fifo_verified']!=true || data?['cash_verified']!=true ||
      data?['full_field_journey_verified']!=true ||
      data?['controlled_grant_expiry_verified']!=true ||
      data?['real_network_disconnect_verified']!=true ||
      data?['projected_stock_verified']!=true || data?['agenda_scopes_verified']!=true || data?['farm_isolation_verified']!=true ||
      data?['expired_tokens_verified']!=true || data?['disabled_author_verified']!=true || data?['revoked_recovery_verified']!=true) {
      throw StateError('Real native business journey incomplete: ${data?['stage']}');
    }
  });

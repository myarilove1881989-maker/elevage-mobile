import 'package:integration_test/integration_test_driver.dart';
Future<void> main()=>integrationDriver(timeout:const Duration(minutes:5),writeResponseOnFailure:true,
  responseDataCallback:(data) async {
    await writeResponseData(data);
    if(data?['real_business_complete']!=true || data?['stage']!='COMPLETE' ||
      data?['originals']!=7 || data?['jean']!=6 || data?['paul']!=1 ||
      data?['server_verified']!=true || data?['fifo_verified']!=true || data?['cash_verified']!=true ||
      data?['expired_tokens_verified']!=true || data?['disabled_author_verified']!=true || data?['revoked_recovery_verified']!=true) {
      throw StateError('Real native business journey incomplete: ${data?['stage']}');
    }
  });

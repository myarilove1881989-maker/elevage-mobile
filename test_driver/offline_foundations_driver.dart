import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(timeout:const Duration(minutes:5),writeResponseOnFailure:true,
  responseDataCallback:(data) async {
    await writeResponseData(data);
    if(data?['journey_complete']!=true || data?['stage']!='COMPLETE' ||
      data?['own_pending_operations']!=6 || data?['original_author_user_id']!=2 || data?['oversale_note_preserved']!=true ||
      data?['owner_supervision_complete']!=true || data?['shared_sync_complete']!=true) {
      throw StateError('Native journey incomplete; framework success alone is insufficient. Last stage: ${data?['stage']}');
    }
  });

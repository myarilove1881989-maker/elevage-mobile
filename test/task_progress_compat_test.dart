import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/api_service.dart';
import 'unified_access_harness.dart';
void main() {
  setUp((){SharedPreferences.setMockInitialValues({});tz.initializeTimeZones();ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();});
  for(final permitted in [true,false]) {
    test('signed task protocol requires the explicit progress right: $permitted',() async {
      final h=UnifiedAccessHarness()..healthAgenda=true;
      if(permitted)h.codes.add('agenda.progress');
      await h.start();final runtime=await h.runtime();
      try {
        await runtime.signIn('synthetic','1234');h.down=true;await runtime.connection.probe();
        final request=http.Request('PATCH',Uri.parse('${Config.apiUrl}/tasks/1/'))..body=jsonEncode({'status':'DONE','expected_version':1});
        if(permitted){
          final response=await runtime.request(request);expect(response.statusCode,202);
          final rows=await h.db.listOutbox();expect(rows,hasLength(1));
          expect(rows.single.declaration['entity_type'],'TASK');expect(rows.single.declaration['operation_type'],'UPDATE');
        }else{
          await expectLater(runtime.request(request),throwsStateError);
          expect(await h.db.listOutbox(),isEmpty);
        }
        expect(h.onlineWrites,isEmpty);
      }finally{
        runtime.dispose();await h.db.close();await h.network?.close();
        final directory=h.directory.absolute;
        if(!directory.path.startsWith('${Directory.systemTemp.absolute.path}${Platform.pathSeparator}'))throw StateError('Unexpected test directory');
        await directory.delete(recursive:true);
      }
    });
  }
}

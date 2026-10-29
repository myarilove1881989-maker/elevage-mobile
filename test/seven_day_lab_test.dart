import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/sync_coordinator.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'foundation_api_test.dart' show TestSecretStore, TestIdentity;
import 'sync_coordinator_test.dart' show MemorySyncState;

void main() {
  testWidgets('LAB injection exercises automatic return and retry without opening ordinary LAB transport',(tester) async {
    expect(Config.current.isLab,isTrue);
    var ordinaryRequests=0;
    final api=FoundationApi(baseUrl:Config.apiUrl,deviceIdentity:TestIdentity(),secrets:TestSecretStore(),
      client:MockClient((_) async {ordinaryRequests++;return http.Response('{}',200);}));
    final tablet=TabletController(api:api,secrets:TestSecretStore(),automaticSyncEnabled:true);
    expect(tablet.automaticSyncEnabled,isFalse);
    await expectLater(api.client.send(http.Request('GET',Uri.parse('${Config.apiUrl}/me/capabilities/'))),
      throwsA(isA<NetworkDestinationException>()));
    expect(ordinaryRequests,0);

    // No application transport or destination guard is bypassed. Only this injected
    // coordinator callback can reach the in-memory MockClient below.
    var now=DateTime.utc(2026,10,15),attempts=0;
    final network=StreamController<bool?>.broadcast(sync:true),state=MemorySyncState();
    final mock=MockClient((_) async {
      attempts++;return http.Response('{}',attempts==1?503:200);
    });
    final coordinator=SyncCoordinator(store:state,networkChanges:()=>network.stream,clock:()=>now,
      synchronize:() async {
        final response=await mock.get(Uri.parse('https://memory.invalid/api/sync'));
        if(response.statusCode!=200) throw StateError('Synthetic server failure');
        return true;
      });
    coordinator.setForeground(true);await tester.pump();
    expect(attempts,1);expect(state.successes,0);expect(state.value.pending,2);
    network.add(false);now=now.add(const Duration(hours:3));
    network.add(true);await tester.pump();
    expect(attempts,2);expect(state.successes,1);
    coordinator.dispose();mock.close();tablet.dispose();api.close();await network.close();
    expect(ordinaryRequests,0);
  },skip:!Config.current.isLab);
}

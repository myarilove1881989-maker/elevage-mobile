import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/offline/outbox.dart';
class ReceiptApi extends ApiService {
  ReceiptApi():super(client:MockClient((request) async=>http.Response('{}',202,request:request,
    headers:{'x-elevage-outbox-id':'synthetic-operation'})));
  List<OutboxEntry> rows=[];
  @override
  List<OutboxEntry> get localOperations=>rows;
  void receipt(String state,{String id='synthetic-operation'}) {
    rows=[OutboxEntry(declaration:{'client_operation_id':id},transportStatus:'SERVER_RECEIVED',
      businessStatus:state,attemptCount:1,lastError:'')];
  }
}
void main() {
  test('only the matching confirmed receipt clears pending feedback; conflict never claims success',() async {
    final api=ReceiptApi();addTearDown(api.close);
    await api.post('/payments/create/',{'client':11,'vente':51,'montant':5});
    expect(api.lastOperationMessage,contains('attente'));
    api.receipt('CONFIRMED',id:'another-operation');expect(api.lastOperationMessage,contains('attente'));
    api.receipt('UNREVIEWED');expect(api.lastOperationMessage,contains('attente'));
    api.receipt('NEEDS_RECONCILIATION');expect(api.lastOperationMessage,contains('Ne ressaisissez pas'));
    api.receipt('CONFIRMED');expect(api.lastOperationMessage,isNull);
    expect(api.operationFeedback('Confirmed'),'Confirmed');
  });
}

import '../services/api_service.dart';
import '../offline/outbox.dart' show newOperationUuid;

/// Uses only authenticated online HTTP. No aquatic command enters the outbox.
class AquaticService {
  AquaticService(this.api);
  final ApiService api;
  static const prefix = '/pisciculture/v1/';
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(await api.get('$prefix$path') as Map);
  Future<List<Map<String, dynamic>>> list(String path) async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final result = await read(
        '$path${path.contains('?') ? '&' : '?'}limit=100${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
      );
      rows.addAll(
        (result['results'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      cursor = result['next_cursor'] as String?;
      // Large lists are paged on their screen, never silently truncated.
      if (rows.length > 10000) {
        throw StateError('Affinez les filtres pour charger cette liste.');
      }
    } while (cursor != null);
    return rows;
  }

  Map<String, dynamic> command(Map<String, dynamic> fields) => {
    'operation_uuid': newOperationUuid(),
    'schema_version': 1,
    ...fields,
  };
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> command,
  ) async =>
      Map<String, dynamic>.from(await api.post('$prefix$path', command) as Map);
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> command,
    String etag,
  ) async => Map<String, dynamic>.from(
    await api.patchWithVersion('$prefix$path', command, etag) as Map,
  );
}

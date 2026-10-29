import 'dart:math';
import 'api_service.dart';
import 'permission_contract.dart';

class UserAdministrationService {
  UserAdministrationService(this.api);
  final ApiService api;
  String? _session;
  bool _authorized = false;
  int? _farm;
  void _guard() {
    if (!_authorized ||
        _session == null ||
        _session != (ApiService.sessionIdentity)) {
      _authorized = false;
      throw StateError('Connexion propriétaire requise.');
    }
  }

  Future<void> initialize() async {
    _authorized = false;
    _session = ApiService.sessionIdentity;
    if (_session == null) {
      throw StateError('Connexion propriétaire requise.');
    }
    final data = await api.get('/me/capabilities/');
    if (_session != (ApiService.sessionIdentity) ||
        data is! Map ||
        data['role'] != 'OWNER' ||
        data['user_administration_contract'] != 1) {
      throw StateError(
        'Gestion réservée au propriétaire sur un serveur compatible.',
      );
    }
    final raw = data['permission_contract'];
    if (raw is! Map<String, dynamic>) {
      throw StateError('Contrat de droits manquant.');
    }
    final rights = PermissionContract.decode(
      raw,
      userId: data['user'] as int,
      farmId: data['exploitation'] as int,
      role: 'OWNER',
      rightsVersion: data['membership']['version'] as int,
    );
    if (!rights.allows('users.manage')) {
      throw StateError('Gestion des utilisateurs refusée.');
    }
    _farm = data['exploitation'] as int;
    _authorized = true;
  }

  Future<List<Map<String, dynamic>>> list() async {
    _guard();
    final result = await api.get('/memberships/');
    _guard();
    if (result is! List ||
        result.any(
          (row) =>
              row is! Map ||
              row['role'] is! String ||
              row['exploitation'] != _farm,
        )) {
      throw StateError('Liste des utilisateurs invalide.');
    }
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> _confirm(Future<dynamic> Function() send) async {
    _guard();
    final result = await send();
    _guard();
    if (result is! Map ||
        result['role'] != 'OPERATEUR' ||
        result['version'] is! int ||
        result['exploitation'] != _farm) {
      throw StateError('Confirmation serveur invalide. Actualisez la liste.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) =>
      _confirm(() => api.post('/memberships/', data));
  Future<Map<String, dynamic>> update(
    Map<String, dynamic> member,
    Map<String, dynamic> data,
  ) => _confirm(
    () => api.patch('/memberships/${member['id']}/', {
      ...data,
      'expected_version': member['version'],
    }),
  );
  Future<Map<String, dynamic>> reset(
    Map<String, dynamic> member,
    String password,
  ) => _confirm(
    () => api.post('/memberships/${member['id']}/reset-password/', {
      'new_password': password,
      'expected_version': member['version'],
    }),
  );
  int? get farmId => _farm;
  static String generatePassword() {
    final random = Random.secure();
    const alphabet =
        '0123456789';
    return List.generate(
      4,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}

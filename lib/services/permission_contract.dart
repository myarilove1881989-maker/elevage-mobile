/// HTTP permission contract. It never replaces a verified signed offline grant.
class PermissionContract {
  PermissionContract._(this.userId, this.farmId, this.role, this.rightsVersion, this.permissions, this.httpVersion);
  final int httpVersion;
  static const version = 1;
  static const ownerHttpActions = {'lots.create','lots.update','lots.delete','weights.update','weights.delete','egg_sales.update','expenses.update','animal_sales.update'};
  static const domains = <String, Set<String>>{
    'vaccinations': {'read','create','update','delete','loss'},
    'purchases': {'read','create','delete'}, 'animal_sales': {'read','create','update','delete','cancel'},
    'expenses': {'read','create','update','delete','cancel'}, 'mortality': {'read','create','delete','cancel'},
    'births': {'read','create','delete'}, 'donations': {'read','create','delete','cancel'},
    'thefts': {'read','create','delete','cancel'}, 'clients': {'read','create'},
    'lots': {'read','create','update','delete'}, 'stocks': {'read'}, 'species': {'read','create'},
    'egg_collections': {'read','create','update','delete'}, 'egg_sales': {'read','create','update','delete','cancel'},
    'cash': {'read','create'}, 'feed': {'read','create','update','delete'}, 'weights': {'read','create','update','delete'},
    'agenda': {'read','progress','plan'}, 'history': {'read'}, 'finance': {'read'},
    'users': {'manage'}, 'devices': {'manage'}, 'reconciliation': {'read','decide'},
  };
  static final catalogue = Set<String>.unmodifiable([
    for (final domain in domains.entries) for (final action in domain.value) '${domain.key}.$action',
  ]);
  final int userId, farmId, rightsVersion;
  final String role;
  final Set<String> permissions;

  static PermissionContract decode(Map<String,dynamic> data, {
    required int userId, required int farmId, required String role, required int rightsVersion, bool allowHttpV2=false,
  }) {
    final raw = data['permissions'];
    if (!(data['version']==version || (allowHttpV2 && data['version']==2)) || data['user'] != userId || data['exploitation'] != farmId ||
        data['role'] != role || data['rights_version'] != rightsVersion ||
        userId < 1 || farmId < 1 || rightsVersion < 1 || !{'OWNER','OPERATEUR'}.contains(role) ||
        raw is! List || raw.length > catalogue.length || raw.any((code) => code is! String || !catalogue.contains(code)) ||
        raw.toSet().length != raw.length) {
      throw StateError('Contrat de permissions invalide ou incompatible.');
    }
    final codes = Set<String>.unmodifiable(raw.cast<String>());
    if (!codes.contains('finance.read') ||
        ((data['version']==1 || role=='OPERATEUR') && codes.intersection(ownerHttpActions).isNotEmpty) ||
        (role == 'OPERATEUR' && codes.intersection({'users.manage','devices.manage'}).isNotEmpty) ||
        (role == 'OWNER' && ((data['version'] == 1 && codes.any(isBusinessWrite)) || codes.contains('agenda.progress')))) {
      throw StateError('Permissions incompatibles avec le rôle.');
    }
    return PermissionContract._(userId,farmId,role,rightsVersion,codes,data['version'] as int);
  }

  static bool isBusinessWrite(String code) => !code.endsWith('.read') &&
    !{'agenda','users','devices','reconciliation'}.contains(code.split('.').first);

  bool allows(String action, {bool revoked = false}) => !revoked && catalogue.contains(action) &&
    permissions.contains(action) && !(role == 'OWNER' && httpVersion == 1 && isBusinessWrite(action));

  static String? operationAction(String kind, String operation) {
    if(kind=='VACCINATION')return {'CREATE':'vaccinations.create','UPDATE':'vaccinations.update','REVERSE':'vaccinations.delete'}[operation];
    if(kind=='ALIMENTATION' && {'UPDATE','REVERSE'}.contains(operation)) return operation=='UPDATE'?'feed.update':'feed.delete';
    if(operation=='REVERSE') {
      const cancelDomains={'VENTE_ANIMAUX':'animal_sales','VENTE_OEUFS':'egg_sales',
        'DEPENSE':'expenses','MORTALITE':'mortality','DON':'donations','VOL':'thefts'};
      final domain=cancelDomains[kind];
      return domain==null?null:'$domain.cancel';
    }
    if (kind == 'COLLECTE_OEUFS' && operation == 'UPDATE') return 'egg_collections.update';
    if (kind == 'TASK' && operation == 'UPDATE') return 'agenda.progress';
    if (operation != 'CREATE') return null;
    const mapping = {'ACHAT':'purchases','VENTE':'animal_sales','VENTE_ANIMAUX':'animal_sales','VENTE_OEUFS':'egg_sales',
      'DEPENSE':'expenses','MORTALITE':'mortality','NAISSANCE':'births','DON':'donations',
      'VOL':'thefts','CLIENT':'clients','COLLECTE_OEUFS':'egg_collections','ENCAISSEMENT':'cash',
      'ALIMENTATION':'feed','PESEE':'weights'};
    final domain = mapping[kind];
    return domain == null ? null : '$domain.create';
  }
}

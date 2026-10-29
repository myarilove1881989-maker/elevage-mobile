/// Translates only existing, reviewed terrain contracts. It does not invent a
/// new offline endpoint, drop unknown fields, or infer unsupported deletions.
class ClassicTerrainCommand {
  ClassicTerrainCommand(this.kind,this.payload,{this.operation='CREATE',this.expectedVersion='',this.at});
  final String kind,operation,expectedVersion;
  final Map<String,dynamic> payload;
  final String? at;
  static Map<String,dynamic> reference(dynamic id) {
    if(id is! int || id<1) throw ArgumentError('Choisissez une référence déjà disponible.');
    return {'server_id':id};
  }
  static String decimal(dynamic value,int scale) {
    final text=value.toString();
    final match=RegExp('^([0-9]{1,10})(?:\\.([0-9]{1,$scale}))?\$').firstMatch(text);
    if(match==null) throw ArgumentError('Vérifiez la précision du montant.');
    return '${match[1]}.${(match[2]??'').padRight(scale,'0')}';
  }
  static ClassicTerrainCommand? decode(String method,String path,Map<String,dynamic> source) {
    if(method!='POST') return null;
    var data=Map<String,dynamic>.from(source);
    final at=(data.remove('date')??data.remove('collecte_at')??data.remove('distribution_at')??data.remove('pesee_at'))?.toString();
    String? kind;
    Set<String> allowed={};
    switch(path) {
      case '/achats/create/':
        kind='ACHAT';allowed={'nom_lot','espece','quantite','prix_total','prix_unitaire','fournisseur','note','type_production','statut_production','date_naissance','age_arrivee_semaines','date_debut_ponte'};
      case '/depenses/create/':
        kind='DEPENSE';allowed={'lot','categorie','montant','note'};
      case '/clients/create/':
        kind='CLIENT';allowed={'nom','telephone','pays','ville'};
      case '/mouvements/create/':
        kind=data.remove('type_mouvement') as String?;
        if(kind=='VENTE') kind='VENTE_ANIMAUX';
        if(kind=='NAISSANCE') {
          allowed={'lot','total_naissances','mort_nes','nom_nouveau_lot','type_production','note'};
        } else if(kind=='VENTE_ANIMAUX') {
          allowed={'lot','client','quantite','prix_unitaire','note'};
        } else if({'MORTALITE','DON','VOL'}.contains(kind)) {
          // The old form sends an unused price for these stock observations.
          data.remove('prix_unitaire');allowed={'lot','quantite','note'};
        } else {return null;}
      case '/oeufs/collectes/':
        kind='COLLECTE_OEUFS';allowed={'lot','nombre_collecte','nombre_alveoles','oeufs_restants','nombre_casses','nombre_declasses','nombre_consommes_donnes','note'};
      case '/alimentation/distributions/':
        kind='ALIMENTATION';allowed={'lot','aliment','quantite_kg','prix_kg','depense','note'};
      case '/production/pesees/':
        kind='PESEE';allowed={'lot','nombre_animaux_peses','poids_total_kg','note'};
      case '/oeufs/ventes/':
        kind='VENTE_OEUFS';allowed={'lot','client','conditionnement','nombre_conditionnements','oeufs_par_conditionnement','prix_unitaire_conditionnement','nombre_alveoles','oeufs_supplementaires','prix_total','note'};
      case '/payments/create/':
        // FarmerRuntime resolves explicit mode and authenticated sale references
        // asynchronously. This stateless decoder must not infer them.
        return null;
      default:return null;
    }
    if(data.keys.any((key)=>!allowed.contains(key))) throw ArgumentError('Cette saisie doit être effectuée avec Internet.');
    if(kind=='DEPENSE' && data.containsKey('categorie')) data['categorie_id']=data.remove('categorie');
    if(data.containsKey('lot')) data['lot_ref']=reference(data.remove('lot'));
    if(data.containsKey('client')) data['client_ref']=reference(data.remove('client'));
    if(data.containsKey('depense')) data['depense_ref']=reference(data.remove('depense'));
    for(final key in {'montant','montant_recu','prix_total','prix_unitaire','prix_kg','prix_unitaire_conditionnement'}) {
      if(data[key]!=null) data[key]=decimal(data[key],2);
    }
    for(final key in {'quantite_kg','poids_total_kg'}) {
      if(data[key]!=null) data[key]=decimal(data[key],3);
    }
    return ClassicTerrainCommand(kind!,data,at:at);
  }
}

import 'operation_history.dart';

/// Presentation only. Original declarations and audit fields are never modified.
class HistoryNames {
  final Map<String,String> lots={}, clients={}, categories={}, authors={};
  String? resolve(Map<String,String> values,dynamic ref) {
    if(ref is Map) ref=ref['server_id']??ref['local_uuid'];
    return ref==null?null:values[ref.toString()];
  }
  void add(String collection,dynamic rows) {
    if(rows is Map) rows=rows['results']??[];
    if(rows is! List) return;
    final target=collection=='lots'?lots:collection=='clients'?clients:categories;
    for(final row in rows.whereType<Map>()) {
      final name=row['nom']??row['name'];
      if(name is String && name.trim().isNotEmpty) target[row['id'].toString()]=name;
    }
  }
}
String readableHistoryDate(String raw) {
  final d=DateTime.tryParse(raw)?.toLocal();
  if(d==null) return 'Date non renseignée';
  String n(int v)=>v.toString().padLeft(2,'0');
  return '${n(d.day)}/${n(d.month)}/${d.year} à ${n(d.hour)}:${n(d.minute)}';
}
String simpleHistoryStatus(OperationHistoryItem item) {
  if({'NOT_APPLIED','NEEDS_RECONCILIATION'}.contains(item.businessState) || item.transportState=='TRANSPORT_BLOCKED') return 'Échec';
  if({'CONFIRMED','SUPERSEDED'}.contains(item.businessState)) return 'Synchronisée';
  return 'En attente';
}
String historyAuthor(OperationHistoryItem item,HistoryNames names) =>
  names.authors[item.authorId?.toString()] ??
  (!item.author.startsWith('Utilisateur ') ? item.author : 'Éleveur non renseigné');
List<String> businessHistoryDetails(OperationHistoryItem item,HistoryNames names) {
  final p=item.data, result=<String>[];
  dynamic value(List<String> keys) {for(final k in keys) {if(p[k]!=null) return p[k];} return null;}
  String? text(dynamic v)=>v is String && v.trim().isNotEmpty?v:null;
  final lot=text(value(['lot_nom','nom_lot']))??names.resolve(names.lots,value(['lot_ref','lot','lot_id']));
  if(lot!=null) result.add(lot);
  final species=text(value(['espece_nom','species_name']));
  if(species!=null) result.add(species);
  final client=text(value(['client_nom']))??names.resolve(names.clients,value(['client_ref','client','client_id']));
  if(client!=null) result.add('Client : $client');
  final supplier=text(p['fournisseur']); if(supplier!=null) result.add('Fournisseur : $supplier');
  final category=text(p['categorie_nom'])??names.resolve(names.categories,value(['categorie_id','categorie']));
  if(category!=null) result.add(category);
  num? number(dynamic v)=>v is num?v:num.tryParse(v?.toString()??'');
  String fmt(num v)=>v==v.roundToDouble()?v.toInt().toString():v.toStringAsFixed(2).replaceAll('.',',');
  void amount(String label,dynamic v,String unit) {final n=number(v); if(n!=null) result.add('$label${fmt(n)} $unit');}
  final kind=item.entityType;
  if(kind.contains('COLLECTE') || kind.contains('collecteoeufs')) {
    final count=number(p['nombre_collecte'])??(p.containsKey('nombre_alveoles') || p.containsKey('oeufs_restants')?((number(p['nombre_alveoles'])??0)*30+(number(p['oeufs_restants'])??0)):null);
    final discarded=(number(p['nombre_casses'])??0)+(number(p['nombre_declasses'])??0)+(number(p['nombre_consommes_donnes'])??0);
    amount('Collectés : ',count,'œufs'); amount('Écartés : ',discarded,'œufs');
    amount('Commercialisables : ',number(p['nombre_commercialisable'])??(count==null?null:count-discarded),'œufs');
  } else if(kind.contains('NAISSANCE') || p.containsKey('total_naissances')) {
    final total=number(p['total_naissances']), dead=number(p['mort_nes']);
    if(total!=null && dead!=null) amount('Nés vivants : ',total-dead,'animaux');
    if(total!=null && dead==null) amount('Naissances : ',total,'animaux');
    amount('Mort-nés : ',dead,'animaux');
  } else if(kind.contains('ALIMENTATION') || kind.contains('consommationaliment')) {
    amount('',p['quantite_kg'],'kg'); final food=text(p['aliment']); if(food!=null) result.add(food);
  } else if(kind.contains('VENTE_OEUFS') || kind.contains('venteoeufs')) {
    final qty=number(p['nombre_oeufs'])??(number(p['nombre_conditionnements'])!=null && number(p['oeufs_par_conditionnement'])!=null
      ?number(p['nombre_conditionnements'])!*number(p['oeufs_par_conditionnement'])!:null);
    amount('',qty,'œufs');
  } else {amount('',p['quantite'],'animaux');}
  dynamic total=value(['montant_total','prix_total','montant','montant_recu']);
  if(total==null && kind.contains('VENTE') && number(p['prix_unitaire'])!=null && number(p['quantite'])!=null) total=number(p['prix_unitaire'])!*number(p['quantite'])!;
  if(total==null && kind.contains('VENTE_OEUFS') && number(p['prix_unitaire_conditionnement'])!=null && number(p['nombre_conditionnements'])!=null) total=number(p['prix_unitaire_conditionnement'])!*number(p['nombre_conditionnements'])!;
  amount(kind.contains('VENTE')?'Total : ':'Montant : ',total,'FCFA');
  if(item.businessState=='SUPERSEDED') result.add('Annulée — historique conservé');
  if(simpleHistoryStatus(item)=='Échec') result.add('À vérifier avec le propriétaire');
  return result.toSet().toList();
}

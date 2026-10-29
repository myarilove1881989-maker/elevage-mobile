import 'package:flutter/material.dart';
import '../services/operation_history.dart';
import '../services/history_presentation.dart';

class OperationHistoryList extends StatelessWidget {
  const OperationHistoryList({super.key,required this.items,this.names});
  final List<OperationHistoryItem> items;
  final HistoryNames? names;
  IconData icon(String kind) {
    if(kind.contains('VENTE') || kind.contains('vente')) return Icons.point_of_sale;
    if(kind.contains('COLLECTE') || kind.contains('collecte')) return Icons.egg_outlined;
    if(kind.contains('DEPENSE') || kind.contains('depense')) return Icons.receipt_long_outlined;
    if(kind.contains('ENCAISSEMENT') || kind.contains('payment')) return Icons.payments_outlined;
    if(kind.contains('NAISSANCE')) return Icons.child_friendly;
    if(kind.contains('ALIMENTATION')) return Icons.grass;
    return Icons.event_note;
  }
  @override
  Widget build(BuildContext context) {
    final lookup=names??HistoryNames();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      for(final item in items) Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
        Wrap(spacing:10,runSpacing:4,crossAxisAlignment:WrapCrossAlignment.center,children:[
          Icon(icon(item.entityType)),Text(item.type,style:Theme.of(context).textTheme.titleMedium),
          Chip(label:Text(simpleHistoryStatus(item)),visualDensity:VisualDensity.compact)]),
        Text('${readableHistoryDate(item.businessDate)} • ${historyAuthor(item,lookup)}'),
        if(businessHistoryDetails(item,lookup).isNotEmpty)
          Text(businessHistoryDetails(item,lookup).join(' • ')),
        if(item.reason!=null && item.reason!.isNotEmpty) Text('Motif : ${item.reason}'),
      ]))),
      if(items.isEmpty) const Text('Aucune opération pour ces filtres.'),
    ]);
  }
}

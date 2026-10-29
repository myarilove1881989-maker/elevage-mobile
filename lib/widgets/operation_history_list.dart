import 'package:flutter/material.dart';
import '../services/operation_history.dart';

/// Read-only by construction: no delete callback or action.
class OperationHistoryList extends StatelessWidget {
  const OperationHistoryList({super.key, required this.items});
  final List<OperationHistoryItem> items;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in items)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.type, style: Theme.of(context).textTheme.titleMedium),
                Text('${item.author} • ${item.status}'),
                Text('Date métier : ${item.businessDate}'),
                Text('Enregistrement : ${item.recordedDate}'),
                if (item.receivedDate != null)
                  Text('Réception serveur : ${item.receivedDate}'),
                if (item.details.isNotEmpty) Text(item.details),
                if (item.reason != null) Text('Motif : ${item.reason}'),
                if (item.original != null) Text('Original : ${item.original}'),
                if (item.compensation != null)
                  Text('Compensation : ${item.compensation}'),
                ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('Référence de l’opération'),
                  children:[SelectableText(item.identity)]),
              ],
            ),
          ),
        ),
      if (items.isEmpty) const Text('Aucun événement disponible.'),
    ],
  );
}

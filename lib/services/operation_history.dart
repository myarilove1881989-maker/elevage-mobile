import '../offline/outbox.dart';
import '../widgets/operation_status.dart';

class OperationHistoryItem {
  OperationHistoryItem({
    required this.identity,
    required this.author,
    required this.type,
    required this.status,
    required this.businessDate,
    required this.recordedDate,
    required this.details,
    this.receivedDate,
    this.reason,
    this.original,
    this.compensation,
  });
  final String identity,
      author,
      type,
      status,
      businessDate,
      recordedDate,
      details;
  final String? receivedDate, reason, original, compensation;

  factory OperationHistoryItem.local(OutboxEntry entry) {
    final d = entry.declaration;
    final p = d['payload'] as Map;
    return OperationHistoryItem(
      identity: entry.operationId,
      author: 'Utilisateur ${entry.authorId}',
      type: '${d['operation_type']=='REVERSE'?'Annulation — ':''}${historyTypeLabel(d['entity_type'].toString())}',
      status: entry.businessStatus=='SUPERSEDED' && entry.lastError=='BUSINESS_EFFECT_REVERSED'
        ?'Annulée — original conservé':operationStatus(
        transport: entry.transportStatus,
        business: entry.businessStatus,
      ),
      businessDate: d['business_occurred_at']?.toString() ?? 'Non disponible',
      recordedDate: d['local_recorded_at']?.toString() ?? 'Non disponible',
      receivedDate: entry.receivedAt?.toIso8601String(),
      details: historyDetails(p),
      reason:p['reason']?.toString() ?? (entry.lastError.isEmpty?null:historyReasonLabel(entry.lastError)),
      original:p['original_operation_id']?.toString(),
      compensation:d['operation_type']=='REVERSE'?entry.operationId:null,
    );
  }
}

String historyReasonLabel(String code)=>const {
  'SALE_HAS_ACTIVE_ALLOCATIONS':'Paiement affecté à cette vente : résolution métier nécessaire.',
  'EXPENSE_HAS_ACTIVE_FEED_DECLARATION':'Dépense liée à une distribution : résolution métier nécessaire.',
  'EXPENSE_HAS_ACTIVE_FEED':'Dépense liée à une distribution : résolution métier nécessaire.',
  'BUSINESS_EFFECT_ALREADY_REVERSED':'Opération déjà annulée.',
  'CANCEL_ALREADY_APPLIED':'Opération déjà annulée.',
  'CANCEL_LEGACY_ORIGINAL':'Ancienne autorisation : cette opération ne relève pas du nouveau parcours d’annulation.',
  'OFFLINE_PERMISSION_DENIED':'Permission nécessaire absente.',
  'AUTHOR_RIGHTS_CHANGED':'Autorisation invalidée.',
  'DEPENDENCY_NOT_APPLIED':'Opération liée non confirmée.',
  'STOCK_INSUFFICIENT':'Stock disponible insuffisant.',
}[code]??'Une vérification par le propriétaire est nécessaire.';

String historyTypeLabel(String code) =>
    const {
      'DEPENSE': 'Dépense',
      'ACHAT': 'Achat',
      'VENTE_ANIMAUX': 'Vente',
      'VENTE_OEUFS': 'Vente d’œufs',
      'CLIENT': 'Client',
      'TASK': 'Tâche',
      'MORTALITE': 'Mortalité',
      'NAISSANCE': 'Naissance',
      'DON': 'Don',
      'VOL': 'Vol',
      'COLLECTE_OEUFS': 'Collecte d’œufs',
      'ENCAISSEMENT': 'Encaissement',
      'ALIMENTATION': 'Alimentation',
      'PESEE': 'Pesée',
      'core.depense': 'Dépense',
      'core.achat': 'Achat',
      'core.vente': 'Vente',
      'core.venteoeufs': 'Vente d’œufs',
      'core.mouvement': 'Mouvement',
      'core.mouvementoeufs': 'Mouvement d’œufs',
      'core.collecteoeufs': 'Collecte d’œufs',
      'core.consommationaliment': 'Alimentation',
      'core.peseeproduction': 'Pesée',
      'core.task': 'Tâche',
      'core.client': 'Client',
      'core.payment': 'Encaissement',
      'core.lettrage': 'Affectation de paiement',
      'core.lot': 'Lot',
      'core.exploitation': 'Exploitation',
      'core.expensecancellation': 'Annulation de dépense',
      'core.terrainstockadjustment': 'Compensation de stock',
      'core.terrainsubmission': 'Déclaration',
      'core.terrainoutcome': 'État de déclaration',
      'core.terraindecision': 'Décision de rapprochement',
    }[code] ??
    'Opération';

String _historyValue(dynamic value) {
  if (value is Map) {
    return value['server_id']?.toString() ??
        value['local_uuid']?.toString() ??
        'Référence conservée';
  }
  return value.toString();
}

String historyDetails(Map data) => [
  for (final key in [
    'lot',
    'lot_id',
    'quantite',
    'nombre_oeufs',
    'montant',
    'montant_total',
    'prix_total',
  ])
    if (data[key] != null)
      '${const {'lot': 'Lot', 'lot_id': 'Lot', 'quantite': 'Quantité', 'nombre_oeufs': 'Œufs', 'montant': 'Montant', 'montant_total': 'Montant total', 'prix_total': 'Prix total'}[key]} : ${_historyValue(data[key])}',
].join(' • ');

/// Group composite server events by operation UUID (or correlation for REST).
/// Pagination is grouped per loaded page; cross-page merging belongs to the caller.
List<OperationHistoryItem> serverHistory(List<Map<String, dynamic>> events) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final event in events) {
    final key =
        (event['operation_id'] ??
                event['correlation_id'] ??
                'event-${event['id']}')
            .toString();
    groups.putIfAbsent(key, () => []).add(event);
  }
  return groups.entries.map((group) {
    final first = group.value.first;
    final reasons = <String>{};
    final details = <String>{};
    final originalAuthors = <String>{};
    final decisionActors = <String>{};
    String? originalBusinessDate;
    String? businessStatus, businessReason;
    String? original, compensation;
    var cancelled = false;
    for (final event in group.value) {
      final data = Map<String, dynamic>.from(event['after_data'] as Map? ?? {});
      // Loaded events are newest first. Do not replace a current confirmation
      // with the status of an older, superseded effect in the same UUID group.
      if (businessStatus == null &&
          data['business_status'] is String &&
          businessStates.contains(data['business_status'])) {
        businessStatus = data['business_status'] as String;
        businessReason = data['reason_code']?.toString();
      }
      if (data['created_by_id'] != null) {
        originalAuthors.add('Utilisateur ${data['created_by_id']}');
      }
      if (event['decision_actor_id'] != null) {
        decisionActors.add('Utilisateur ${event['decision_actor_id']}');
      }
      originalBusinessDate ??= data['date']?.toString();
      final reason =
          (data['cancellation_reason'] ??
                  data['reason'] ??
                  event['reason_text'])
              ?.toString();
      if (reason != null && reason.isNotEmpty) reasons.add(reason);
      final detail = historyDetails(data);
      if (detail.isNotEmpty) details.add(detail);
      cancelled |=
          data['voided_at'] != null ||
          data['status'] == 'CANCELLED' ||
          event['reason_code'] == 'EXPENSE_CANCELLED';
      if (event['entity_type'] == 'core.expensecancellation') {
        original = 'Dépense ${data['expense_id']}';
        compensation = 'Annulation ${event['entity_id']}';
      }
      if (event['entity_type'] == 'core.terrainstockadjustment') {
        original = 'Déclaration ${data['submission_id']}';
        compensation = 'Compensation ${event['entity_id']}';
      }
    }
    final actor = 'Utilisateur ${first['actor_user_id'] ?? 'inconnu'}';
    final author = originalAuthors.isEmpty ? actor : originalAuthors.join(', ');
    return OperationHistoryItem(
      identity: group.key,
      author:
          '$author${author == actor ? '' : ' • événement par $actor'}${decisionActors.isEmpty ? '' : ' • décision par ${decisionActors.join(', ')}'}',
      type: group.value
          .map((e) => historyTypeLabel(e['entity_type'].toString()))
          .toSet()
          .join(' / '),
      status: businessStatus != null
          ? businessStatus == 'SUPERSEDED' &&
                    businessReason == 'BUSINESS_EFFECT_REVERSED'
                ? 'Annulée — original conservé'
                : operationStatus(
                    transport: 'SERVER_RECEIVED',
                    business: businessStatus,
                  )
          : cancelled
          ? 'Annulée — original conservé'
          : 'Événement serveur enregistré',
      businessDate:
          first['business_occurred_at']?.toString() ??
          originalBusinessDate ??
          'Non renseignée',
      recordedDate: first['applied_at']?.toString() ?? 'Non renseignée',
      receivedDate: first['received_at']?.toString(),
      details: details.join(' • '),
      reason: reasons.isEmpty ? null : reasons.join(' • '),
      original: original,
      compensation: compensation,
    );
  }).toList();
}

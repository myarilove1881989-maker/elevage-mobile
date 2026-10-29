import 'api_service.dart';

/// Only fixed labels and status codes reach these screens; never response bodies.
String safeAccessError(Object error, String stage) {
  final status = error is ApiHttpException ? error.status : null;
  final reason = status == 401 ? 'Session expirée. Reconnectez-vous.'
    : status == 403 ? 'Votre compte ne peut pas effectuer cette action.'
    : status == 404 ? 'Service introuvable. Faites vérifier la compatibilité de l’application et du serveur.'
    : status == 400 || status == 409 ? 'Demande refusée. Actualisez les informations avant de réessayer.'
    : status != null ? 'Erreur du serveur. Réessayez plus tard.'
    : error is ApiConnectionException ? 'Connexion impossible. Vérifiez votre connexion.'
    : 'Réponse ou session incompatible. Reconnectez-vous puis réessayez.';
  return '$stage : $reason${status == null ? '' : ' (HTTP $status)'}';
}

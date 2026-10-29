import '../offline/foundation_api.dart';
import '../offline/outbox_transport.dart';

const unconfirmedOperationMessage =
    'Confirmation de l’opération indisponible. Vérifiez l’historique avant de réessayer.';

String operationStatus({required String transport, required String business}) {
  switch (business) {
    case 'CONFIRMED':
      return 'Confirmé par le serveur';
    case 'NEEDS_RECONCILIATION':
      return 'Cette opération nécessite une vérification';
    case 'NOT_APPLIED':
      return "Cette opération n'a pas été appliquée";
    case 'SUPERSEDED':
      return 'Opération remplacée — historique conservé';
  }
  switch (transport) {
    case 'SERVER_RECEIVED':
      return 'Reçue par le serveur — confirmation en attente';
    case 'IN_FLIGHT':
      return 'Transmission en cours';
    case 'TRANSPORT_BLOCKED':
      return 'Transmission bloquée : contactez le responsable';
    case 'LOCAL_PENDING':
    case 'RETRY_WAIT':
      return 'En attente de synchronisation';
    default:
      return 'État indisponible — données conservées';
  }
}

/// Allowlisted user-facing errors only. Never expose arbitrary exception text.
String tabletErrorMessage(Object error) {
  if (error is FoundationApiException) {
    final stage=error.operation==null?'':'${error.operation} : ';
    if (error.status == 401) {
      return '${stage}Connexion personnelle requise.';
    }
    if (error.status == 403) {
      return '${stage}Cette action n’est pas autorisée.';
    }
    if (error.status == 503) {
      return '${stage}La préparation hors ligne est indisponible sur le serveur.';
    }
    final reason=error.status==404?'Service introuvable. Faites vérifier la compatibilité de l’application et du serveur.'
      : error.status==400 || error.status==409?'Demande refusée. Actualisez les informations avant de réessayer.'
      :'Erreur du serveur. Réessayez plus tard.';
    return error.status>=500 ? '$stage$reason' : '$stage$reason (HTTP ${error.status})';
  }
  if (error is DeviceTransportException) {
    return error.status == 403
        ? 'Cette tablette ne peut plus transmettre normalement.'
        : 'Connexion indisponible : vos données sont conservées';
  }
  if(error is ArgumentError && error.message=='Le PIN doit contenir 6 à 12 chiffres.') return 'Le PIN doit contenir 6 à 12 chiffres.';
  if (error is StateError) {
    final text = error.message.toString();
    if (text == 'Profil verrouillé ou permission refusée.' ||
        text == 'Profil verrouillé ou permission refusée pendant la déclaration.') {
      return 'Cette saisie exige un profil ouvert et le droit correspondant. Vérifiez votre PIN et vos permissions auprès du propriétaire.';
    }
    const safe = {
      'La vente n’est pas autorisée avec vos permissions actuelles. Reconnectez votre compte ou contactez le propriétaire.',
      'Autorisation hors ligne invalide ou expirée.',
      'Stock historique à vérifier : actualisez avec Internet après la synchronisation.',
      'Actualisation du stock différée : attendez les confirmations de synchronisation, puis réessayez.',
      'Le stock a changé pendant la validation. Rouvrez la vente et vérifiez le stock actualisé.',
      'PIN incorrect ou temporairement bloqué.',
      'Autorisation expirée : connexion requise.',
      'Ce compte appartient à une autre exploitation.',
      'Cette tablette est préparée pour une autre exploitation.',
      'Cette préparation appartient à une autre installation.',
      'Tablette non préparée.',
      'La préparation de cette exploitation doit être activée par son propriétaire.',
      'Activation hors ligne non confirmée.',
      'Tablette principale requise.',
      'Cette tablette n’est pas la tablette principale.',
      'Ce profil exige un renouvellement V2 explicite.',
      'Profil personnel ouvert requis.',
      'Déverrouiller un profil personnel.',
      'Le profil a été verrouillé. Rouvrez votre PIN.',
      'Le profil a été verrouillé pendant la lecture.',
      'La tablette a été verrouillée.',
      'La préparation de tablette doit être actualisée par le propriétaire.',
      'Préparer la tablette et connecter un opérateur personnel.',
      'Tablette principale active requise.',
      'Une autre tablette est principale. Son remplacement doit être décidé explicitement.',
      'Tablette révoquée : récupération explicite requise.',
      'Tablette révoquée : récupération par le propriétaire requise.',
      'Cette tablette ne peut plus créer de déclaration.',
      'Un motif explicite est requis.',
      'La récupération concerne uniquement une tablette révoquée.',
      'Une récupération est déjà en cours.',
      'Le chargement est déjà en cours.',
      'Une opération de sécurité est déjà en cours.',
      'Un PIN existe déjà : utiliser le changement de PIN.',
      'Ce profil ne correspond pas à cette tablette et exploitation.',
    };
    if (safe.contains(text)) {
      return text;
    }
  }
  return 'Action indisponible. Les données déjà enregistrées restent conservées.';
}

# Pisciculture 3D — écrans V2 finances et agenda

Base 3C 67e351231df7afbba83ba74707f67f69d3b81153. Navigation principale et sélecteur Élevage/Pisciculture conservés. Nouveaux onglets de l'espace piscicole : Finances et Agenda, composant finance_agenda_panel.dart.

Finances : Synthèse, Dépenses, Recettes et paiements, Coûts communs. Montants serveur en chaînes décimales et monnaie existante, aucune somme Flutter en double. Période, espèce/cohorte/installation explicites. Factures et encaissements distingués, ancienne facture payée dans la période identifiée. Résultat indicatif avec limites visibles ; coûts communs non répartis, coûts exploitation exclus. Catégories réutilisées, propriétaire peut créer un libellé libre. Nouvelle dépense = modèle financier existant, aucun achat/stock automatique. Achat alimentaire existant : attribution seule, correction économique dans son parcours d'origine.

Agenda : Mes tâches, Ajouter une tâche, Tâches terminées, Rappels. Titre/type/date, heure facultative réellement choisie, site/cohorte/description facultatifs. Statut déclaré avec motif/compte rendu, annulation et réouverture réservées propriétaire. Heure inconnue conservée, rappel désactivé par défaut et nécessitant sa propre date/heure. Rappels visibles dans l'application uniquement ; aucune notification OS/push et aucun changement de synchronisation.

Marquer une tâche terminée ne lance aucun acte métier. Une section facultative propose de sélectionner un fait déjà enregistré (eau, pesée, aliment, sanitaire, reproduction, éclosion ou récolte). Aucun UUID de fait inventé ou présélectionné. Les contrôles de périmètre et de type restent serveur. Le module d'origine réalise l'opération réelle.

Depuis fiche cohorte/installation : contexte prérempli seulement si fiable. Une cohorte ayant plusieurs positions ne reçoit pas arbitrairement le premier site. Le détail permet d'ouvrir Finances ou Planifier, sans modifier les écrans de stock/santé/vente précédents.

Dialogues V2 rose pâle, champs blancs et bordure bleue, icônes vertes, défilement et disposition adaptative. Tests 360/1080 pixels, texte ×1/×2 sur six formulaires, jusqu'à l'enregistrement réel à 360/×2. Captures synthétiques sur D: ; la galerie externe précise leur périmètre widget.

API /api/pisciculture/v1/, contrat détaillé backend/PISCICULTURE-PHASE3D.md. Capabilities.finance_write ajoute le droit dépenses existant, séparé des droits aquatiques. Lecture refusée : anciennes données privées effacées. Réponses périmées et changement de session ignorés. Réseau incertain : UUID et corps gelés, réessai identique seulement par la même session/auteur ; si fermé avant confirmation, vérifier l'historique avant nouvelle saisie. Pas de nouvelle persistance ni d'outbox.

Aucun changement Android, PIN/clés, dépendances, notifications, transport offline, /telecharger ou /android-version.json. Tests via outils/SDK/pub-cache D: existants, --no-pub ; aucun APK, build Web ou publication. Limites : recette widget synthétique, volume >10 000 demande un filtre plus ciblé, pas de test physique ou serveur distant. Rapports phase3d externes : résultats réellement exécutés et risques résiduels. Attendre validation avant publication.

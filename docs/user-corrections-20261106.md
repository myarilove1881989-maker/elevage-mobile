# Correctifs utilisateurs Web — 6 novembre 2026

## Changements
- Informations techniques des historiques Aliments/Vaccins derrière une icône accessible ; Accueil sur les écrans de consommables.
- Après confirmation, mouvements et achats restent ouverts pour une saisie suivante ; les dépenses directes proposent une nouvelle dépense ; les refus et résultats incertains conservent le formulaire.
- Composant monétaire réutilisable : milliers et séparateur local, curseur conservé, aucune troncature des décimales invalides. Valeur canonique distincte de l’affichage.
- Responsable sanitaire existant ou contact ajouté immédiatement, multidates sans heure obligatoire, aucun droit de connexion créé au contact.
- Préremplissage prudent du prix d’origine pour mortalité/don/vol ; édition manuelle conservée, origine ambiguë signalée.
- Relance d’une facture impayée : données de vente et devise configurée, texte modifiable, copie et ouverture manuelle SMS/WhatsApp uniquement.
- Renouvellement JWT unique pour plusieurs 401, une seule répétition après refus d’authentification avec corps identique ; jamais après délai dépassé. Changement de compte protégé ; coupure réseau ne déconnecte pas. Récupération temporaire en mémoire des champs de brouillon pour le même compte après expiration réelle, sans renvoi automatique ; références à sélectionner à nouveau.

## Vérifications
- 54 tests Flutter ciblés réussis puis série finale de 106 tests réussis (séries avec recouvrement).
- Série finale : 66 contrôles visuels, 22 familles × 360/768/1440 px, historique, formulaires, session et changements de compte.
- 45 tests Chrome réussis, API simulée et accès externes bloqués : responsables multidates, achats aliments/vaccins, refus 400/403/500, erreurs et validations, ventes, naissances, flux animaux et largeur étroite.
- Construction Web release réussie avec SDK épinglé et API production ; aucun APK construit.
- Analyse : aucune erreur ni avertissement ; 125 remarques de style/dépréciation restent présentes. Il ne s’agit pas d’un contrôle d’analyse intégralement vert.

## Deux anciens échecs
Le test de réponses HTTP 401 simultanées passe avec ses assertions conservées. Le scénario hors ligne utilisait une mise à jour de statut TASK désormais prise en charge ; il représente maintenant l’édition du titre d’une tâche, réellement réservée au réseau, avec les mêmes assertions (succès réseau, refus hors ligne, aucune file trompeuse). Les autres tests de statut et de permissions demeurent actifs. La série hors ligne dédiée a également exécuté tous ses scénarios avec succès ; sa commande globale avait un unique échec du test visuel tablette, corrigé et validé ensuite.

## État de publication
Candidat construit localement ; aucune nouvelle publication à ce stade. La création des contacts sanitaires exige le backend correspondant et sa migration additive 0050, soumis à une sauvegarde de production vérifiée avant mise en ligne. Les anciennes API ignorent les champs additionnels. Version Web de retour : e735f051af607347bb0edbd1e95ab95730eccd5f. Ne pas considérer les achats réels résolus avant validation utilisateur.
Auto-déploiement reste désactivé. Android 118 et les formats signés hors ligne restent inchangés. Aucun achat ni message envoyé en production.

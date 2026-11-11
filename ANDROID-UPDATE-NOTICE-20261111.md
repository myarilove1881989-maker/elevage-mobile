# Notification Android — préparation du 11 novembre 2026

## État public vérifié

Page officielle : https://elevage-mobile.onrender.com/telecharger

La version 1.0.5 / build 118, package `com.elevage.app`, est déjà téléchargeable. La 117 reste en archive. Les deux téléchargements ont été refaits et leurs empreintes contrôlées le 11 novembre 2026. La release GitHub 118 reste une préversion intitulée « version de test ». La page actuelle ne reprend plus cet avertissement : cet écart doit être résolu avant une diffusion générale.

118 : `ElevAge-1.0.5-118-production.apk`, 29 092 086 octets ; SHA-256 `6fadfbdd977bd8bf967d0cc4d8759943b0862713777e9aeab9b4dcc0e7a9e61a`.

117 : SHA-256 `4e8e25acf45c2b6bf49f092c1a95c78f02e720c6a58f523c40718209e608cd5d`.

Les signatures des APK publics sont vérifiées ; certificat commun SHA-256 `999dd8507273df8f1c06a4731d1528e01be1e13b9ca48f438cd74347b4ffe774`. L’APK 118 conserve la signature v2 et minSdk 24. Son source de construction historique est `2080a42cb47d604531e74f2e57c978f993bd9f7a` ; les numéros passés au build priment sur le pubspec historique.

## Bootstrap et stratégie

Les sources de la 117 officielle (`e50b9d980aca436f509b25860ababd1434ca1136`) et de la 118 publiée ne contiennent pas de lecteur de manifeste de version ni de notification de mise à jour au démarrage. Les notifications locales existantes concernent les rappels : elles ne constituent pas un canal distant d’annonce de nouvelle APK. Aucun mécanisme distant existant n’a été identifié permettant d’ajouter cette interface à la 117 inchangée.

1. Conserver l’APK 118 public et son empreinte. Ne pas remplacer ses octets sous le même nom ou numéro.
2. Pour passer de 117 à 118, communiquer la page officielle par un moyen déjà accessible : accompagnement direct, lien partagé par le propriétaire ou canal de communication existant. Aucun message n’est envoyé par cette mission.
3. Intégrer ce changement dans une prochaine APK portant un build strictement supérieur à 118, par exemple 119 après décision de version. Une installation initiale accompagnée reste nécessaire. Cette nouvelle APK pourra annoncer les publications ultérieures ; avec le manifeste actuel 118, elle restera silencieuse.
4. Qualifier les données hors ligne, la signature et l’installation de ce nouveau binaire avant toute annonce générale. Présenter son empreinte et demander confirmation avant publication.

## Changement préparé

Branche isolée `feature/android-update-notice-20261111`, basée sur la branche de qualification 118 au commit `200a602`. Aucun numéro de version changé et aucune nouvelle APK 118 produite.

Le canal natif lit le build de l’APK réellement installé via PackageManager. Après le premier affichage, le widget consulte anonymement le manifeste HTTPS officiel, sans suivre les redirections. Il n’accède ni aux identifiants, ni aux bases, ni à l’outbox. Délai total de cinq secondes, réponse limitée à 16 Ko, erreurs silencieuses.

Seul un build entier strictement supérieur, publié, daté sans anticipation, correspondant au package et à la page officielle, produit l’annonce « Une mise à jour d’Élev’Age est disponible ». Le bouton « Télécharger la mise à jour » ouvre cette page dans le navigateur externe. « Plus tard » masque cette annonce pour le démarrage courant. Les mises à jour de ce mécanisme sont facultatives ; aucun mode obligatoire n’est activé.

Web et autres plateformes n’effectuent aucune requête de mise à jour. Les environnements laboratoire et pilote conservent leur affichage et ne démarrent pas ce contrôle. L’application reste utilisable pendant la requête et en cas d’échec du navigateur.

## Qualification et limites

SDK Flutter exact `5fc346839b5d0eef006ed8404392afb4dfae428d`, version 3.47.6 ; dépendances verrouillées conservées. Tests du service et de l’interface : six réussis, un test réservé à Web ignoré sur la machine native. Analyse des quatre nouveaux fichiers : aucune remarque. Les tests existants de connexion (quatre) et de sécurité réseau (huit) ont également réussi durant la première exécution ; ses trois échecs provenaient du dispositif de simulation de plateforme des nouveaux tests, corrigé ensuite.

La recette historique 117 → 118 confirme le remplacement sans désinstallation et le maintien de l’UID/répertoire. Elle ne qualifie pas le déchiffrement de tous les profils/PIN et la conservation exacte des opérations V2 en attente, ni leur reprise et synchronisation. Ces points restent bloquants pour une diffusion générale. Aucun appareil n’est connecté actuellement. Aucune installation nouvelle, aucun effacement et aucune écriture métier de test n’ont été effectués.

La compilation native et une ouverture réelle du navigateur sur Android restent à vérifier avec le prochain candidat. Les tests Flutter avec canal natif simulé ne remplacent pas cette qualification. Le binaire 118 signé public reste inchangé.

Contrôle Chrome final avec le lanceur du projet : trois tests réussis, deux cas réservés à Android ignorés. Le test Web simule aussi la plateforme Android et vérifie qu’aucun appel de recherche de version n’a lieu et qu’aucune annonce ne paraît. Le moteur graphique exact est servi localement et les requêtes externes sont bloquées par le lanceur. Après correction du cas numérique portable (118.5 est non entier sur toutes les plateformes), la relance native confirme encore six tests réussis et un cas Web ignoré.

La vérification des déploiements est consignée dans le rapport local. Aucune configuration ni aucun déploiement backend ou Web modifié par cette mission.

## Publication et retour arrière

Aucun changement du manifeste public, de la page officielle, des branches de production, de Render, des migrations ou de la base de production. Aucun envoi utilisateur. Une proposition locale rétablit l’avertissement de test de la page ; elle n’est pas publiée.

Pour le prochain candidat : désactiver l’annonce en conservant une version publiée inférieure ou égale, ou `published:false`, sans toucher aux données. Vérifier d’abord le binaire téléchargeable, puis seulement publier son manifeste après accord. Sur Android, corriger avec un build supérieur ; aucune désinstallation, rétrogradation ou restauration d’ancienne base. Une page restaurée n’annule pas les installations déjà faites.

## Revue autorisée

L’utilisateur a autorisé l’envoi public de cette branche et de son rapport pour revue uniquement, sans fusion ni déploiement. Les détails opérationnels de la vérification Render restent dans le rapport local. Aucune nouvelle APK ni annonce générale publiée.

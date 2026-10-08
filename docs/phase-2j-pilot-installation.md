# Phase 2J — installation PRITOM B10K / Android 15

Statut : préparation, installation non autorisée tant que les prérequis ne passent pas.

## Signature et versions

Le package client reste `com.elevage.app`. Le package debug est `com.elevage.app.offlinevalidation` : il ne démontre pas une mise à jour du package client. Version préparée : 1.0.0+103, supérieure aux versions 1 et 101/102 connues ; relever néanmoins le versionCode réellement installé et augmenter 103 si nécessaire. Ne jamais utiliser `-d` pour forcer un downgrade.

Le release exige ELEVAGE_KEYSTORE_PATH, ELEVAGE_KEYSTORE_PASSWORD, ELEVAGE_KEY_ALIAS, ELEVAGE_KEY_PASSWORD injectés par un coffre dans le processus de build. Aucune valeur dans le dépôt, les commandes journalisées ou les rapports. Keystore obligatoirement hors dépôt. La CI générale ne reçoit aucun secret et vérifie que le release refuse leur absence. Aucun APK pilote n’y est publié.

Décision en attente : clé existante et gardien, ou création après désignation du gardien et de deux copies chiffrées vérifiées dans des lieux distincts. Garder les mots de passe séparément. Utiliser une validité d’au moins 25 ans. Noter uniquement alias non sensible, empreinte SHA256 du certificat, dates et inventaire des copies ; vérifier une récupération depuis le coffre avant livraison. Ne pas remplacer une clé déjà utilisée sans procédure compatible démontrée.

Avant build : fixer explicitement API_URL sur une cible pilote HTTPS vérifiée et isolée de la production. Choisir les ABI à partir de `ro.product.cpu.abilist` ; ne pas supposer arm64 sur B10K. Après build : `apksigner verify --verbose --print-certs`, relever empreinte, package, versionCode, ABI, SHA256 de l’APK et SHA du source. Comparer aux métadonnées approuvées et refuser toute clé debug, APK debuggable, package inattendu ou URL production.

## Checklist ADB — dès disponibilité physique

1. Finir le premier démarrage. Activer options développeur et débogage USB ; accepter personnellement l’empreinte RSA du poste. Aucun reset de la tablette.
2. `adb devices -l` ; désigner le numéro de série, puis toujours utiliser `adb -s SERIAL`. Relever modèle, Android, SDK, ABI avec `shell getprop`. Android 15 attendu : API35, à vérifier.
3. Relever `shell settings get global auto_time`, `auto_time_zone`, `shell date +%s`, `persist.sys.timezone`. Comparer UTC tablette, poste synchronisé et serveur pilote ; conserver deltas et aller-retour réseau. Refaire après redémarrage et reconnexion. Aucun élargissement des contrôles temporels pour faire passer un test.
4. `shell pm path com.elevage.app` et `shell dumpsys package com.elevage.app`. Si présent, récupérer l’APK installé (`adb pull` du chemin retourné), vérifier son certificat et versionCode. Certificat incompatible : STOP, aucune désinstallation. Une copie de la base chiffrée seule ne sauvegarde pas les clés Keystore ; `adb backup` n’est pas une garantie sur Android15.
5. Sur application existante : inventaire avant mise à jour des exploitations, UUID/ordre/auteurs des originaux et états en attente, montants/quantités et clés publiques de dispositif, sans PIN/JWT ni données sensibles dans les logs. Si sauvegarde récupérable impossible et données réelles présentes : bloquer la mise à jour jusqu’à stratégie validée.
6. Après prérequis et accord d’installation : `adb -s SERIAL install --no-streaming -r CHEMIN_APK`. Première installation possible avec cette même commande. Aucun `uninstall`, `pm clear`, `run-as` destructif, `-d`, root ou effacement de stockage. Refus de signature ou version : conserver l’application et diagnostiquer.
7. Relever certificat/version après installation, ouvrir et confirmer le même inventaire. Si échec : arrêter les écritures, préserver l’app, la base et le Keystore ; corriger via un APK du même signataire avec version supérieure, jamais par désinstallation.

## Tests physiques réservés — données fictives seulement

- Keystore P-256 : génération, signature/challenge, persistance après arrêt et redémarrage, impossibilité d’export de la clé privée ; preuve distincte de la clé de signature de l’APK et de la clé Ed25519 du serveur.
- Enrôlement OWNER/OPERATEUR, PIN et limites de tentatives, isolation profils/exploitations ; journal de preuve sans secrets.
- Horloge : dérive, expiration, recul/avance et redémarrage. Manipulations de temps seulement sur environnement pilote fictif, avec restauration des réglages et inventaire préservé.
- Offline : quatre jours contrôlés à distinguer de quatre jours réellement écoulés ; original immuable et UUID conservé, droits/génération/autorisation valides.
- Synchronisation : coupure avant réponse, réponse perdue après commit, reprise et idempotence ; stocks/encaissements/lettrages exacts sans double effet. Révocation : pas de nouvelles écritures, récupération OWNER motivée sans réactivation.
- Mise à jour réelle du package client : deux APK release avec même clé pérenne et versions croissantes, originaux en attente et PIN/Keystore conservés. Les tests API24 debug 2I ne remplacent pas ce contrôle.

Sources : https://developer.android.com/studio/publish/app-signing ; https://developer.android.com/studio/publish/versioning

# Phase 2K — installation pilote et garde de la signature

Le propriétaire du projet est le gardien final de la clé. Aucune clé de distribution n'a été créée dans le poste ou dans GitHub. Les certificats de la CI Android 15 portent « PHASE 2K TEST ONLY DO NOT DISTRIBUTE », expirent après deux jours, restent dans RUNNER_TEMP et ne sont jamais joints aux artefacts. Seules les empreintes publiques et les preuves synthétiques sont publiées. Ne pas installer ces APK de test sur une tablette contenant des déclarations.

## Signature durable avant livraison

1. Identifier d'abord un éventuel APK déjà installé et son certificat. Une clé différente empêche le remplacement sans perte : arrêter, conserver l'installation et rechercher sa clé. Ne jamais désinstaller pour résoudre ce refus.
2. Préparer avec le gardien deux emplacements chiffrés durables indépendants (coffre principal et sauvegarde indépendante), un mot de passe fort conservé séparément et une procédure d'accès de secours. Ne pas utiliser le dépôt, les journaux, les artefacts CI ou ce poste saturé comme sauvegarde.
3. Générer la clé seulement dans cet environnement durable. RSA au moins 3072 bits, validité au moins 25 ans. Utiliser les invites interactives de keytool ou les entrées protégées du coffre ; aucun mot de passe dans une ligne de commande, un fichier commité ou un rapport. Les quatre variables ELEVAGE sont injectées pour le processus de build depuis le coffre.
4. Vérifier une récupération indépendante de chaque copie : ouvrir le keystore restauré, vérifier alias et SHA-256 du certificat avec keytool, signer un APK synthétique et vérifier avec apksigner. Garder uniquement les preuves publiques, dates, empreintes et identifiants des copies. Cette récupération n'est pas encore exécutée.
5. Fixer explicitement API_URL sur le serveur pilote HTTPS isolé autorisé, confirmer sa liaison à une base synthétique et son certificat TLS. Le défaut de lib/config.dart est la production : il ne doit pas être utilisé pour les essais. La CI release utilise https://phase2k.synthetic.invalid/api, domaine volontairement inutilisable, sans service distant.
6. Compiler depuis le SHA validé avec Flutter 3.47.6, lockfile imposé, version 1.0.0+103 (ou valeur supérieure au code installé). Choisir les ABI après lecture de la tablette ; les builds de test couvrent arm64-v8a et x86_64, pas une preuve d'ABI B10K.
7. Vérifier : apksigner verify --verbose --print-certs, aapt dump badging, SHA-256 de l'APK, package com.elevage.app, version, minSDK24, targetSDK relevé, flags non-debuggable, URL pilote et certificat attendu. Conserver un manifeste public source→APK→certificat→URL. Aucun APK pilote de distribution n'est fourni par cette phase.

## Branchement Windows et relevé sans modification

ADB est disponible sur le poste ; la dernière lecture n'a trouvé qu'un émulateur, pas de B10K. Ne jamais utiliser ce numéro de série comme s'il s'agissait de la tablette. Android Studio possède un JDK moderne : utiliser son JBR ou JDK17 pour Gradle, pas le Java8 global.

- Terminer le premier démarrage ; activer options développeur/débogage USB. Utiliser un câble de données et accepter personnellement l'empreinte RSA affichée par la tablette.
- Dans PowerShell : `adb devices -l`. Si aucune tablette : vérifier câble/port/Gestionnaire de périphériques et pilote OEM/ADB adapté. Ne pas télécharger un pilote d'un site non officiel. Une entrée « unauthorized » nécessite l'acceptation physique, pas une réinitialisation.
- Lancer `./tool/phase2k_device_inventory.ps1 -Serial NUMERO_TABLETTE`. Le script lit modèle, Android/API, ABI et horloge ; il n'installe rien et ne lit ni PIN, tokens ni base client. Android15/API35 reste à constater matériellement.
- Comparer UTC du poste synchronisé, tablette et serveur pilote ; noter latence et résolution à la seconde. Refaire après redémarrage/reconnexion. Ne pas élargir les règles temporelles pour faire passer un test.
- Si com.elevage.app existe, relever versionCode et signature via dumpsys/apksigner sur une copie de l'APK installé. La copie APK ne sauvegarde pas les données, le PIN ou le Keystore.

## Installation et remplacement sans perte

Après les prérequis ci-dessus et un verdict pilote GO, utiliser exclusivement `adb -s NUMERO_TABLETTE install --no-streaming -r CHEMIN_APK`. Interdits : uninstall, pm clear, factory reset, root sur tablette, downgrade forcé -d ou effacement de stockage. Un refus de certificat ou de version impose un diagnostic en conservant l'application.

Avant et après : comparer exploitations/profils, UUID/auteurs/ordre des déclarations et états en attente, montants physiques reçus, clés publiques du dispositif et résultat de signature/challenge. Ne pas exposer les valeurs PIN/JWT. Une base chiffrée copiée sans ses clés Keystore n'est pas une sauvegarde récupérable. Si des données réelles existent et aucune récupération sûre n'est démontrée, différer l'installation.

## Recette physique obligatoire, données fictives

- P-256 Android Keystore : challenge serveur, signature, impossibilité d'export de la clé privée, persistance après arrêt/redémarrage. Distinguer clé de dispositif, clé APK et clé de signature serveur.
- Deux opérateurs PIN personnels, propriétaire, tablette partagée : mauvais PIN/limites, isolation de profils et exploitations, verrouillage, persistance et accès après mise à jour.
- Achat, vente, dépense, mortalité, vol, naissance, œufs, encaissement et agenda hors réseau ; original UUID/auteur/date/payload immuable et persistant.
- Coupure avant réception et réponse perdue après commit : reprise/idempotence, aucun double stock ou montant ; conflits conservés et réconciliés explicitement. Encaissement physique conservé même si affectation financière impossible.
- Autorisation expirée, recul/avance d'horloge, redémarrage et révocation appareil : serveur autorité finale, aucune nouvelle écriture interdite, récupération propriétaire motivée sans réactivation.
- Deux APK release du même certificat durable, codes croissants : remplacer avec des déclarations en attente et vérifier PIN, Keystore et inventaire inchangés. Le témoin de fichier privé sur émulateur API35 n'est pas une validation des déclarations/PIN sur B10K. Les scénarios de résilience API24 complètent ce contrôle sans le remplacer.
- Quatre jours réellement écoulés et quatre jours simulés doivent être rapportés séparément.

En cas d'incident, préserver APK/base/Keystore/originaux, arrêter les nouvelles écritures selon la procédure autorisée et corriger en avant avec le même signataire et un code supérieur. Aucun effacement automatique pour réparer.

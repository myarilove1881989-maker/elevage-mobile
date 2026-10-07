# Élev’Age — Android, phase 1

Même projet Flutter que le Web. Branche `feature/android-app`, basée sur le master
`0e590db1f828652dd1c952890a726a4ccb4fd6eb`. Aucun déploiement Render, changement
backend ou migration de base de données n’est nécessaire pour installer cette APK.

## Application de test

- Nom : **Élev’Age** ; identifiant : `com.elevage.app`.
- Version : `1.0.0+1` ; Android 7.0 / API 24 minimum.
- API HTTPS : `https://backend-elevage.onrender.com/api`.
- Application connectée : aucune base métier locale et aucune synchronisation hors ligne.
- Android conserve le JWT dans `flutter_secure_storage` ; un ancien JWT présent
  dans les préférences est migré après une écriture chiffrée réussie. Le Web
  conserve ses préférences existantes.
- Un 401 efface la session et ferme les routes protégées. Pas de renouvellement
  automatique de jeton ni de nouvelle tentative automatique d’une écriture.
- Les factures Android disposent d’un aperçu, de l’impression et du partage via
  `printing`. Les polices Roboto embarquées couvrent les accents et « Œufs ».
- Les notifications sont facultatives ; les rappels utilisent une planification
  non exacte, sans réclamer la permission spéciale des alarmes exactes.

## Reproduire les vérifications

Outils validés : Flutter **3.47.6** / Dart **3.13.5**, JDK **17** complet, Android
SDK `platforms;android-34`, `platforms;android-35`, `platforms;android-36`, `build-tools;35.0.0`, `build-tools;36.0.0`, `platform-tools` et NDK
`28.2.13676358`, et CMake `3.22.1`. Utiliser un JDK contenant `javac`, pas seulement un JRE.
Le projet conserve AGP 8.11.1, Gradle 8.14 et Kotlin 2.2.20 ; Flutter affiche un
avertissement de prise en charge future pour ces versions. Leur mise à niveau
doit être validée avant publication définitive.

```sh
flutter pub get --enforce-lockfile
flutter test
flutter analyze --no-fatal-infos
flutter build web --release --dart-define=API_URL=https://backend-elevage.onrender.com/api
flutter build apk --debug --dart-define=API_URL=https://backend-elevage.onrender.com/api
flutter build apk --release --dart-define=API_URL=https://backend-elevage.onrender.com/api
```

Seules les informations de lint sont non bloquantes ; les erreurs et avertissements restent bloquants.
L’analyse ne présente pas d’erreur ni d’avertissement ; les informations de
lint restantes sont recensées dans le rapport de livraison. Les APK sont dans
`build/app/outputs/flutter-apk/`. La définition de l’API est commune au Web et
à Android. Un build release refuse une API HTTP ou une adresse de boucle locale.

## Signature

Cette APK release est **une version de test signée par la clé debug** prévue
dans le projet. Elle peut être installée manuellement ; ce n’est pas une
publication Play Store. Aucune clé privée définitive n’a été créée. Les clés,
`key.properties`, `build/` et `.dart_tool/` sont exclus du dépôt.

Avant publication définitive, le propriétaire doit choisir et conserver une
clé d’upload privée pérenne, organiser sa sauvegarde, créer son `key.properties`
hors Git et remplacer la configuration debug du build release par cette
configuration privée. Ne jamais publier les mots de passe ni les fichiers de
clé. Vérifier la signature et la mise à jour d’une version installée avant
distribution. Une clé debug différente ne permettra pas une mise à jour en
place de cette APK ; les données métier sont conservées sur le serveur.

## Installer et tester sur téléphone

1. Télécharger l’APK release fournie, l’ouvrir et autoriser temporairement
   l’installation depuis ce navigateur ou gestionnaire de fichiers si Android
   le demande. Installer Élev’Age et révoquer ensuite cette permission.
2. Garder Internet activé, ouvrir l’application et se connecter avec son compte.
   Vérifier le tableau de bord, le menu, les paramètres et le suivi de production.
3. Fermer complètement puis rouvrir l’application : la session doit être reprise
   si le jeton est encore valable. Quitter : la connexion doit réapparaître.
4. Sur un compte de test jetable uniquement, vérifier achats, dépenses,
   mouvements, CHAIR, collecte/stock/KPI/FIFO OEUFS et naissance en lot séparé.
   Ne pas créer de fausses ventes ou naissances dans un compte réel.
5. Ouvrir une facture FR puis EN, animaux puis œufs, paiement total puis partiel.
   Vérifier les accents, partager le PDF et lancer l’impression si une imprimante
   compatible est disponible. Une imprimante n’est pas requise pour le partage.
6. Couper Internet : une erreur doit être visible ; l’application ne doit pas
   annoncer un enregistrement réussi. Rétablir Internet et actualiser. Après un
   délai dépassé sur une écriture, vérifier l’historique avant de soumettre à
   nouveau : le serveur peut avoir reçu la première requête.

Les tests de widgets et des actions PDF utilisent des plateformes simulées.
Aucun téléphone ni émulateur Android n’était disponible lors de cette phase :
installation, Keystore réel, rendu natif, imprimante et applications de partage
doivent encore être essayés sur l’appareil. Aucun AAB, compte Play Store, module
piscicole ou mode hors ligne n’a été créé.

# Mission offline autonome — journal

## État initial, 7 octobre 2026

- Backend 2B.1 : `c3c5ff455ac01be61fd6992d1310368a34d0b0a2`.
- Web master : `0e590db1f828652dd1c952890a726a4ccb4fd6eb`.
- Android : `9e11afb4ddd426d8fd5b6d9e81ed797535d1b195`, contient master.
- Branche de travail : `feature/offline-phase-2c`.
- Aucun merge, déploiement ou accès PostgreSQL production.

## Préparation 2C — EN COURS, non validée

La validation doit utiliser Flutter 3.47.6 / Dart 3.13.5. Le SDK Windows
installé est 3.41.6 / 3.11.4. Dart ne peut pas canonicaliser les chemins
dans cet environnement (erreur Windows 5), même après copie du SDK dans
le workspace. La CI de branche vérifie la version demandée, les tests,
le Web et les APK. Elle ne déploie aucun service.

L'APK release utilise actuellement la signature debug prévue par le projet :
**PILOTE / TEST**, non prêt pour le Play Store.

Le backend accepte P-256 avec signature DER SHA256withECDSA pour
Android Keystore API 24, en complément d'Ed25519. La clé privée ne doit
jamais sortir du Keystore.

Le chiffrement Drift utilise sqlite3 3.7.0 et sqlite3mc avec Drift 2.35.1.
L'ouverture refuse le stockage si le moteur chiffrant n'est pas disponible.
Le checkpoint `6e64d9c7bcb5db309948a4299beb8b0b4223a92f` passe le lockfile
strict, l'analyse, la suite Flutter, la preuve de fichier illisible avec
SQLite Python standard, le Web release et les APK debug/ARM64 release.
L'exécution Android API 24 est encore en cours, donc 2C reste non validée.

La préparation utilise une connexion HTTP personnelle distincte de la
session historique. Les PIN, JWT, grants et clés sont dans le coffre
Android ; le cache partagé chiffré contient seulement les données métier
confirmées et les métadonnées des profils. Les pages serveur sont limitées
à 200 éléments, puis promues après réception complète d'une collection.
L'agenda local filtre les tâches de l'opérateur et les tâches générales.
Le schéma local 1 vers 2 ajoute une table de chargement sans supprimer
le cache existant ; cette migration est couverte par un test.

Le test d'intégration utilise les vrais Keystore, coffre, base chiffrée et
PIN sur Android, avec HTTP synthétique. La fermeture/réouverture de la
base dans ce test ne constitue pas encore une preuve de redémarrage
complet du processus. Une signature produite par Android doit également
être soumise au backend PostgreSQL local avant clôture de la validation.

Références :
- https://drift.simonbinder.eu/platforms/encryption/
- https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec

## Portes de progression

La première CI a réellement installé Flutter 3.47.6 et résolu le lockfile.
L'analyse du code initial retourne 56 diagnostics de niveau `info`, sans
erreur ni warning. Ils restent visibles dans les logs ; l'analyse bloque
toujours les erreurs et warnings, mais pas ces conseils existants.

2D ne commence qu'après validation complète de 2C. Les phases suivantes
et tout déploiement restent soumis aux portes de la mission. Les politiques
offline des exploitations existantes restent désactivées.

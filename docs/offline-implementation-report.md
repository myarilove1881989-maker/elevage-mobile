# Mission offline autonome — journal

## État initial, 7 octobre 2026

- Backend 2B.1 : `c3c5ff455ac01be61fd6992d1310368a34d0b0a2`.
- Web master : `0e590db1f828652dd1c952890a726a4ccb4fd6eb`.
- Android : `9e11afb4ddd426d8fd5b6d9e81ed797535d1b195`, contient master.
- Branche de travail : `feature/offline-phase-2c`.
- Aucun merge, déploiement ou accès PostgreSQL production.

## Phase 2C — VALIDÉE, socle Android

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

Le checkpoint `00f4e9de5b5fe6d00cce2dd05c5b4a0baf5c5214` passe 126 tests,
le lockfile strict, l'analyse (56 infos antérieures, aucune erreur ni
warning), le Web et les APK. La relance précédente a installé et exécuté
la fixture native API 24, puis révélé un contrôleur de champ PIN libéré
avant la fin de la transition de fermeture. Le contrôleur appartient
désormais à l'état du dialogue et est libéré à son démontage. La suite
native complète est relancée ; cet échec reste conservé dans les preuves.

Le parcours Flutter Android API 24 passe après cette correction. L'étape
JUnit suivante révèle un conflit de résolution cohérente : le graphe
debug reçoit runner 1.3.0 via le plugin Flutter tandis que le test demande
1.7.0. Les dépendances de test maintenues sont maintenant déclarées aussi
dans le graphe debug pour aligner les deux configurations, sans modifier
le graphe release ni désactiver les contrôles de résolution.

La compilation instrumentation a ensuite lancé les tâches de tous les
plugins, dont une suite tierce déclarant minSdk 16. La commande cible
désormais explicitement les APK et tests de `:app`, avec toutes leurs
dépendances, pour exécuter notre test Keystore sur API 24. Aucun manifeste
n'est forcé avec overrideLibrary et aucune assertion n'est supprimée.

Le premier job API 24 a atteint 45 minutes : la compilation de l'APK
avait réussi en 275,8 secondes, puis son installation est restée bloquée.
Les assertions Android n'ont donc pas été exécutées. Le même APK s'est
installé sur l'émulateur local API 36 en quelques secondes avec l'option
ADB officielle `--no-streaming`. La relance API 24 utilise cette option,
puis le pilote Flutter officiel `--use-existing-app`; les SDK locaux ne
sont pas modifiés. `--keep-app-running` évite la désinstallation de la
fixture avant les preuves de chiffrement et les assertions natives.

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

Clôture du socle 2C, 7 octobre 2026 : checkpoint code
`9e5937846340e09e51c3c287b5de576e0bb02867`, workflow `37613201556`,
jobs Flutter et Android tous deux réussis. Flutter 3.47.6 / Dart 3.13.5 :
126 tests, lockfile strict, aucune erreur ni warning d'analyse (56 infos
initiales conservées), Web release, APK debug et ARM64 release réussis.
API 24 x86_64 : vrai parcours Jean/Paul, PIN et coffre Android, cache
chiffré partagé, puis test Keystore réussi dans deux processus.
Le fichier Android extrait refuse une lecture SQLite Python standard,
également vérifiée après téléchargement de l'artefact. SHA256 ZIP :
`1e4412926219d0cd9f04988e9f0c6ab5e6a526cd44272e13092fad39e3d23f40`.
Le script trouve désormais le cache par son nom synthétique dans l'espace
de l'application isolée au lieu de supposer un dossier particulier.
La preuve publique native a aussi activé un appareil de test via Django
sur PostgreSQL local ; corps altéré et rejeu refusés, régression backend
183 tests réussie avec deux skips propres à SQLite.

Cette clôture valide le socle 2C, sans valider les phases 2D–2I.
Le redémarrage complet du parcours terrain avec commandes en attente,
les conflits métier et le déploiement restent des portes ultérieures.

La première CI a réellement installé Flutter 3.47.6 et résolu le lockfile.
L'analyse du code initial retourne 56 diagnostics de niveau `info`, sans
erreur ni warning. Ils restent visibles dans les logs ; l'analyse bloque
toujours les erreurs et warnings, mais pas ces conseils existants.

2D ne commence qu'après validation complète de 2C. Les phases suivantes
et tout déploiement restent soumis aux portes de la mission. Les politiques
offline des exploitations existantes restent désactivées.

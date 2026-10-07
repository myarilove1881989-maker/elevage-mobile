# Mission offline autonome — journal

## Phase 2E — extension des opérations terrain, EN COURS

Premier lot clients/tâches validé : source `e64ca3f056d4c46425defbd40139d867508f37e8`,
CI `37627927982`, 145 tests Flutter, Web/APK/API 24 et formulaire client
sans session Internet passent. Le serveur correspondant a passé 207 tests
SQLite (5 skips PG) et 207 tests PostgreSQL local (2 skips SQLite).

Extension : dépenses, alimentation, pesées, collectes, mortalité/don/vol,
achats et naissances disposent d'un formulaire personnel. Les montants sont
normalisés comme chaînes décimales ; le total d'achat utilise des entiers
BigInt, sans conversion flottante. Un constat supérieur au stock projeté
demande un motif et reste conservé. Recherche locale de lot bornée, y compris
au-delà de la première page. Les projections des lots provisoires et les
dépendances conservent leurs UUID ; parent de naissance et mort-nés ne
contribuent pas au stock enfant vivant.

Les reçus de stock confirment exploitation, lot et révision. Leur promotion
est atomique avec le reçu et les mappings. Un chargement antérieur ne peut
remplacer une révision plus récente, même si l'horloge locale diffère. Stock
confirmé, delta local et stock projeté sont affichés séparément. Les œufs
restent distincts des animaux ; aucune autorité FIFO locale n'est créée.

Tests projections/stock/restart et véritable formulaire achat API 24 en cours
de validation. La phase 2E complète reste non validée ; aucune phase 2F,
fusion, politique silencieuse ou production.

## Phase 2E — premier checkpoint, EN COURS

Clients et comptes rendus de tâches peuvent être saisis avec le PIN personnel,
sans réseau. La projection est calculée depuis la déclaration durable : aucun
état projeté ne peut précéder le commit de l'Outbox. La migration locale 3 vers
4 ajoute uniquement les correspondances UUID local/identifiant serveur et
préserve la file existante. Reçu et correspondance sont enregistrés dans une
même transaction ; une correspondance étrangère ou contradictoire est refusée.
Les tâches locales prévoient leur version suivante et une dépendance pour le
second compte rendu. Les données d'autres opérateurs restent filtrées.

Validation Flutter et native en cours. Ce checkpoint ne valide pas les autres
modules terrain et ne permet pas de commencer 2F. Aucun déploiement ni fusion.

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

## Phase 2D — VALIDÉE

Le schéma local 3 ajoute une Outbox chiffrée et un compteur de séquence.
Les déclarations originales sont protégées contre UPDATE/DELETE SQL ;
les états de transport et métier restent séparés. Le grant est référencé
par UUID, sans JWT. Projection et déclaration peuvent être enregistrées
dans une seule transaction. Les tentatives interrompues sont reprises
avec le même UUID, l'auteur d'origine et une temporisation persistante.
Le transport utilise une preuve appareil distincte des sessions JWT
personnelles, avec nonce, exploitation, génération, méthode, chemin et
empreinte exacte du corps. Un défi expiré est réessayable ; une tablette
révoquée conserve ses déclarations et bloque le transport normal.
Les tests Flutter et Android du checkpoint 2D doivent encore passer.
Les formulaires terrain 2E et les confirmations métier ne sont pas encore
implémentés. Aucun déploiement ni merge de production n'a lieu.

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
## Clôture 2D — 7 octobre 2026

Source mobile : `930f4462cd3c380a630c04e0a7d5d860e234ebef` ; serveur :
`eab29d096d3b72bad06fc1f36f415bd493553ccf`. Branches `feature/offline-phase-2d`,
PR brouillons mobile #9 et backend #7, sans fusion.

CI `37620191629` : Flutter, Web release, APK debug et ARM64 release passent.
L'analyse affiche 61 diagnostics info (56 antérieurs et 5 conseils d'accolades),
aucune erreur ni warning. Le lockfile strict reste obligatoire. Les tests
de file locale couvrent atomicité, UUID idempotent, séquence partagée,
reprise IN_FLIGHT, mauvaise attribution des reçus, réponse perdue et révocation.
API 24 réelle : parcours Jean/Paul avec deux déclarations d'auteurs distincts
retrouvées à la réouverture, deux processus Keystore, preuve de fichier natif
chiffré illisible par SQLite ordinaire. La reprise complète du processus et
l'actualisation d'APK avec une file métier restent dans les scénarios 2I.

Serveur SQLite : 197 tests, 193 réussis et 4 spécifiques PostgreSQL ignorés.
PostgreSQL 17.11 temporaire local : 197 tests, 195 réussis et 2 spécifiques
SQLite ignorés. Migrations additives 0019/0020, trigger terrain UPDATE/DELETE
SQL refusés et réception simultanée du même UUID sans double effet validés.
La première exécution PostgreSQL a révélé deux erreurs de fixtures : retour
du test historique de migrations à 0018 et propriété SQLSTATE du mauvais
pilote. Corrigées, puis les deux suites complètes relancées avec succès.

Aucun formulaire métier 2E n'était inclus dans ce jalon. Aucun accès de test
à la production, merge, déploiement ou activation silencieuse de politique.

## Clôture 2E — 7 octobre 2026

Sources validées : backend `5e146d76de58658d7ec7fd95e196693389ce2b97`,
mobile `6aa7ab9179d3b3796bc8585e3ca0d97c193fb1b8`.
Clients, comptes rendus de tâches, dépenses, alimentation, pesées, collectes,
mortalités, dons, vols, achats et naissances sont inclus. Achats et enfants
ont un UUID de lot provisoire résolu dans la même exploitation. Les mort-nés
ne contribuent pas au stock et le lot parent reste inchangé.

SQLite : 217 tests, 211 réussis et 6 skips PostgreSQL. PostgreSQL 17.11
local isolé : 217 tests, 215 réussis et 2 skips SQLite, migrations jusqu'à
0022 et token_blacklist, check et makemigrations --check réussis. Les
retraits simultanés conservent deux déclarations, appliquent un seul retrait
et laissent un stock de 5. Le cluster de test est arrêté.

CI mobile `37635935971` : 160 tests réussis ; analyse sans erreur ni warning
(61 infos conservées), lockfile strict, Web release, APK debug et ARM64
release (28,4 MB). Android API 24 réelle : profils Jean/Paul et auteurs
préservés, formulaire client offline et achat de 3 à 13,01 donnant 39,03,
projection et réouverture de la file, Keystore dans deux processus et
preuve de fichier chiffré illisible par SQLite ordinaire. Les échanges HTTP
du parcours UI sont synthétiques ; le parcours métier natif avec backend
réel, redémarrage complet et mise à jour APK reste à valider en 2I.

Phase 2E validée ; ventes, FIFO et encaissements commencent ensuite en 2F.
PR backend #8 et mobile #10 restent en brouillon. Aucun merge, déploiement,
test de production ni activation de politique réelle.

## Phase 2F — ventes et encaissements, checkpoint EN COURS

Ventes animaux sous verrou de lot/exploitation, survente conservée à
rapprocher sans stock confirmé négatif. Ventes d'œufs via le service existant,
FIFO et AffectationMouvementOeufs avec la date/heure métier comme borne :
une collecte postérieure, même du même jour, est inéligible.

EncaissementTerrain distingue le montant physiquement reçu, le montant
lettré et le reliquat à rapprocher. Payment garde tout le montant reconnu ;
seule la vente explicitement visée est lettrée, sans allocation silencieuse
à d'autres dettes. 50 000 reçus pour 30 000 dus conserve 50 000, affecte
30 000 et signale 20 000. Auteur, date métier et déclaration restent tracés.
Migration 0023 : modèle reconnu et conversion Payment/Lettrage en Decimal,
précédée d'un contrôle refusant arrondi réel, dépassement ou montant non
fini. Cette évolution des anciens champs est nécessaire au lettrage exact ;
elle reste soumise à sauvegarde et contrôle des valeurs réelles avant toute
migration de production. Test de migration historique valide et refusée.

Mobile : schéma local 5 additif, ventes/projections et chaîne UUID
client → vente → encaissement. Reçus monétaires contrôlés et persistés,
montants en chaînes décimales/BigInt, affectation distincte du fait physique.
Formulaires et parcours natif supplémentaires en attente de CI.

Premières suites complètes : 229 tests sur chaque moteur, deux erreurs
identiques dans l'export Excel mélangeant Decimal et float ; calculs corrigés.
Les tests de concurrence PostgreSQL passent, dont deux ventes concurrentes
et deux encaissements sur une dette unique. Un premier appel SQLite depuis
le mauvais répertoire n'avait découvert aucun test : résultat non retenu,
relancé depuis le dépôt. Test de cache ajouté : erreur de chemin de fixture
corrigée, puis format de dette harmonisé à deux décimales. 21 tests ciblés
ventes/exports passent avec deux skips PG. Suites complètes corrigées et CI
mobile restent requises avant clôture 2F. Aucune production touchée.

### Vérifications supplémentaires 2F

Checkpoint serveur `edd5a4a6500bb71ebb45e585f042af4fff06ff8d` : suites
corrigées 230 SQLite (222 réussis, 8 skips PG) et 230 PostgreSQL (228 réussis,
2 skips SQLite), migrations et contrôles passent ; cluster local arrêté.
Le montant physique reconnu est désormais aussi protégé dans le modèle
et par le trigger PostgreSQL additif 0024 : UPDATE de l'origine ou DELETE
refusés, affectations évolutives conservées. Quinze tests ciblés passent
sous SQLite avec trois skips PG ; régression complète de cet ajout requise.

CI mobile initiale `37642626542` : analyse réussie, 166 tests réussis et un
échec de fixture. Le test supposait le mauvais ordre de listOutbox à la
réouverture ; il recherche désormais l'encaissement par son UUID et vérifie
toujours ses deux dépendances et l'auteur. Le parcours natif de ce run
reste en cours ; aucune porte 2F n'est considérée entièrement validée.

Le premier parcours natif 2F a aussi échoué : ensureVisible était suivi
immédiatement d'un clic alors que le bouton venait sous l'AppBar. Le test
centre le bouton, attend le défilement, puis vérifie l'ouverture du dialogue
avant de continuer. Les assertions métier et les avertissements de clic
manqué restent actifs. Relance CI intégrale requise.

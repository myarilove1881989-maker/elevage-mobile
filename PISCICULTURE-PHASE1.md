# Pisciculture — candidat Flutter local

Base Web : `e4cd64a4d421fdbc8a267aca093cd3330afb3ba5`. Référence Android 119 préservée : `074475fcfb09ed2d7772f0ac1959933a3d6cd541`. Aucun APK construit ou publié.

Le dashboard découvre les capacités `/pisciculture/v1/capabilities/`. Le propriétaire peut activer explicitement son espace ; l'opérateur ne le voit que si le serveur lui accorde la lecture. Le sélecteur pleine largeur partage Élevage/Pisciculture à 50/50 sous la barre commune. La barre conserve cinq opérations sur une seule ligne à 1080/1280/1440 CSS px ; en dessous ou à texte agrandi, le menu détaillé conserve les accès. Les parcours terrestres restent dans leur corps d'écran existant.

Le nouveau dossier `lib/pisciculture/` contient :

- service REST authentifié, pagination et enveloppes UUID ;
- sélecteur d'activité ;
- tableau de bord avec effectifs, cohortes/installations actives et répartitions ;
- listes et fiches d'installations/cohortes et historique ;
- formulaires de création/modification/désactivation, profil aquatique, stades et transferts ;
- assistant en quatre étapes, soumis atomiquement à sa confirmation finale.

Les cartes, décorations, scaffold et bandeaux sont ceux de V2. Les indicateurs des phases suivantes affichent Non disponible. Les captures de qualification sont des rendus des véritables widgets avec des données synthétiques, pas des vues de production.

Les nouvelles écritures sont en ligne uniquement. Aucun ajout à la grammaire des opérations signées, à l'outbox ou aux schémas locaux chiffrés. Les lectures piscicoles ne sont pas réinjectées dans le cache écran offline. Le runtime Android reprend la preuve de tablette principale existante pour les nouvelles requêtes en ligne lorsque la politique de la ferme l'exige. Les contrats de permissions fermés historiques restent inchangés ; les nouvelles capacités sont négociées séparément.

Un échec réseau ou une réponse serveur incertaine bloque une nouvelle saisie : vérifier le statut ou reprendre strictement les mêmes données et UUID. Les erreurs de version sont expliquées par le serveur ; actualiser avant une nouvelle confirmation. Une réponse tardive d'un ancien filtre ou d'un espace quitté ne peut pas réafficher ses données.

Tests locaux : `tools/dev.ps1 test -Tests test/aquatic_phase1_test.dart`, plus les suites existantes de navigation, accès unifié, PIN/profils, outbox, projections, alimentation, vaccins, authentification et factures. SDK Flutter 3.47.6 et lockfile conservés. Le dossier de livraison extérieur contient les journaux et captures.

Qualification Web de compilation réalisée sans publication ni ouverture de l'artefact sur des données réelles. La commande release existante compile une configuration de production : **cet artefact n'est pas une démonstration à connecter à la production et n'a pas été exécuté contre celle-ci**. Les essais fonctionnels utilisent API Django locale synthétique et widgets avec services simulés. Pas de recette navigateur de bout en bout sur serveur local TLS ni de recette matérielle Android ; cette limite doit être levée avant publication.

Cette phase est qualifiée en français. Les libellés piscicoles nouveaux n'ont pas encore de traduction anglaise complète ; les langues et parcours historiques n'ont pas été changés. L'attribution des droits aquatiques utilise l'administration/API existante, sans nouvel écran spécialisé de délégation. L'activation, les clés, PIN et autres données Android réelles n'ont jamais été manipulés pendant cette mission.

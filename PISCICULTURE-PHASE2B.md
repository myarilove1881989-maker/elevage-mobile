# Pisciculture phase 2B — Flutter V2 local

Base : 17ad98265bf570e6e4b99ec048e0653e306467d9.
Branche feature/pisciculture-phase2b-20261112, même copie D: que la phase 2A.

Nouvel onglet Pertes et inventaires dans l’espace piscicole :
- mortalité confirmée attribuée ou inconnue ; suspicion explicite sans débit ;
- pertes/corrections en attente et réserves par cohorte ;
- rapprochement partiel des seules cohortes éligibles ;
- inventaire réel avec révision de référence ;
- crédit positif séparé et affectation à une cohorte ouverte existante ;
- historique et annulation compensatoire motivée.

Les boutons sensibles suivent le statut OWNER ; l’API reste l’autorité et
refuse les délégations de rapprochement/inventaire/compensation à un opérateur.
Seule la saisie de mortalité/suspicion a une permission aquatique déléguable.
Aucun nouveau droit dans le contrat signé offline.

Tous les formulaires exigent date avec fuseau et motif ; nombres entiers.
Une réponse incertaine conserve exactement UUID/payload/path et bloque les
modifications jusqu’au réessai. Aucune déclaration n’entre dans l’outbox.
Les lectures ignorent les réponses tardives après fermeture/changement de
session et effacent les anciennes données en cas d’échec.

Les effectifs non rapprochés affichent le brut et une plage conservatrice.
Les anciennes biomasses restent historiques ; un avertissement signale un
effectif actuel incertain ou une référence modifiée, sans écraser l’observation.
Le composant KPI partagé terrestre reste inchangé.

Lanceur tools/test_phase2b.ps1 : SDK et cache existants sur D:, profil d’outil
et temporaires contrôlables sur D:, captures dans phase2b/captures.
Aucun navigateur, build Web ou APK. Tests --no-pub avec configuration de
dépendances existante, sans recréer les liens bureau incompatibles exFAT.
Les fichiers de preuve de phase 2A restent dans leurs dossiers d’origine.

Voir le rapport parent phase2b/RAPPORT-PHASE2B.md pour les résultats exacts et
les limites. Android 119, PIN, outbox, profils/appareils, clés,
pubspec/lockfile et routes de téléchargement restent hors diff.

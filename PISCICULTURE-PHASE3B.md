# Pisciculture phase 3B — Flutter V2 local

Base 7b433d3818a7b8356bd9f155f3226c5abf2933a6. Branche feature/pisciculture-phase3b-20261113, même copie isolée sur D:.

Nouvel espace Reproduction dans la navigation piscicole, sans changer la barre principale, le sélecteur Élevage/Pisciculture ni les écrans terrestres. Quatre actions : Mes géniteurs, Nouvelle reproduction, Enregistrer une éclosion, Mettre les alevins en élevage. Ponte/incubation accessibles dans le détail de reproduction ; pas d’étapes biologiques obligatoires ni protocole par défaut.

Géniteurs : groupe descriptif relié à espèce, bassin et cohorte d’origine si connue ; aucune entrée/réserve de poissons. Mâles/femelles facultatifs, champs vides -> null, zéro explicite conservé. Détails repliables maintenus dans le formulaire pour que leur validation reste active après repli. Depuis fiche bassin/cohorte : contexte fiable prérempli, pas de premier bassin arbitraire lorsque la cohorte en occupe plusieurs.

Éclosion/ponte/incubation : qualité Inconnu/Estimé/Compté explicitement choisie, quantité entière ou null selon qualité. Aucun alevin déduit des œufs, aucune éclosion ajoutée au vivant. Histogrammes/taux biologiques non inventés.

Mise en élevage : source d’éclosion, effectif réel, destination et nouvelle cohorte ; total confirmé, déjà affecté et disponible affichés indépendamment du vivant actuel. Estimation/quantité inconnue : total réellement compté et justification à saisir, jamais préremplis depuis l’estimation. Confirmation explicite obligatoire. Comptage seul : total incluant les quantités déjà affectées, sans nouvelle entrée dans le vivant. Nom de cohorte lisible prérempli, code technique généré stable et modifiable dans les détails ; stade facultatif, aucun choix biologique par défaut.

Historique par espèce/groupe/installation/période et statuts ; origines et quantités inconnues distinctes de zéro ; annulations conservant l’original. OWNER peut mettre à jour groupes/statuts avec motif/version ou demander une compensation conservatrice. Historique de modifications des groupes consultable ; révisions de statut aussi disponibles par l’API commune des révisions. Une entrée ayant des dépendances n’est pas supprimée.

HTTP en ligne via AquaticService existant ; aucune nouvelle commande outbox. Réponse incertaine : même UUID, même identité de cohorte et même charge figée au réessai. Refus connu : correction possible avec nouvel UUID. Session d’origine conservée, réessai refusé après changement d’utilisateur. Lectures protégées par identité/génération, état précédent effacé après échec. Les écritures sensibles suivent les droits, dont aquatic.fry.stock + aquatic.cohorts.manage pour créer la cohorte.

Palette V2, fond rose pâle, champs blancs bordés de bleu, icônes vertes, formulaires défilants. Tests à 360/1080, texte ×1/×2, enregistrements réels après défilement sur petit écran et contrôles de préremplissage. Captures natives de widgets, aucun navigateur piloté/APK/build Web.

Runner tools/test_phase3b.ps1 : SDK/cache existants D:, --no-pub, profils/temp/build sur D:, tests séquentiels. Contrat complet : ../backend/PISCICULTURE-PHASE3B.md ; résultats réellement exécutés : ../phase3b/RAPPORT-PHASE3B.md.

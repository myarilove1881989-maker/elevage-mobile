# Pisciculture phase 3A — Flutter V2 local

Base c2c6a6c063756ef07e40f32f3be6a1213337dcfb ; branche feature/pisciculture-phase3a-20261113.

Espace Santé ajouté à la navigation piscicole seulement. Trois actions principales : Signaler un problème, Enregistrer un traitement, Consulter l’historique. Filtres bassin, cohorte, espèce et période d’historique. État « En cours et précautions » indépendant de cette période, sans autorisation implicite de vente.

Fiches bassin/cohorte : accès au signalement, au traitement et à l’historique, avec contexte prérempli. Une cohorte présente dans plusieurs bassins ne fait pas choisir arbitrairement le premier : le bassin réel reste à sélectionner. Sans cohorte choisie, acte global explicitement indiqué ; pas de répartition des doses.

Observations libres sans diagnostic ; au moins un symptôme ou comportement. Photo non proposée faute de stockage privé adapté. Traitement : produit existant, quantité décimale exacte et unité connue affichée, motif, observation liée facultative, note, date/heure et confirmation explicite « administré ». Pas de traitement prévu. Délai inconnu par défaut, distinct de zéro ; champ jours et source seulement si le délai est connu et documenté. Aucune posologie recommandée.

Catalogue VACCINE existant utilisé directement. OWNER peut créer un produit sanitaire d’un autre type, avec unité et informations explicites, sans achat/stock/traitement implicite. OWNER peut rectifier un constat en fournissant un remplacement complet et un motif, original conservé. Traitement en cours : déclaration, modifiable par rectification, sans moteur de protocole ou rappel.

V2 existant : bleu foncé, icônes vertes, fond de formulaire rose pâle et champs blancs bordés de bleu. Formulaires et actions défilants, dates au calendrier, textes libres pouvant occuper plusieurs lignes. Aucun changement à la barre principale, au sélecteur pleine largeur Élevage/Pisciculture ni à la navigation terrestre.

AquaticService HTTP en ligne réutilisé, aucune commande dans l’outbox. Réponse incertaine : même UUID/payload, champs figés et réessai identique, lié à l’identité de session d’origine ; réessai refusé après changement d’utilisateur. Refus déterministe 4xx hors 408 : correction possible, nouvelle commande. Lectures protégées contre réponses tardives, changement de session et données périmées après échec.

Tests widgets : observation/traitement/produit/rectification à 360 et 1080 pixels, texte ×1/×2 ; enregistrement réel après défilement sur petit écran avec texte ×2 ; préremplissage depuis les fiches ; historique et filtres, unknown vs zéro, rôle lecture, réseau et idempotence. Captures natives sans navigateur, APK ni build Web.

Runner tools/test_phase3a.ps1 : dépendances et SDK D: réutilisés, --no-pub, caches/profil/temp/build sur D:, tests séquentiels. Contrat API dans ../backend/PISCICULTURE-PHASE3A.md et résultats réels dans ../phase3a/RAPPORT-PHASE3A.md.

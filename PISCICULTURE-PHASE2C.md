# Pisciculture phase 2C — Flutter V2 local

Base : 430a1ec38c5dfe671d0e66bce3c21fcddb478016. Branche feature/pisciculture-phase2c-20261112.

Onglet Alimentation ajouté à l’espace piscicole existant. Stock partagé, distributions/historiques, période par calendrier, filtres bassin/cohorte/aliment, graphe des quantités journalières et classement des aliments. Stock actuel explicitement indépendant des filtres de population et de période. Achats et mouvements étiquetés comme communs à l’exploitation, jamais artificiellement rattachés au bassin sélectionné.

Formulaires V2 : acheter un aliment existant ou créer explicitement le nom (OWNER), catégorie existante alimentaire ou nouvelle (OWNER), quantité kg et montant décimaux exacts ; distribution à un bassin et cohorte facultative sans choix arbitraire ; gestion explicite des réserves par propriétaire. Date/heure par sélecteurs, heure connue facultative et date seule préservée. Virgule de saisie normalisée en point ; les montants/quantités restent des chaînes dans les requêtes.

Restes vides distincts de zéro. Total de consommation inconnu ou partiel expliqué ; sous-total connu distinct. Biomasse indicative seulement lorsque qualifiée par l’API ; données insuffisantes affichées sinon. FCR non calculé, aucune ration par défaut. Une seule carte Alimentation au tableau de bord, période affichée, stock commun et trois aliments les plus utilisés.

Lecture et boutons selon capacités existantes ; API autorité finale. HTTP authentifié uniquement via AquaticService existant ; aucune nouvelle commande offline/outbox. Réponse réseau incertaine : même UUID/charge conservés, champs figés, réessai identique. Refus déterministe 4xx hors 408 : correction possible avec nouvelle commande. Protection des lectures tardives par génération et identité de session ; données anciennes effacées en cas d’échec. Pas de modification des clés/PIN, du protocole ou des écrans terrestres.

Palette V2 existante, bleu foncé, icônes vertes, formulaires fond rose pâle, champs blancs bordés de bleu. Formulaires défilants et actions accessibles. Tests widgets réels à 360/1080 pixels, texte normal et ×2 pour tableau de bord/écran, captures sans navigateur.

Runner tools/test_phase2c.ps1 : SDK et caches réutilisés sur D:, profil/temp/compilation D:, --no-pub, tests séquentiels. Aucun APK, pub get, installation ou build Web. Contrat backend détaillé dans ../backend/PISCICULTURE-PHASE2C.md ; résultats exacts et captures dans ../phase2c/RAPPORT-PHASE2C.md.

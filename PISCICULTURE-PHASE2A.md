# Pisciculture phase 2A — Flutter V2 local

Base : cf02104eb375fa7a674e87808aaef6a5ae647da9.
Nouveaux onglets dans l’espace piscicole : Pesées, Eau, Règles.

Formulaires avec dates explicites et unités, décimaux transmis en chaînes,
virgule française normalisée sans calcul binaire des valeurs métier.
Pesée par cohorte ou bassin, échantillon ou poids moyen direct ; date de
référence d’effectif visible. Graphique chronologique seulement après choix
d’une cible ; une pesée de bassin ne rejoint jamais une courbe de cohorte.
Les calculs canoniques restent au backend ; double uniquement pour dessiner.

Relevé partiel d’eau, zéro conservé, champs vides omis. Historique affichant
les évaluations par population, la règle et sa version, les seuils incompatibles
et les alertes issues uniquement de règles configurées.

Règles installation, espèce/stade ou système, bornes et intervalle de validité,
remplacement daté d’une règle existante. Délégation explicite requise côté API ;
les boutons de mutation suivent les capacités reçues.

Chargement protégé contre les réponses tardives et changements de session.
Une réponse de mutation incertaine fige la commande et son UUID ; réessai
strictement identique. Aucune commande envoyée dans l’outbox.
Le dialogue V2 conserve sa protection des brouillons.

Tests locaux : tools/test_phase2a.ps1 (par défaut nouveaux tests).
Paramètre -Targets pour la non-régression. SDK et cache existants sur D:,
profil d’outil, temporaires, captures et compilations de tests sur D:.
Résolution des dépendances hors ligne. Le pub get Flutter standard rencontre
une limite exFAT sur les liens Windows bureau ; tests --no-pub après création
du package_config avec les dépendances déjà présentes. Pas de build Web,
d’APK ni de navigateur piloté.

Non modifiés : Android/version, pubspec et lockfile, PIN/profils, outbox,
notification Android 119, /telecharger et /android-version.json.
Limites : français piscicole uniquement, aucun test appareil Android ni E2E
navigateur/API ; snapshots de widgets avec données synthétiques. Voir rapport
de qualification parent pour les résultats réellement exécutés et captures.

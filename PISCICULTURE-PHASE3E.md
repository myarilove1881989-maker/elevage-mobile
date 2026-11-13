# Pisciculture 3E — qualification Flutter

Base 0c9b92d9919eccabd42a08bfb0d027616dc6a2dc, copie isolée D:/ElevAge-Pisciculture-Phase3E-20261113/flutter, branche feature/pisciculture-phase 3e-qualification-20261113. Aucun code applicatif Flutter, dépendance, version ou artefact Android modifié. La copie et les commits précédents sont préservés.

Correction d’un test périmé uniquement : aquatic_phase1_test vérifie les accès Finances et Agenda et l’absence de l’ancien texte « Non disponible (phases suivantes) », plutôt que d’exiger cet ancien message après livraison3D. Les vérifications de la barre, du sélecteur50/50, des largeurs360/1080 et du texte agrandi sont conservées.

Reproduction : tools/qualify_phase3e.ps1. D: obligatoire ; SDK3.47.6 verrouillé existant, pub-cache D: existant, profils/temp/cache/compilations D:, --no-pub et tests séquentiels. Par défaut tous les fichiers de test. Les captures de phases restent dans qualification/captures ; un dossier evidence distinct reçoit la facture PDF synthétique. Le runner ne crée ni APK ni publication Web.

La campagne globale conserve les résultats complets, tests ignorés, erreurs initiales et confirmations finales. Les limites de temps des essais chiffrés/hors ligne doivent être distinguées de défauts applicatifs ; aucune assertion ou limite n’est relâchée pour fabriquer un succès. Aucun changement aux clés/PIN, base/outbox, transports ou contrats offline.

Les contrôles de widgets natifs couvrent les formulaires360/1080, texte ×1/×2. Ils ne remplacent pas une recette navigateur ou appareil. Un export Web debug de la base applicative3D, séparé sur D:, peut être servi uniquement en boucle locale avec API synthétique et profil navigateur isolé D:, sans publier ni connecter la production ; ses résultats sont consignés séparément. Aucun appareil Android119 n’est modifié ou remplacé.

Voir ../qualification/RAPPORT-PHASE3E.md, matrice, rapports, journaux, captures et limites pour les résultats effectifs. Les nouvelles fonctions aquatiques restent en ligne et en français ; une traduction anglaise complète et une recette sur matériel réel ne sont pas revendiquées. Aucune publication ni phase 4 sans validation.

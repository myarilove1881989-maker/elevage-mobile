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

Le backend doit accepter P-256 avec signature DER SHA256withECDSA pour
Android Keystore API 24, en complément d'Ed25519. La clé privée ne doit
jamais sortir du Keystore.

Le chiffrement Drift utilisera le mécanisme maintenu sqlite3 3.x et
sqlite3mc. Une vérification en mode release refusera toute ouverture si
le moteur chiffrant n'est pas disponible. Une preuve de fichier illisible
avec SQLite standard est obligatoire avant validation 2C.

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

# État du projet

Version applicative : `1.0.0+1` (pubspec). Dernière mise à jour : 23 octobre 2026.

## Résumé

Hydra POS est une application Flutter Android de caisse et de gestion de
boutique, hors ligne, en arabe (par défaut, RTL) et en français (LTR), avec le
dirham marocain. Le code couvre le cycle complet : produits et stock, caisse,
achats, retours, dettes, caisse espèces, rapports, PDF, sauvegarde,
import/export.

Cette itération ajoute l'accueil de premier lancement, les deux profils de
commerce, la classification en deux divisions, la gestion des lots et
péremptions, les thèmes clair/sombre/système et la correction des
`setState` asynchrones.

## Vérifications réellement exécutées

| Vérification | Commande | Résultat |
| --- | --- | --- |
| Formatage | `dart format lib test` | **88 fichiers formatés** |
| Analyse statique | `flutter analyze` | **Aucun problème** |
| Tests automatisés | `flutter test` | **132 réussis, 0 échec** |
| Build Android debug | `flutter build apk --debug --dart-define=use_arabic=true` | **APK produit** |
| Build Android release | `flutter build apk --release --dart-define=use_arabic=true` | **APK produit (81,7 Mo)** |

Détail des tests par fichier : [TESTING.md](TESTING.md).

### APK produits

Debug — `build/app/outputs/flutter-apk/app-debug.apk`

- Taille mesurée : 223 914 291 octets, soit environ **213,5 Mio** (build debug
  universel, toutes les architectures, sans minification).
- Signé avec la clé debug de Flutter : installable pour essai, non publiable.

Release — `build/app/outputs/flutter-apk/app-release.apk`

- Taille mesurée : 85 654 767 octets, soit **81,7 Mo** (APK universel).
- `aapt2` confirme : `com.hydra.pos.hydra_pos`, version `1.0.0` (code 1),
  minSdk 24, targetSdk 36, label `Hydra POS`.
- `apksigner` confirme que l'APK est signé avec le certificat
  **Android Debug** (`CN=Android Debug`), schéma v2. Il s'agit donc d'une preuve
  que le mode release compile, **pas d'un APK publiable**.
- Aucune installation ni exécution sur appareil n'a été effectuée.

## Ce qui est implémenté

- **Premier lancement** : écran d'accueil arabe avec les cinq points forts,
  bouton principal « ابدأ الآن », choix du type de commerce et bascule de
  langue. L'écran ne s'affiche qu'une fois et reste accessible depuis
  Réglages → « Revoir l'accueil ».
- **Profils de commerce** :
  - `محل تجاري صغير` (petit commerce) : navigation simplifiée
    Caisse / Produits / Dettes / Plus.
  - `سوبر ماركت` (supermarché) : navigation complète
    Tableau de bord / Caisse / Produits / Ventes / Plus.
  - Même base, mêmes services et mêmes données pour les deux profils. Le profil
    ne change que la navigation et l'ordre des raccourcis ; il se modifie à tout
    moment dans Réglages.
- **Classification** : exactement deux divisions de premier niveau, **الأكل**
  (alimentaire) et **غير الأكل** (non alimentaire), avec 16 sous-catégories
  prédéfinies verrouillées. Les sous-catégories personnalisées peuvent être
  ajoutées, renommées, déplacées de division, fusionnées ou supprimées avec
  réaffectation explicite des produits. Aucun produit ni historique n'est
  supprimé ; les produits non classés restent accessibles par un filtre dédié.
- **Lots et péremptions** : plusieurs lots par produit, quantités séparées,
  numéro de lot facultatif, date de péremption facultative, alerte par défaut à
  30 jours. Les ventes consomment les lots en FEFO (premier expiré, premier
  sorti) et enregistrent les allocations pour que les retours restaurent le bon
  lot. Vues « proches », « périmés » et « sans date » ; mise au rebut avec
  confirmation, motif et journal d'audit.
- **Thèmes** : clair, sombre et système, persistés. La palette sombre utilise
  des variantes à contraste élevé (vérifiées AA par un test) et tous les écrans,
  dialogues, formulaires et graphiques suivent le thème actif.
- **Caisse** : recherche locale, saisie clavier/douchette, scan caméra,
  multiplicateur de quantité, conditionnements, remise, paiement comptant,
  partiel ou crédit, rendu de monnaie, confirmation idempotente. Les
  `setState(() { _future = _load(); })` sont synchrones dans toute
  l'application ; plus aucun callback `setState` ne renvoie un `Future`.
- **Produits** : CRUD, code-barres, division et sous-catégorie, fournisseur,
  unités et prix de conditionnement, seuil d'alerte, notes, archivage, lot
  initial avec péremption facultative.
- **Stock** : quantités en milli-unités, lots, péremption, mouvements justifiés,
  inventaire par session, coût moyen pondéré, ajustements compatibles avec les
  lots.
- **Achats** : fournisseur, coût, paiement partiel, annulation, numéro de lot et
  péremption par ligne, bon PDF/CSV.
- **Ventes** : historique, détail, paiements, retours partiels, annulation,
  facture A4 PDF, reçu 58/80 mm, partage.
- **Tiers** : clients et fournisseurs, soldes, règlements, grand livre.
- **Finance** : dépenses, sessions de caisse, rapprochement, rapports et
  graphiques, exports CSV et XLSX.
- **Exploitation** : sauvegarde/restauration locale, import CSV/XLSX, journal
  d'audit, écran À propos avec attributions.
- **Catalogues** : Open Food Facts v3 et Open Products Facts, cache avec TTL,
  recherche locale prioritaire, aucune écriture dans les prix/stock/dettes.
- **Langues** : arabe par défaut avec RTL, français en LTR, libellés et messages
  d'erreur traduits ; montants en MAD.

## Migrations et données

- Schéma SQLite **v3**. La migration est idempotente et conserve toutes les
  lignes existantes.
- `v1 → v3` et `v2 → v3` sont couvertes par des tests avec vérification des
  produits, catégories, paramètres et du versionnement.
- Nouvelles colonnes : métadonnées de division et verrouillage des catégories,
  numéro de lot et péremption sur les lignes d'achat, table
  `sale_line_batches` pour les allocations FEFO.
- Les catégories héritées sont conservées. Les anciennes catégories
  Alimentation / Boissons / Fruits et légumes / Produits laitiers sont classées
  en alimentaire ; Hygiène / Entretien en non alimentaire ; Autres reste sans
  division.
- Une installation neuve démarre en arabe, thème système, petit commerce,
  accueil à afficher et alerte de péremption à 30 jours.
- Une base existante contenant déjà des données est marquée comme ayant déjà vu
  l'accueil lors de la mise à jour, afin de ne pas interrompre le commerce.
- Les anciennes valeurs de paramètres inconnues retombent sur des valeurs sûres
  (arabe, système, petit commerce, 30 jours).

## Ce qui n'a pas pu être vérifié

Aucun téléphone Android, aucune imprimante Bluetooth et aucun scanner physique
n'étaient disponibles pendant le développement. Les points suivants restent
donc **non validés sur matériel réel** :

1. Installation et démarrage sur Android 10 et Android 14.
2. Scan caméra réel (autorisation, luminosité, codes difficiles).
3. Impression thermique Bluetooth ESC/POS (appairage, encodage, coupe papier).
4. Partage de fichiers, sélecteur de fichiers et permissions à l'exécution.
5. Performances et confort sur un téléphone d'entrée de gamme.
6. Rendu imprimé des PDF arabes (la génération est testée, pas l'impression).
7. Rendu visuel exact sur un appareil physique des écrans étroits testés en
   widget (360 × 640) et du mode sombre.

Ces points figurent aussi dans la checklist manuelle de [TESTING.md](TESTING.md).

## Limites connues

- **Signature de publication** : `android/app/build.gradle.kts` utilise encore
  la clé debug pour le type `release`, et l'APK release produit est bien signé
  par `CN=Android Debug`. Il faut créer un keystore, configurer
  `signingConfigs.release` et ne jamais versionner les mots de passe.
- **Identifiant d'application** : `com.hydra.pos.hydra_pos` est un identifiant
  de travail ; à remplacer avant publication sur un store.
- **PDF arabes** : nécessitent `--dart-define=use_arabic=true` (polices Noto
  Sans Arabic embarquées). Sans ce drapeau, l'interface reste correcte mais les
  noms arabes des PDF peuvent ne pas être liés.
- **Marges** : les rapports de bénéfice sont des estimations au coût moyen
  pondéré, pas une comptabilité fiscale certifiée.
- **Catalogue externe** : dépend d'Internet et de la couverture communautaire ;
  Open Products Facts est encore peu couvert. L'application reste pleinement
  utilisable hors ligne.
- **Sauvegarde** : locale uniquement (fichier choisi par l'utilisateur) ; aucune
  synchronisation cloud n'est fournie ni requise.
- **Base de données** : schéma v3 ; les migrations v1 → v3 et v2 → v3 sont
  testées. Une base créée par une version future est refusée avec un message
  explicite.
- **Dépôt Git** : le code est versionné à la racine du dépôt et publié sur
  GitHub (`Mpsy19/HYDRA`), sous licence MIT.

## Sécurité et données

- Montants stockés en centimes entiers, quantités en milli-unités : aucun
  calcul monétaire en virgule flottante.
- Écritures de vente, achat, retour, stock et mise au rebut dans des
  transactions SQLite.
- Confirmation de vente idempotente par clé unique.
- Les factures et tickets sont des instantanés : l'historique n'est pas
  réécrit par une modification ultérieure de produit.
- La restauration de sauvegarde valide le fichier avant remplacement.
- Aucune donnée n'est envoyée à un serveur ; les fonctions caméra, Bluetooth et
  fichiers restent locales.

## Prochaines étapes recommandées

1. Tester sur au moins deux appareils Android réels (Android 10 et 14), en
   arabe RTL et en mode sombre.
2. Tester une imprimante thermique 58 mm et 80 mm, puis ajuster la mise en page.
3. Configurer la signature de publication et un identifiant d'application
   définitif.
4. Vérifier la licence et la structure du dépôt avant toute distribution
   publique.
5. Faire une passe de validation avec un commerçant : vocabulaire, flux de
   caisse, tickets et rapports.
6. Ajouter, si nécessaire, l'export de sauvegarde vers un stockage externe et
   un écran de diagnostic matériel.

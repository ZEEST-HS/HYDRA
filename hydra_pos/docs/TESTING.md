# Tests et vérifications

## Commandes

```powershell
$env:Path = "C:\src\flutter\bin;$env:Path"
$env:JAVA_HOME = "C:\src\jdk\jdk-17.0.20.1+1"

flutter analyze
flutter test
flutter test test/widget_test.dart --reporter expanded
```

## Résultat vérifié

Dernière exécution complète :

- `flutter analyze` : **aucun problème**.
- `flutter test` : **132 tests réussis**, 0 échec.

Répartition :

| Fichier | Objet | Tests |
| --- | --- | --- |
| `test/core/money_test.dart` | analyse, formatage, totaux de ligne, séparateurs arabes | 12 |
| `test/core/quantity_test.dart` | conversions milli-unités et conditionnements | 8 |
| `test/data/migration_test.dart` | v1 → v3, v2 → v3, valeurs par défaut, version future | 4 |
| `test/data/category_repository_test.dart` | divisions, 16 sous-catégories, ajout, renommage, fusion, suppression | 8 |
| `test/data/settings_repository_test.dart` | valeurs par défaut, persistance thème/profil/accueil, repli | 3 |
| `test/data/product_inventory_test.dart` | produits, unités, stock, lots, mouvements | 8 |
| `test/domain/batch_expiry_test.dart` | FEFO, allocations, retours, rebut, vues de péremption | 4 |
| `test/domain/sale_service_test.dart` | vente, crédit, idempotence, annulation, stock | 12 |
| `test/domain/purchase_service_test.dart` | achat, coût moyen, paiement partiel, annulation, lot | 9 |
| `test/domain/return_service_test.dart` | retours partiels, cumul, remboursement, crédit | 8 |
| `test/domain/cash_service_test.dart` | rapprochement, annulations, remboursements | 5 |
| `test/domain/catalog_service_test.dart` | cache, TTL, hors ligne, priorité, écritures isolées | 10 |
| `test/domain/backup_service_test.dart` | création, validation, restauration, refus | 5 |
| `test/domain/party_repository_test.dart` | soldes, règlements, grand livre | 4 |
| `test/domain/report_service_test.dart` | revenus, retours, COGS, dépenses, encaissements | 3 |
| `test/services/import_export_service_test.dart` | CSV/XLSX, stock optionnel, erreurs, export | 9 |
| `test/services/print_service_test.dart` | octets ESC/POS, ASCII, totaux, coupe | 8 |
| `test/services/invoice_pdf_service_test.dart` | PDF facture et reçu arabe avec les polices embarquées | 2 |
| `test/ui/theme_test.dart` | contraste AA des palettes claire et sombre, bascule | 3 |
| `test/widget_test.dart` | navigation FR/AR, accueil, profils, mode sombre, 360 × 640 | 7 |

## Méthodes

- Les tests de domaine et de données utilisent `sqflite_common_ffi` avec une base
  en mémoire ou un fichier temporaire via `TestEnv`.
- Les montants sont vérifiés en centimes exacts, jamais en flottants.
- Les tests de vente couvrent la clé d'idempotence, le paiement partiel, la
  dette client et l'annulation avec restitution du stock.
- Les tests d'achat couvrent le coût moyen pondéré, le paiement partiel
  fournisseur et l'annulation.
- Les tests de retour couvrent les retours cumulés et l'interdiction d'un
  remboursement espèces sur une vente encore due.
- Les tests de caisse vérifient que ventes annulées, remboursements et
  règlements fournisseurs sont correctement signés.
- Les tests de catalogue utilisent des fournisseurs simulés et vérifient que
  les tables métier ne sont pas modifiées.
- Les tests de sauvegarde créent une base fichier réelle, sauvegardent,
  modifient, restaurent et vérifient les données.
- Un test PDF charge réellement les polices embarquées et génère une facture
  A4 ainsi qu'un reçu arabe. Il a été ajouté après la découverte de fichiers de
  police arabes invalides (pages HTML téléchargées par erreur) ; les polices
  Noto Sans Arabic ont été remplacées par de véritables TTF et le test empêche
  une régression.

## Tests de widgets

Un piège important : les appels SQLite passent par de vrais ports de réception.
Dans `testWidgets`, la zone de temps simulé ne les termine pas. Le helper
`_bootstrap` est donc exécuté dans `tester.runAsync`, puis chaque pompage laisse
les futures SQLite se terminer avant de rendre le résultat. Cela évite à la fois
les blocages de 60 secondes et l'utilisation de `pumpAndSettle` avec un
indicateur de progression.

Ces tests ont aussi révélé un vrai défaut : `AppScope.of` était appelé dans
`initState`, ce que Flutter interdit. Les chargements utilisent désormais
`AppScope.read`, sans dépendance héritée.

Les tests de widgets couvrent en plus :

- l'accueil de premier lancement et l'enregistrement du profil choisi ;
- la navigation simplifiée du petit commerce et la navigation complète du
  supermarché ;
- le rendu arabe RTL et le passage en mode sombre ;
- un écran de 360 × 640 px en arabe sombre, avec ouverture des onglets Produits,
  Dettes, Plus, Stock et Réglages, sans débordement de mise en page ;
- l'accueil arabe sur la même largeur étroite.

Un test de thème calcule le contraste WCAG des couleurs sémantiques et exige au
moins 4,5:1 sur les surfaces claire et sombre.

## Ce qui n'est pas couvert

- Scan caméra réel et lecture de codes-barres sur appareil.
- Impression Bluetooth réelle.
- Rendu visuel des PDF arabes (la génération est testée, pas l'aspect imprimé).
- Interactions Android (partage, sélecteur de fichiers, permissions runtime).
- Performance sur un téléphone d'entrée de gamme.
- Contraste et ergonomie sur appareil réel (les palettes et les écrans étroits
  sont vérifiés en test, pas sur un écran physique).
- Migration depuis une version future (les migrations v1 → v3 et v2 → v3 sont
  couvertes, et une base plus récente est refusée).

## Vérifications manuelles recommandées avant livraison

1. Installer l'APK sur un Android 10 et un Android 14.
2. Accorder/refuser les permissions caméra et Bluetooth.
3. Scanner un code produit, un code inconnu, puis le même code deux fois.
4. Vendre en espèces, en crédit, avec `10×` et un conditionnement.
5. Faire un retour partiel, puis vérifier le stock et la caisse.
6. Créer un achat à crédit, payer partiellement, annuler.
7. Ouvrir/fermer une session de caisse avec écart.
8. Générer un PDF arabe, le partager, puis l'imprimer en Bluetooth.
9. Sauvegarder, modifier, restaurer, rouvrir l'application.
10. Passer en arabe et vérifier le sens de lecture.
11. Installer une base existante (v2) et vérifier que les produits, ventes,
    dettes et catégories sont conservés, sans réafficher l'accueil.
12. Choisir « petit commerce » puis « supermarché » dans Réglages et vérifier
    que la navigation change sans modifier les données.
13. Créer deux lots du même produit avec des dates différentes, vendre, puis
    vérifier que le lot le plus proche de la péremption sort en premier.
14. Mettre un lot au rebut et vérifier le stock, le motif et le journal d'audit.
15. Basculer clair / sombre / système et vérifier la lisibilité des textes,
    icônes, graphiques et dialogues.

# Architecture

## Objectif

Hydra POS est une application Flutter Android-first, utilisable hors ligne, pour
une boutique de proximité marocaine. Le code est organisé en couches simples afin
que les règles d'argent et de stock restent testables sans interface.

## Couches

```text
features/ (écrans, widgets)
        │  AppScope / AppController
        ▼
domain/ (ventes, achats, retours, caisse, rapports, catalogue, sauvegarde)
        │
        ▼
data/ (dépôts SQLite + modèles)
        │
        ▼
core/ (unités, erreurs, dates, AppDatabase, L10n)
```

- `lib/core/money.dart` : montants en **centimes entiers**. Aucun `double` pour
  l'argent. Analyse tolérante des saisies (`12,50`, espaces, séparateurs
  arabes) et totaux de ligne exacts.
- `lib/core/quantity.dart` : quantités en **milli-unités** (`1000` = une unité
  de base). Les facteurs de conditionnement sont aussi des milli-unités.
- `lib/core/db/app_database.dart` : ouverture SQLite, schéma, migrations,
  transactions et jeu de paramètres initial.
- `lib/data/repositories/` : accès SQL. Le stock n'est jamais modifié par un
  écran directement.
- `lib/domain/` : règles métier et opérations multi-tables. Les services
  ouvrent une transaction et écrivent ensemble vente, lignes, stock, paiements,
  grand livre et audit.
- `lib/features/` : interface. Chaque écran appelle `AppScope.of(context)` pour
  les reconstructions et `AppScope.read(context)` pour les chargements lancés
  depuis `initState` (Flutter interdit les dépendances héritées à cet endroit).

## Démarrage

`HydraBoot` ouvre la base et construit `AppController` avant le premier écran.
`AppController` possède les dépôts, services, la langue et la boutique. Il
notifie l'interface via `ChangeNotifier`; `HydraApp` reconstruit le `MaterialApp`
et `AppScope` transmet le contrôleur.

Le premier écran est `HomeShell`, avec cinq onglets : tableau de bord, caisse,
produits, ventes, plus. Les écrans sont conservés dans un `IndexedStack`.

## Règles structurantes

### Argent

- Tous les montants persistés sont des entiers de centimes.
- Les totaux de ligne peuvent être fournis explicitement pour éviter les écarts
  d'arrondi lors des conditionnements.
- Une vente ou un achat ne peut pas dépasser son total en paiement.
- Les rapports de marge utilisent le coût moyen pondéré et sont estimatifs.

### Stock

- Les mutations de stock passent par `InventoryRepository` ou par les services
  de vente/achat/retour, dans une transaction SQLite.
- Chaque mouvement écrit une ligne `stock_movements` avec type, delta, coût et
  référence.
- Le coût moyen pondéré est recalculé à la réception d'un achat. Annuler un
  achat ne réécrit pas l'historique des coûts déjà consommés.
- La politique de stock est configurable : bloquer, demander confirmation ou
  autoriser le stock négatif.

### Ventes

- `SaleService.completeSale` est **idempotent** : une clé unique renvoyée deux
  fois retourne la vente existante sans consommer un nouveau numéro.
- Une vente validée est historiquement figée. Seuls le statut d'annulation, le
  motif et l'horodatage peuvent être ajoutés ; les lignes ne sont pas modifiées.
- Le paiement partiel crée une créance client et une écriture de grand livre.
- Les retours vérifient les quantités cumulées déjà retournées et le montant
  remboursable. Un remboursement espèces est refusé si la vente d'origine a
  encore une dette.

### Achats

- `PurchaseService.completePurchase` exige un fournisseur si un solde reste dû.
- Le paiement partiel met à jour le solde fournisseur et le dû de l'achat dans
  la même transaction.
- L'annulation remet le stock et les soldes en cohérence, sans recalcul
  rétroactif du coût moyen.

### Caisse

Le rapprochement additionne : fond de caisse, ventes espèces (y compris les
ventes annulées, compensées par les sorties), règlements clients espèces,
règlements fournisseurs espèces, remboursements fournisseurs, dépenses espèces
et remboursements/annulations espèces. La différence est calculée sur le
montant compté.

### Audit

Les opérations sensibles (annulation, suppression, ajustement, restauration,
import) écrivent dans `audit_log` avec un motif lorsque l'interface en demande
un. L'écran d'audit affiche les entrées récentes et leur détail JSON.

## Interface et localisation

- Thème clair/sombre Material 3, composants adaptatifs.
- `L10n` utilise le texte français comme clé et fournit la traduction arabe.
  Les écrans basculent en RTL quand la langue est l'arabe.
- Les tailles sont pensées pour les petits écrans ; les listes et formulaires
  restent utilisables au clavier et à la douchette.

## Services transverses

- `InvoicePdfService` : factures A4, reçus, bons d'achat, polices latines et
  arabe.
- `PrintService` : ESC/POS Bluetooth, ASCII uniquement, avec repli PDF/partage.
- `ImportExportService` : CSV/XLSX produits, exports ventes/achats/dettes.
- `BackupService` : copie cohérente de la base, validation et restauration.
- `CatalogService` : fournisseurs externes, cache, limitation de débit, repli
  hors ligne ; n'écrit jamais dans les tables métier.

## Choix assumés

- Pas de gestion d'état lourde (bloc, Riverpod) : `ChangeNotifier` et navigation
  simple suffisent et réduisent la charge sur les téléphones modestes.
- Pas de cloud, de compte, ni de service payant.
- Les migrations sont explicites et testées ; le schéma courant est la version 2.

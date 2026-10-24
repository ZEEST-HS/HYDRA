# Base de données

SQLite via `sqflite`, fichier `hydra_pos.db`, schéma **version 2**. Les clés
étrangères sont activées à l'ouverture. Les écritures multi-tables passent par
une transaction.

## Unités

| Donnée | Unité | Exemple |
| --- | --- | --- |
| Argent | centimes entiers | `1250` = 12,50 DH |
| Quantité | milli-unités de base | `1500` = 1,5 kg |
| Facteur d'unité | milli-unités | `12000` = carton de 12 pièces |
| Dates métier | texte ISO `YYYY-MM-DD` | `2026-10-23` |
| Horodatages | millisecondes Unix | `1761200000000` |

Aucun montant n'est stocké en flottant.

## Tables

### Référentiel

- `settings(key, value)` : paires clé/valeur (langue, politique de stock,
  péremption, imprimante, largeur papier, impression auto).
- `shop(id = 1, name, name_ar, address, phone, email, tax_id, footer,
  logo_path, updated_at)` : coordonnées affichées sur les documents.
- `categories(id, name_fr, name_ar, created_at)`.
- `sequences(name, next_value)` : numéros de facture, bon d'achat et retour.

### Produits et stock

- `products` : code-barres, noms FR/AR, marque, catégorie, conditionnement,
  unité de base, coût, prix, stock, seuil, fournisseur, image, source catalogue,
  actif, suppression logique, notes, horodatages.
- `product_units` : nom FR/AR, `factor_milli`, prix et coût optionnels, unité
  par défaut à la vente/à l'achat.
- `batches` : lot, date de péremption, quantité reçue/restante, coût unitaire,
  achat d'origine.
- `stock_movements` : type, delta de quantité, coût unitaire, référence, motif,
  date métier. C'est le journal de vérité des variations.

### Ventes

- `sales` : numéro de facture unique, client, totaux, payé, dû, mode de
  paiement, statut, date métier, clé d'idempotence unique, note, annulation.
- `sale_lines` : produit et nom figés, code-barres, unité, facteur, quantité,
  prix, coût unitaire, remise de ligne, total de ligne exact.
- `sale_returns` et `return_lines` : remboursements, quantités retournées,
  valorisation d'origine.

### Achats

- `purchases` : référence unique, fournisseur, totaux, payé, dû, mode, statut,
  date métier, note, annulation.
- `purchase_lines` : produit, unité, facteur, quantité, coût, total, péremption.

### Tiers, paiements et dettes

- `customers` : nom, téléphone, adresse, note, solde, limite de crédit,
  suppression logique.
- `suppliers` : nom, téléphone, adresse, note, solde, suppression logique.
- `payments` : type de tiers, identifiant, sens, montant, mode, référence, note,
  date métier, liens éventuels vers vente/achat/retour.

Un solde client positif représente une dette du client envers la boutique. Un
solde fournisseur positif représente une dette de la boutique envers le
fournisseur.

### Caisse, dépenses et audit

- `expenses` : catégorie, montant, mode, note, date métier.
- `cash_sessions` : ouverture, clôture, fond, attendu, compté, différence,
  note, statut.
- `ledger_entries` : écritures clients/fournisseurs (dette, règlement,
  remboursement).
- `audit_log` : action, entité, identifiant, détail JSON, motif, horodatage.

### Cache catalogue

- `catalog_cache(barcode PRIMARY KEY, source, found, payload_json, fetched_at)`.
  Table isolée ; aucune donnée métier n'est écrasée par un catalogue externe.

## Index principaux

- Code-barres unique parmi les produits actifs non supprimés (index partiel).
- Recherche par nom, activité, stock, fournisseur.
- Dates métier des ventes, achats, paiements, dépenses et mouvements.
- Clients/fournisseurs des ventes et achats ; lignes par document.
- Péremption des lots, ventes par statut, audit par date.

## Migrations

Le schéma de base est créé par `createBaseSchema`, puis `migrateV1ToV2` ajoute
`products.notes`, `sales.note` et `purchases.note`. La migration est idempotente
(`PRAGMA table_info`) et testée sur une base v1 réelle. Toute nouvelle version
doit suivre le même modèle : une étape explicite, idempotente et testée.

## Intégrité et sauvegarde

- Contraintes de clés étrangères et index uniques sur les numéros de document.
- Les services vérifient les montants, les quantités et les soldes avant
  d'écrire ; les erreurs annulent la transaction.
- `BackupService` force un checkpoint WAL, ferme la base, copie le fichier,
  puis la rouvre. La restauration vérifie l'en-tête SQLite, la taille minimale
  et la présence des tables essentielles avant de remplacer le fichier.
- Les sauvegardes sont stockées dans `backups/` du répertoire de documents et
  peuvent être partagées ou restaurées depuis un fichier externe.

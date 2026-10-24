# Hydra POS

Application de caisse et de gestion de boutique pour le commerce de proximité
marocain. Conçue pour Android, en priorité pour des téléphones d'entrée de gamme,
avec interface **français / العربية** (RTL), montants en **MAD (DH)** et
fonctionnement **100 % hors ligne**.

## Fonctions

- Caisse tactile : recherche produit, scan caméra ou douchette, multiplicateur
  `10×`, unités de conditionnement (pièce, paquet, carton), panier, remise,
  paiement comptant ou crédit, rendu de monnaie, impression et PDF.
- Produits : prix d'achat/vente, stock, seuil d'alerte, code-barres, catégories,
  fournisseur, unités et prix par conditionnement, notes.
- Achats : saisie fournisseur, coût, dates de péremption, paiement total ou
  partiel, annulation, bon d'achat PDF/CSV.
- Stock : journal des mouvements, ajustements justifiés, stock compté,
  lots proches de la péremption, inventaire par session.
- Clients et fournisseurs : soldes, règlements, historique (grand livre).
- Ventes : liste, détail, paiements partiels, retour/remboursement, annulation,
  facture PDF, reçu thermique.
- Dépenses, sessions de caisse, rapprochement des espèces, rapports et
  graphiques, exports CSV/XLSX.
- Sauvegardes locales, restauration, import CSV/XLSX, journal d'audit.
- Recherche de produits via Open Food Facts et Open Products Facts, avec cache.

## Démarrage

Prérequis : Flutter stable, JDK 17, SDK Android.

```powershell
flutter pub get
flutter test
flutter analyze
flutter run
```

Build Android avec le moteur PDF arabe activé :

```powershell
flutter build apk --release --dart-define=use_arabic=true
```

Sans `use_arabic=true`, les PDF restent corrects en français mais les noms
arabes peuvent apparaître avec des lettres non liées dans le PDF. L'interface
arabe, elle, n'est pas concernée.

Variables utiles sous Windows :

```powershell
$env:Path = "C:\src\flutter\bin;$env:Path"
$env:JAVA_HOME = "C:\src\jdk\jdk-17.0.20.1+1"
$env:ANDROID_HOME = "C:\src\android-sdk"
```

## Organisation du dépôt

```text
lib/
  app/            démarrage, contrôleur, navigation
  core/           monnaie, quantités, dates, erreurs, SQLite, L10n
  data/           modèles et dépôts SQLite
  domain/         ventes, achats, retours, caisse, rapports, catalogue, sauvegarde
  features/       écrans par domaine
  integrations/   fournisseurs de catalogues externes
  services/       PDF, impression, import/export, partage
  ui/             thème et composants partagés
test/             tests unitaires, dépôts, services et widgets
docs/             architecture, base, catalogue, impression, tests, statut
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Base de données](docs/DATABASE.md)
- [Catalogues externes](docs/CATALOG.md)
- [Impression et PDF](docs/PRINTING.md)
- [Tests](docs/TESTING.md)
- [État du projet](docs/STATUS.md)
- [Guide utilisateur](docs/USER_GUIDE.md)
- [Audit de la phase 1](docs/PHASE1_AUDIT.md)

## Limites connues

- Aucune imprimante Bluetooth physique ni aucun téléphone Android n'était
  disponible pendant le développement : l'impression thermique réelle et le
  scan caméra sur appareil restent à valider.
- Les PDF arabes nécessitent le build avec `--dart-define=use_arabic=true`.
- Les rapports de marge sont des estimations (coût moyen pondéré) et ne
  constituent pas une comptabilité fiscale certifiée.
- Le catalogue externe dépend d'Internet et de la couverture communautaire ;
  il ne remplace jamais les prix, le stock ou les dettes locales.

## Licences et attribution

Le code de cette application a été écrit pour ce projet. Les données Open Food
Facts et Open Products Facts sont ouvertes sous ODbL et affichées avec leur
attribution dans l'écran À propos. Voir [docs/CATALOG.md](docs/CATALOG.md).

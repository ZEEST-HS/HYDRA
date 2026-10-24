# Hydra POS

Application Flutter de caisse et de gestion de boutique pour le commerce de
proximité marocain. Conçue pour Android, prioritairement pour des téléphones
d'entrée de gamme, avec interface **arabe (RTL)** et **français (LTR)**,
montants en **MAD (DH)** et fonctionnement **100 % hors ligne**.

## Fonctionnalités

- **Premier lancement** : accueil arabe, présentation des fonctions, choix du
  type de commerce et de la langue ; rejouable depuis les réglages.
- **Deux profils** : `محل تجاري صغير` (navigation simplifiée) et
  `سوبر ماركت` (navigation complète), sur la même base de données.
- **Classification** : deux divisions (الأكل / غير الأكل), 16 sous-catégories
  prédéfinies et gestion sûre des catégories personnalisées.
- **Caisse tactile** : recherche produit, scan caméra ou douchette,
  multiplicateur de quantité, conditionnements, remise, paiement comptant,
  partiel ou crédit, rendu de monnaie, reçu et facture PDF.
- **Produits** : prix d'achat/vente, stock, seuil d'alerte, code-barres,
  fournisseur, unités et prix par conditionnement, archivage.
- **Lots et péremptions** : plusieurs lots par produit, numéro et date
  facultatifs, alerte configurable (30 jours par défaut), vente FEFO, retours
  vers le lot d'origine, mise au rebut avec motif et journal d'audit.
- **Achats** : fournisseur, coût moyen pondéré, paiement partiel, annulation,
  lot et péremption par ligne, bon PDF/CSV.
- **Stock** : mouvements justifiés, ajustements compatibles avec les lots,
  inventaire par session, vues des produits périmés, proches ou sans date.
- **Clients et fournisseurs** : soldes, règlements, grand livre.
- **Finance** : dépenses, sessions de caisse, rapprochement des espèces,
  rapports et graphiques, exports CSV/XLSX.
- **Exploitation** : sauvegarde/restauration locale, import CSV/XLSX, journal
  d'audit, catalogues Open Food Facts / Open Products Facts avec cache.
- **Thèmes** : clair, sombre ou système, persistés, avec contrastes vérifiés.

## Structure du dépôt

```text
android/              projet Android natif (Gradle, manifestes, ressources)
assets/               polices Noto Sans et Noto Sans Arabic
docs/                 architecture, base de données, impression, tests, statut
lib/
  app/                démarrage, contrôleur, navigation
  core/               monnaie, quantités, dates, erreurs, SQLite, L10n
  data/               modèles et dépôts SQLite
  domain/             ventes, achats, retours, caisse, rapports, sauvegarde
  features/           écrans par domaine
  integrations/       fournisseurs de catalogues externes
  services/           PDF, impression, import/export, partage
  ui/                 thème et composants partagés
test/                 tests unitaires, dépôts, services et widgets
analysis_options.yaml configuration d'analyse statique
pubspec.yaml          dépendances et métadonnées du projet
```

Les dossiers générés (`build/`, `.dart_tool/`, `.gradle/`) et les secrets
Android (`local.properties`, `key.properties`, keystores) ne sont pas versionnés.

## Prérequis

- Flutter stable (testé avec Flutter 3.47.7 / Dart 3.13.5)
- JDK 17
- Android SDK (minSdk 24, targetSdk 36)

Sous Windows, l'environnement utilisé pendant le développement :

```powershell
$env:Path = "C:\src\flutter\bin;$env:Path"
$env:JAVA_HOME = "C:\src\jdk\jdk-17.0.20.1+1"
$env:ANDROID_HOME = "C:\src\android-sdk"
```

## Démarrage

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

## Build Android

```powershell
flutter build apk --release --dart-define=use_arabic=true
```

L'APK est produit dans `build/app/outputs/flutter-apk/app-release.apk`.

`use_arabic=true` embarque les polices arabes dans les PDF. Sans ce drapeau,
l'interface arabe reste correcte mais les noms arabes des PDF peuvent apparaître
avec des lettres non liées.

## Vérifications

- `flutter analyze` : aucun problème.
- `flutter test` : 132 tests réussis (monnaie, lots/FEFO, migrations v1→v3 et
  v2→v3, services, impression, PDF, thème, widgets 360 × 640 en arabe sombre).

Détail et checklist manuelle : [`docs/TESTING.md`](docs/TESTING.md).

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Base de données](docs/DATABASE.md)
- [Catalogues externes](docs/CATALOG.md)
- [Impression et PDF](docs/PRINTING.md)
- [Tests](docs/TESTING.md)
- [État du projet](docs/STATUS.md)
- [Guide utilisateur](docs/USER_GUIDE.md)
- [Audit de la phase 1](docs/PHASE1_AUDIT.md)

## Version publiée

`v1.0.0` — voir la page des releases du dépôt. L'APK joint est signé avec la
clé debug Android : il sert aux essais, pas à une publication sur un store.

## Licence

Distribué sous licence MIT. Voir [`LICENSE`](LICENSE).

Le code de référence utilisé pendant l'audit initial n'est pas inclus dans ce
dépôt et reste soumis à sa propre licence.

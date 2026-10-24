# Catalogues externes

## Sources

- **Open Food Facts** : `https://world.openfoodfacts.org/api/v3/product/<code>.json`
- **Open Products Facts** : même API v3 sur
  `https://world.openproductsfacts.org`.

Seuls des champs utiles sont demandés : code, noms FR/générique/AR, marques,
quantité, catégories et images. Les données sont ouvertes sous **ODbL** ;
l'attribution est affichée dans l'écran À propos et dans
`docs/ARCHITECTURE.md`. Aucune clé API ni compte n'est nécessaire.

## Flux d'utilisation

1. L'écran cherche d'abord dans la base locale (nom, code-barres, catégorie).
2. Si aucun produit local ne correspond, l'utilisateur peut lancer une
   recherche externe depuis la fiche produit ou la caisse.
3. `CatalogService` consulte le cache, puis les fournisseurs dans l'ordre
   Open Food Facts → Open Products Facts.
4. Le résultat est proposé comme **brouillon** : nom, marque, quantité,
   catégorie et image peuvent être préremplis.
5. L'utilisateur garde la main sur le prix, le coût, le stock, le fournisseur
   et les unités. **Aucun prix, stock, dette ou historique local n'est écrasé.**

La saisie manuelle reste toujours disponible, y compris hors ligne.

## Cache et réseau

- Résultat trouvé : cache valide **30 jours**.
- Résultat absent : cache négatif valide **7 jours**.
- Les appels réseau sont espacés d'au moins **900 ms**.
- Délai HTTP de 9 secondes par fournisseur.
- Si le réseau échoue, un résultat en cache, même expiré, peut être affiché
  avec un indicateur hors ligne.
- Le cache est stocké dans `catalog_cache` et peut être vidé depuis les
  réglages.

## Confidentialité

La seule donnée envoyée est le code-barres recherché, avec un User-Agent
identifiant l'application. Aucun nom de client, montant, stock ou coordonnée de
boutique n'est transmis.

## Couverture vérifiée

Des tests manuels effectués pendant le développement ont trouvé 5 codes-barres
de produits marocains courants (Sidi Ali, Aicha) sur 5 dans Open Food Facts.
Le code `6111245100059` renvoyait une absence (404), correctement traitée comme
« non trouvé ». La couverture d'Open Products Facts est plus sparse ; il est
donc évalué mais ne peut pas être garanti pour tous les produits.

Ces vérifications datent du développement et dépendent de la base communautaire
au moment de l'appel. L'application ne promet pas qu'un produit donné existe.

## Limites

- Les noms et quantités peuvent être incomplets ou dans une autre langue.
- Les images distantes nécessitent Internet ; aucune image n'est intégrée au
  produit sans action de l'utilisateur.
- Le catalogue externe ne remplace pas une fiche locale et ne sert jamais de
  source de vérité pour l'argent ou le stock.

# Guide utilisateur

Ce guide décrit l'utilisation quotidienne de Hydra POS dans une boutique de
proximité. L'application fonctionne sans Internet ; seuls les catalogues
externes et le partage de fichiers utilisent le réseau.

## Première ouverture

1. Ouvrir l'application.
2. Aller dans **Plus → Réglages** (ou **المزيد → الإعدادات**) pour saisir le
   nom de la boutique, l'adresse, le téléphone et le pied de page.
3. Choisir la langue : français ou arabe. L'interface passe immédiatement en
   sens de lecture correspondant.
4. Vérifier la politique de stock :
   - **Bloquer** : interdire une vente qui rend le stock négatif ;
   - **Confirmer** : demander avant de continuer ;
   - **Autoriser** : laisser le stock devenir négatif.

## Ajouter des produits

1. Onglet **Produits → +**.
2. Saisir le nom (obligatoire), le prix de vente, le coût, le stock initial et
   éventuellement le code-barres.
3. Pour vendre par paquet ou carton, ajouter une unité avec son facteur
   (exemple : carton = 12 pièces) et, si besoin, un prix spécifique.
4. Le bouton de scan permet de remplir le code-barres à la caméra.
5. Si le produit n'existe pas localement, le bouton catalogue peut rechercher
   Open Food Facts / Open Products Facts. Les champs proposés restent
   modifiables ; le prix et le stock locaux ne sont jamais écrasés.

## Vendre

1. Onglet **Caisse**.
2. Saisir un nom/code-barres, scanner avec la caméra ou la douchette.
3. Pour ajouter plusieurs exemplaires d'un coup, choisir `10×` avant le scan.
4. Choisir l'unité de vente si le produit a plusieurs conditionnements.
5. Vérifier le panier, appliquer une remise si nécessaire.
6. Appuyer sur le bouton d'encaissement :
   - choisir le client (obligatoire si un crédit reste dû) ;
   - saisir le montant payé et le mode (espèces, carte, crédit) ;
   - valider. La monnaie à rendre est affichée.
7. Le reçu peut être imprimé en Bluetooth ou partagé en PDF.

Un scan répété très rapidement du même code est ignoré pour éviter les doublons.
Le multiplicateur se remet à `1×` après la vente.

## Encaisser un crédit client

1. **Plus → Clients**, ouvrir le client.
2. Le solde dû est affiché. Appuyer sur **Régler**.
3. Saisir le montant et le mode de paiement. Le solde et le grand livre sont
   mis à jour.

## Achats et fournisseurs

1. **Plus → Achats → +**.
2. Choisir ou créer le fournisseur.
3. Scanner ou rechercher les produits, ajuster quantité, coût, unité et date de
   péremption.
4. Le paiement est prérempli au total ; il peut être réduit pour un achat à
   crédit.
5. Valider : le stock augmente, le coût moyen pondéré est recalculé et le solde
   fournisseur est mis à jour.
6. Dans le détail d'un achat, il est possible d'ajouter un paiement partiel,
   d'imprimer le bon ou d'annuler l'achat avec un motif.

## Retours et annulations

- **Retour** : depuis une vente, choisir les quantités retournées. Le stock est
  remis et le remboursement est enregistré. Un remboursement en espèces est
  refusé si la vente a encore une dette ; utiliser alors un avoir client.
- **Annulation d'une vente** : réservée aux erreurs, avec motif. La vente reste
  dans l'historique avec le statut annulé ; le stock et les soldes sont
  compensés.
- **Annulation d'un achat** : même principe, sans réécrire l'historique des
  coûts déjà utilisés.

## Stock et inventaire

- **Plus → Stock** : rechercher un produit, filtrer les stocks bas, ajuster une
  quantité avec un motif.
- **Péremptions** : lots dont la date approche, selon le délai configuré.
- **Inventaire** : démarrer une session, saisir les quantités comptées, puis
  valider. Seuls les écarts sont enregistrés comme mouvements.
- **Journal** : historique des entrées, sorties, ventes, achats, retours et
  ajustements.

## Caisse et dépenses

1. **Plus → Caisse** : saisir le fond de caisse à l'ouverture.
2. En fin de journée, compter les espèces et saisir le montant compté.
3. L'application affiche l'attendu, le compté et la différence, puis clôture la
   session.
4. **Plus → Dépenses** permet d'enregistrer une sortie d'argent avec catégorie,
   mode et note.

Le montant attendu tient compte des ventes espèces, règlements clients,
paiements fournisseurs, remboursements, dépenses et annulations.

## Rapports

**Plus → Rapports** permet de choisir une période et d'afficher :

- chiffre d'affaires, retours, marge brute estimée, dépenses, résultat net ;
- encaissements et crédits ;
- graphique du chiffre d'affaires ;
- meilleurs produits ;
- répartition par mode de paiement et par dépense.

Les exports CSV/XLSX sont disponibles depuis les écrans Rapports, Ventes et
Achats. Les marges sont des estimations basées sur le coût moyen ; elles ne
remplacent pas une comptabilité officielle.

## Sauvegarde et restauration

1. **Plus → Sauvegarde**.
2. **Créer une sauvegarde** copie la base dans le dossier de l'application.
3. Une sauvegarde peut être partagée (WhatsApp, drive personnel, câble) ou
   supprimée.
4. **Restaurer** remplace toutes les données actuelles. L'application vérifie
   le fichier avant de continuer. Faire une sauvegarde avant toute restauration.

## Import et export

**Plus → Import / Export** :

- importer des produits depuis un CSV ou XLSX ;
- télécharger un modèle ;
- choisir explicitement si le stock existant doit être mis à jour ;
- exporter les produits, ventes, achats et dettes.

Un import n'écrase pas silencieusement les prix ou le stock : les options sont
visibles avant validation.

## Imprimante

1. Appairer l'imprimante Bluetooth dans les réglages Android.
2. **Plus → Imprimante** : sélectionner l'appareil, la largeur (58/80 mm),
   activer ou non l'impression automatique.
3. Envoyer un ticket de test.
4. En cas d'échec, utiliser le PDF : il est toujours proposé.

L'impression thermique est en ASCII : les accents et l'arabe peuvent être
simplifiés sur le ticket. Le PDF conserve mieux les textes.

## Journal d'audit

**Plus → Audit** liste les actions sensibles avec leur date, leur motif et leur
détail. Il permet de retrouver qui a annulé, supprimé ou ajusté une donnée.

## Bonnes pratiques

- Sauvegarder régulièrement, surtout avant une restauration ou une mise à jour.
- Ne pas supprimer un produit utilisé dans l'historique : le désactiver.
- Vérifier le comptage de caisse avant de clôturer.
- Utiliser des motifs clairs pour les annulations et ajustements.
- Tester l'imprimante et le scan caméra sur le téléphone de la boutique avant
  la mise en service.

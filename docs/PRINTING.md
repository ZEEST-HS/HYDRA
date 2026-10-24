# Impression et PDF

## Deux canaux

1. **Imprimante thermique Bluetooth ESC/POS** pour le reçu de caisse et le test
   d'imprimante.
2. **PDF** (A4 ou reçu) partagé via le système Android, pour l'archivage,
   l'envoi WhatsApp/e-mail ou une imprimante non ESC/POS.

L'interface propose toujours le PDF, même quand une imprimante Bluetooth est
configurée.

## ESC/POS

`lib/services/print_service.dart` construit les octets ESC/POS :

- initialisation, alignement, double hauteur/largeur, coupe papier ;
- en-tête boutique (nom, téléphone, adresse), numéro de facture, date ;
- lignes produit : quantité affichée, unité, prix, total ;
- sous-total, remise, total, payé, reste dû, retours ;
- pied de page et mention Hydra POS.

Le contenu est **ASCII uniquement**. Les caractères accentués français et
l'arabe sont volontairement translittérés ou remplacés afin d'éviter des
octets illisibles sur les imprimantes à page de code. Les noms arabes sans nom
français sont remplacés par un texte lisible.

L'impression utilise `print_bluetooth_thermal` avec les permissions Bluetooth
déclarées dans le manifeste Android. L'écran Imprimante permet de choisir un
appareil apparié, la largeur (58/80 mm), l'impression automatique après vente
et d'envoyer un ticket de test.

## PDF

`lib/services/invoice_pdf_service.dart` produit :

- **facture de vente A4** avec en-tête boutique, client, lignes, totaux,
  paiements, retours et pied de page ;
- **reçu étroit** (largeur papier configurable) ;
- **bon d'achat A4** avec le fournisseur et les lignes d'achat.

Polices embarquées :

- `assets/fonts/NotoSans-Regular.ttf` pour le latin ;
- `assets/fonts/NotoSansArabic-Regular.ttf` et
  `assets/fonts/NotoSansArabic-Bold.ttf` pour l'arabe (SIL Open Font License,
  voir `assets/fonts/OFL.txt`).

L'activation du moteur de rendu arabe de `pdf` se fait à la compilation :

```powershell
flutter build apk --release --dart-define=use_arabic=true
```

Sans ce drapeau, le PDF reste correct en français ; les noms arabes peuvent
perdre leurs ligatures. C'est une limite du moteur, pas une erreur de données.

## Partage

`share_plus` et `printing` permettent d'ouvrir la feuille de partage Android ou
l'aperçu d'impression système. Les fichiers PDF sont générés en mémoire puis
partagés ; aucun serveur n'intervient.

## État de validation

- Génération des octets ESC/POS : testée par tests unitaires.
- Génération PDF : testée (facture A4 et reçu arabe, chargement réel des
  polices), mais la vérification visuelle des ligatures arabes sur un appareil
  reste à faire.
- Impression Bluetooth réelle : **non testée**, faute d'imprimante physique et
  de téléphone Android disponibles.
- Aucune imprimante réseau, USB ou Sunmi n'est prise en charge.

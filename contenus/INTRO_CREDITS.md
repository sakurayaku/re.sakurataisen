# Crédits du jeu

**Fichiers concernés:**
- `SAKURA1/LOGO.SH2/INTRO_CREDITS/CREDITS.bmp` 
- `SAKURA1/LOGO.SH2/INTRO_CREDITS/LOGO.bmp`

La palette BMP des étiquettes a été adaptée pour permettre l'édition, mais le jeu emploie ses propres palettes: une noire, partagée avec les dialogues.

> [!CAUTION]
> Le blanc est employé comme couleur de la transparence pour conserver l'anti-aliasing du texte lors de la conversion en fichiers .bmp par GIMP. De plus, la toute dernière couleur de la palette est un rouge criard: ce n'est PAS un accident, et elle n'est PAS transparente: c'est une limite de GIMP qui interprète la palette comme "grayscale" si elle ne contient pas au moins une "couleur colorée", et cela impactait la réinsertion.

## Description

Ces images correspondent aux logos affichés lors du lancement du jeu, juste après le logo SEGA.

Comme pour [les options](./OPTIONS.md), le codec produit une image complète de l'écran avec les tiles jointes, et à la réinsertion, les tuiles seront dé-dupliquées et unifiées, puis réordonnées en instruction de dessin à l'écran.

En pratique, ça rentre, mais il faudra sûrement un peu tricher avec les alignements de `8px` et les tuiles de `8x8px` pour diminuer le nombre de tuiles uniques.

Le budget total après compression PRS est de `916 octets`.

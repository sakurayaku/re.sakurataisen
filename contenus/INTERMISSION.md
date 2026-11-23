# Écran d'intermission

**Codecs:**
```
SakTaiCD1_Track1.bin
├── SAKURA
│   ├── [decode] META_INTERMISSION - scripts/intermission_screen_metadata.lua
│   └── [decode] META_STATUS — scripts/SAKURA/status_screen_metadata.lua
└── SAKURA1
    └── ICATALL.DAT
        ├── [decode] INTERMISSION — scripts/intermission_screen_gfx.lua
        └── [decode] STATUS_SCREEN — scripts/status_screen_gfx.lua
```

**Fichiers concernés:**
- `SAKURA1/ICATALL.DAT/INTERMISSION_LABELS.bmp`: Trois étiquettes de choix
- `SAKURA1/ICATALL.DAT/STATUS_BG.bmp`: Cartouches de fond des status.
- `SAKURA1/ICATALL.DAT/STATUS_NAMES.bmp`: Les étiquettes des noms des filles.
- `SAKURA1/ICATALL.DAT/STATUS_MOODS.bmp`: Les étiquettes des humeurs possibles.
- `SAKURA1/ICATALL.DAT/STATUS_STATS.bmp`: Les stats des filles.
- `SAKURA1/ICATALL.DAT/STATUS_DIGITS.bmp`: Les chiffres.

La palette des étiquettes de choix est celle des dialogues ADV du jeu. Vous ne pouvez pas la modifier.

> [!CAUTION]
> Sur les étiquettes, le blanc est employé comme couleur de la transparence pour conserver l'anti-aliasing du texte lors de la conversion en fichiers .bmp par GIMP. De plus, la toute dernière couleur de la palette est un rouge criard: ce n'est PAS un accident, et elle n'est PAS transparente: c'est une limite de GIMP qui interprète la palette comme "grayscale" si elle ne contient pas au moins une "couleur colorée", et cela impactait la réinsertion.

## Description

L'écran se sépare en deux parties: le menu d'intermission, et le sous-menu de stats.

### Menu d'intermission

En fin d'épisode, et de temps en temps au cours d'un épisode, le joueur a droit à un écran d'intermission ([eye-catch](https://fr.wikipedia.org/wiki/Eyecatch)?) qui l'invite à sauvegarder et voir l'état de son équipe. En japonais, les trois choix sont:
- `セーブする` - Sauvegarder
- `隊員の状況` - Stats de l'équipe
- `ゲームを再開` - Continuer le jeu

Pour le budget, c'est UN PEU complexe: le jeu original employait un atlas de glyphs uniques de `16x16px` (un par glyph), les dé-dupliquait, et utilisait des commandes de draw pour les afficher une à une, ce qui renvoyait à des contraintes pas très pratiques pour du texte non-aligné.

Donc, le codec transforme ça: chaque ligne est considérée comme UN sprite, aligné sur `8px` (la taille minimale des sprites Saturn), et une seule commande suffit à l'afficher centrée. Le codec gère tout ça.

Donc, pour les budgets:
- Vous devez conserver les dimensions (et la palette 16 couleurs) du BMP: `96px` de large, et trois fois `16px` de haut.
- Le jeu rogne les blocks de `8x16px` transparents aux extrémités, donc vos labels seront centrés. Vous ne pouvez pas les aligner à gauche.
- Vous n'avez droit d'occuper que TRENTE-DEUX blocks de `8x16px`, c'est-à-dire que votre dessin final doit avoir AU MOINS quatre blocks de `8x16px` transparents sur les extrémités gauche et droite. Si vous êtes sur GIMP, utilisez une grille de `8x16px`, vous verrez immédiatement les 4 blocks libres de l'original, puis regarde la version FR, et vous comprendrez.
- Un block de `8x16px` transparent au milieu d'un mot sera considéré comme "occupé".
- Malgré ça, une fois [compressé en PRS](https://segaretro.org/PRS_compression), votre image ne doit pas dépasser les `966 bytes`. En théorie, avec tous les pixels transparents, et si vous n'êtes pas gourmand, ça passe.
- Enfin, le plus vrai limiteur, qui explique la limite de blocks: la [VRAM](https://fr.wikipedia.org/wiki/M%C3%A9moire_vid%C3%A9o). On PEUT agrandir le budget, mais rien ne prouve qu'on ne va pas foutre en l'air d'autres sprites de la scène. Bref, le budget total est de `2048 octets`.

### Menu de stats

Pour le budget, `STATUS_BG` a son propre budget. Toutes les autres étiquettes de textes ont un budget commun un peu plus complexe:
- d'abord, tout est décomposé en tuiles uniques de `16x16px` qui forment un atlas
- cet atlas doit contenir moins de 96 tuiles uniques (la limite _retail_  est de 48, mais grimper à 96 ne pète pas le jeu dans les tests).
- cet atlas doit avoir un budget de `2 522 octets` une fois [compressé en PRS](https://segaretro.org/PRS_compression).
- la liste de glyphe (voir [la doc de l'écran de sauvegarde](./LOAD_SCREEN.md) pour comprendre) est limitée à `140 octets`.

Originellement, le jeu encodait les glyphs sur `2 octets`. Un patch ASM a été appliqué pour qu'ils soient stockés (et lus) sur `1 octet`, permettant donc de grimper leur limite à 140 glyphes (la retail était limitée à 70 glyphes).

#### STATUS_BG

Ces six cartouches correspondent aux six filles et leurs nom/humeur/stats s'afficheront là-dedans. La team US a déjà géré l'adaptation avec des chiffres romains, donc on réutilise leur boulot.

Vous pouvez modifier, mais:
- ne changez pas les dimensions.
- ne changez pas la palette (on POURRAIT la réinsérer modifiée, mais elle peut être employée ailleurs, donc pas touche).
- le budget total est de `21 967 octets` une fois [compressé en PRS](https://segaretro.org/PRS_compression).

#### STATUS_GIRLS

Six rangées de `16px` de haut et `64px` de large. Chaque ligne est le nom d'une des filles.

#### STATUS_MOODS

Trois rangées de `32px` de haut et `64px` de large. Chaque étiquette est une humeur.

#### STATUS_STATS

Trois rangées de `16px`de haut et `32px` de large. Chaque étiquette est une stat.

#### STATUS_DIGITS

Dix rangées de `16px`de haut et `16px` de large. Les chiffres de 0 à 9.
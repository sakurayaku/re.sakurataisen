# Écran d'intermission

**Codecs:**
```
SakTaiCD1_Track1.bin
├── SAKURA
│   └── META_INTERMISSION — scripts/intermission_screen_metadata.lua
└── SAKURA1
    └── ICATALL.DAT
        └── INTERMISSION — scripts/intermission_screen_gfx.lua
```

**Fichiers concernés:**
- `SAKURA1/ICATALL.DAT/INTERMISSION_LABELS.bmp`: Trois étiquettes de choix

La palette des étiquettes de choix est celle des dialogues ADV du jeu. Vous ne pouvez pas la modifier.

> [!CAUTION]
> Sur les étiquettes, le blanc est employé comme couleur de la transparence pour conserver l'anti-aliasing du texte lors de la conversion en fichiers .bmp par GIMP. De plus, la toute dernière couleur de la palette est un rouge criard: ce n'est PAS un accident, et elle n'est PAS transparente: c'est une limite de GIMP qui interprète la palette comme "grayscale" si elle ne contient pas au moins une "couleur colorée", et cela impactait la réinsertion.

## Description

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

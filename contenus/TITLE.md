# Écrans de titres des épisodes

**Codecs:**
```
SakTaiCD1_Track1.bin
└── SAKURA1
│   ├── LOAD.BIN
│   │   └── [decode] LOAD — scripts/title.lua
    ├── TITLE1.BIN
    │   └── [decode] TITLE - scripts/title.lua
    ├── (...)
    ├── TITLE9.BIN
    │   └── [decode] TITLE - scripts/title.lua
    └── TITLE10.BIN
        └── [decode] TITLE - scripts/title.lua
```

**Fichiers concernés:**
- `SAKURA1/LOAD.BIN/LOAD.bmp` pour l'écran de chargement des données
- `SAKURA1/TITLE{nn}.BIN/TITLE.bmp` où `nn` est un nombre entier de `1` à `10`, sans zéro initial.
  Des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés sans transparence.

## Description

Ces images correspondent aux écrans de titre des dix épisodes du jeu. L'équipe US a produit [des versions redessinées sans les textes originaux](https://github.com/NoahSteam/RomHackingTools/tree/master/SakuraTaisen/Data/SourceArt/FromJoqu/Titleimages).

Le même codec s'applique aussi à l'écran de chargement des données du jeu, `LOAD.BIN`. Pour le redessiner à l'horizontale, le background utilisé est [celui produit par MatyMeatBoy pour le projet SaturnTaisen](https://github.com/MatyMeatBoy/SaturnTaisen/blob/main/assets/generated/screen-backgrounds/LOADING-v1.png) sous [license GPL-3.0](/workspace/SakTaiCD1_Track1.bin/SAKURA1/LOAD.BIN/LICENSE).

## Contraintes d'édition

- L'image doit faire `320x224px`
- Vous pouvez modifier les couleurs de la palette.

L'encodeur valide explicitement ces règles avant d'insérer l'image.

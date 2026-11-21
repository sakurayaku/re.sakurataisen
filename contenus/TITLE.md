# Écrans de titres des épisodes

**Codecs:**
```
SakTaiCD1_Track1.bin
└── SAKURA1
    ├── TITLE1.BIN
    │   └── [decode] TITLE.bmp - scripts/title.lua
    ├── (...)
    ├── TITLE9.BIN
    │   └── [decode] TITLE.bmp - scripts/title.lua
    └── TITLE10.BIN
        └── [decode] TITLE.bmp - scripts/title.lua
```

**Fichiers concernés:**
- `SAKURA1/TITLE{nn}.BIN/TITLE.BMP` où `nn` est un nombre entier de `1` à `10`, sans zéro initial.
  Des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés sans transparence.

## Description

Ces images correspondent aux écrans de titre des dix épisodes du jeu. L'équipe US a produit [des versions redessinées sans les textes originaux](https://github.com/NoahSteam/RomHackingTools/tree/master/SakuraTaisen/Data/SourceArt/FromJoqu/Titleimages).

## Contraintes d'édition

- L'image doit faire `320x224px`.
- Vous pouvez modifier les couleurs de la palette.

L'encodeur valide explicitement ces règles avant d'insérer l'image.

# Cartouches des menus de combats

**Codecs:**
```
SakTaiCD1_Track1.bin
└── SAKURA2
    ├── 0SLG.BIN
    │   └── [decode] combat_commands — scripts/combat_commands_metadata.lua
    ├── SLG.BIN
    │   └── [decode] combat_commands — scripts/combat_commands_metadata.lua
    ├── WKL01.BIN
    │   └── [decode] COMBAT — scripts/combat_commands_gfx.lua
    ├── (etc..)
    │   └── [decode] COMBAT — scripts/combat_commands_gfx.lua
    └── WKL22.BIN
        └── [decode] COMBAT — scripts/combat_commands_gfx.lua
```

**Fichiers concernés:**
- `workspace/combat/commands/*.bmp`
- `workspace/combat/names/*.bmp`

Les images sont tous des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés. La couleur d'index 0 (le bleu-vert) indique la transparence. Tout le reste sera visible.

> [!CAUTION]
> La palette n'est PAS modifiable, ou alors faudra partir du principe que ça sera la MÊME pour TOUTES les images.

## Description

Ces images contiennent TOUS les éléments graphiques liés au système de combat: commandes, noms des persos, des ennemis, des attaques,... Ils sont extraits de TOUS les fichiers `SAKURA2/WKL{nn}.BIN`, qui représentent chacun un combat différent. Ces archives se composent de deux morceaux:

- les commandes de combat, qui sont les éléments de menu commun à TOUS les fichiers `WKL{nn}`.
- les cartouches de noms, qui sont spécifiques à chaque fichier mais peuvent être partagés (genre `Ôgami` et `Sakura` sont partout, mais pas le boss final).

Vu qu'elles sont partagées, et pour éviter d'avoir à gérer plusieurs copies, etc... Tout est dans `workspace/combat`.

### Commandes de combat (combat)

Toutes dans `workspace/combat`. Pour faciliter le boulot, beaucoup d'images ont été "réunies" en une seule, et l'insertion fera le découpage. De plus, sauf si expressément indiqué, on supporte (un certain niveau) de redimensionnement.

#### CMD_MAIN.bmp

Les commandes de combat principales, en deux colonnes (active et inactive[^inactive]), et six rangées. Vous pouvez agrandir (mais les ennuis viennent plus tard), et le codec découpera automatique des morceaux de `(largeur / 2)x(hauteur / 6)px`.

#### CMD_NAMES.bmp

Les sous-commandes. Même principe que précédemment: 2 colonnes (active et inactive[^inactive]), et douze rangées. Vous pouvez agrandir (mais les ennuis viennent plus tard), et le codec découpera automatique des morceaux de `(largeur / 2)x(hauteur / 12)px`.

#### MAIN_MENU_GIRLS.bmp & MAIN_MENU_OGAMI.bmp

Le cartouche sur lequel sont dessinées les commandes de combat. Vous devez l'agrandir si vous agrandissez les commandes principales.

> [!NOTE]
> Même si le jeu dispose d'une protection pour éviter que le menu se dessine hors de l'écran, le jeu original a un "bug": le menu de commande d'Ôgami étant plus long, il n'a pas cette protection. Même si le codec adapte cette protection à la longueur du menu des filles, j'ai conservé ce comportement au lieu de rajouter encore du déplacement pour pallier au problème du menu d'Ôgami.

#### SUBMENU

Les cartouches dans lesquelles seront dessinées les sous-commandes de combat. Bien évidemment, si vous voulez agrandir les noms, il faudra agrandir ces cartouches aussi.

Accessoirement: ils doivent faire la même longueur (duh!) car leur longueur est utilisée pour calculer où sera positionné le compteur d'utilisations des commandes "Réparer" et "Couvrir".

#### UNIT_INFO.bmp

L'écran d'info qui apparaît au survol des unités. Redimensionnable.

#### UNIT_STATUT.bmp

L'écran de statut complet des unités. Redimensionnable, mais tous les éléments que le jeu dessine dessus iront à leur place originale.

#### MENU_START

Le menu qui apparaît quand vous appuyez sur `START` en pleine partie. Le `HOVER.bmp` est chelou, mais en réalité, c'est juste une image qui alterne plusieurs palettes pour donner une illusion d'animation.

> [!CAUTION]
> Vous pouvez redimensionner, mais ils se retrouveront dé-centrés. Pas encore prévu de les repositionner.

#### MENU_CONFIRM

Le menu de confirmation qui apparaît lorsque vous sélectionner "Recommencer" sur le `MENU_START`. Il y a aussi un label `02_QUIT` que je n'ai jamais vu employé en jeu.  Vous pouvez redimensionner, et même repositionner, en modifiant le fichier `MENU_CONFIRM.json`.

> [!NOTE]
> Les positions `x` et `y` sont toutes indiquées par rapport au centre de l'écran, d'où les valeurs négatives.

#### MENU_GAMEOVER

Le menu de `Game Over`. Rien à dire.

> [!CAUTION]
> Vous pouvez redimensionner, mais ils se retrouveront dé-centrés. Pas encore prévu de les repositionner.

#### Les autres fichiers

Ils sont extraits et n'ont pas forcément besoin d'être touchés. Soit ils ont un nom car ils ont été identifiés, soit ils ont des noms genre `command_{xx}_{yy}.bmp`. Aucune idée d'à quoi ceux-là servent. En théorie, vous n'avez aucune raison d'y toucher.

### Cartouches de noms (names)

Vu que chaque fichier a sa liste de fichiers, un choix a été fait:
- lors d'un build, le codec fait un hash SHA256 du fichier original.
- il cherche `workspace/names/{hash}.bmp`, et le créée s'il n'existe pas.
- si vous identifiez le fichier, il y a une table de hachage dans le codec pour donner au fichier un nom "identifiable".

J'ai identifié quelques types, et pour le moment, à moins de plus de hacks assembleur, ils sont pas modifiables

#### NAME_CHAR & NAME_ENEMY

Fichiers de `40x16px`. Les noms de personnages, qui apparaissent par-dessus `UNIT_INFO`.

#### NAME_UNIT

Fichiers de `48x16px`. Les noms des robots, tels qu'ils apparaissent tout en haut de `UNIT_STATUS`.

#### SUPER

Fichiers de `88x16px`. Les noms des super attaque, tels qu'ils apparaissent tout en bas de `UNIT_STATUS`.


## Le budget

Alors. C'est complexe. Il y a le budget commun des `commands` et le budget (spécifique à chaque fichier) des `names` (qui, sont spécifique à chaque fichier)...

- Pour `commands`, c'est `190 208 octets`, soit `380 416 pixels` au total. Le codec vérifie.
- Pour `names`, c'est une section [compressée en PRS](https://segaretro.org/PRS_compression), pas de budget identifié. Soyez vigilant, ou vous pétez la [VRAM](https://fr.wikipedia.org/wiki/M%C3%A9moire_vid%C3%A9o).

***
[^inactive]: Oui, certaines commandes n'ont PAS de version inactive, j'ai juste voulu garder l'alignement.

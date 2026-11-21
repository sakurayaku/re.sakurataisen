# Logo d'introduction

**Codecs:**
```
SakTaiCD1_Track1.bin
└── SAKURA1
    └── LOGO.SH2
        └── [decode] INTRO_LOGO — scripts/intro_logo_gfx.lua
```

**Fichiers concernés:**
- `SAKURA1/LOGO.SH2/INTRO_LOGO/SWIRL.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/BACKDROP.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/EMBLEM.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/SAKURA.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/TAI.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/SEN.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/MARK.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/CAPTION.bmp`
- `SAKURA1/LOGO.SH2/INTRO_LOGO/LAYOUT.csv`

Les huit images sont des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés. La couleur d'index 0 (un rouge sombre) indique la transparence. Tout le reste sera visible. `LAYOUT.csv` est décrit plus bas.

> [!CAUTION]
> La palette n'est PAS modifiable. Les cinq palettes du fichier (à `0x28F24`) sont recopiées telles quelles, et l'encodeur refuse toute image dont l'en-tête BMP ne correspond pas à celle que le jeu emploie (`0x29124`). La comparaison se fait en 5 bits, donc un simple ré-enregistrement par GIMP est accepté, mais un changement de couleur est une erreur.

## Description

Ces images composent l'écran du logo, celui qui arrive sur le menu principal. Elles sont stockées de **deux** façons différentes, et il faut le savoir avant de les éditer.

### Les décorations

Les fichiers `BACKDROP.bmp`, `EMBLEM.bmp`, et `CAPTION.bmp` correspondent aux éléments qui composent cet écran. Vous pouvez les modifier tant que vous respectez leurs palettes ET leurs dimensions. Il ne fonctionnent PAS par tuiles, mais partagent leur compression avec les autres glyphes, donc soyez vigilant. 

Leurs dimensions sont les suivantes:

| Image | Dimensions | Contenu |
| --- | --- | --- |
| `BACKDROP.bmp` | `112x136px` | la carte, le cadre, les pétales, la plaque de légende et le « TM » |
| `EMBLEM.bmp` | `96x96px` | le disque 帝撃 |
| `CAPTION.bmp` | `160x24px` | la bande de légende |

### Les éléments de texte (Sakura, Tai, Sen, et fleur de cerisier)

Le jeu décompose les éléments textuels en trois morceaux: `サクラ` (Sakura), `大` (Tai), et `戦` (Sen), et une fleur de cerisier (stockée dans `MARK.bmp`).

Pour les trois éléments textuels, chaque fichier contient trois copies: deux silhouettes (qui flasheront selon les palettes du jeu), et l'élément coloré final. Ainsi, `SAKURA.bmp` se compose de trois bandes empilées (`56x456`) en japonais, ou `152x168` en version US (trois bandes de `152x56`).

Les dimensions doivent être conservées afin d'assurer la continuité des bytes: MÊME si votre `SEN.bmp` est vide, ses bytes doivent être présents dans le block PRS pour ne de pas déplacer les autres éléments visuels.

| Image | Dimensions | Contenu |
| --- | --- | --- |
| `SAKURA.bmp` | `56x456` | サクラ en trois états (voir plus bas) |
| `TAI.bmp` | `64x216` | 大: silhouette, silhouette, couleur |
| `SEN.bmp` | `64x240` | 戦: silhouette, silhouette, couleur |
| `MARK.bmp` | `24x24` | la fleur de cerisier |

### Le "Sakura" qui se déplace (`SWIRL.bmp`)

`SWIRL.bmp` est le mot « Sakura » qui traverse l'écran. Il ne s'agit PAS d'une image linéaire: c'est une banque de 92 tuiles de `8x8px` réutilisées par une carte de 133 cellules, qui forme une grille de `19x7` cellules, soit `152x56px`. L'encodeur dé-tuile l'image, re-numérote les tuiles si deux cellules qui partageaient une tuile ne sont plus identiques, réécrit la carte et re-compresse le tout.

> [!IMPORTANT]
> Le slot fait `1 644 octets` et la carte commence exactement à la fin de celui-ci (`0x24B8C + 1 644 = 0x251F8`): **il ne peut pas grandir**. Notre build en utilise `989`. Si le mot devient trop complexe, l'encodeur refuse l'insertion plutôt que de déborder sur la carte.

L'image doit faire `152x56px`.

### Le placement (`LAYOUT.csv`)

Les douze rectangles d'affichage sont dans une table à `0x6260`.

`LAYOUT.csv` les expose **tous**:

```csv
index,x,y,w,h,file
0,-80,-56,96,96,EMBLEM.bmp
3,-128,-48,152,56,SAKURA.bmp
10,10,-12,24,24,MARK.bmp
```

Seules les huit octets de placement (`x`, `y`, `w`, `h`) de chaque ligne sont réécrites: le pointeur vers l'image et les drapeaux du sprite restent ceux du jeu. La dernière colonne nomme l'image concernée; elle est purement documentaire et n'est pas relue, donc une ancienne ligne à cinq colonnes reste acceptée.

> [!NOTE]
> `LAYOUT.csv` est appliqué **en dernier**, après les valeurs que l'encodeur écrit lui-même pour "サクラ": une ligne écrite à la main gagne toujours. Si vous repassez en orientation japonaise, pensez donc à remettre les records `1`, `2` et `3` à `-24,-104,56,152`, sinon ils resteront dans la position US alors que l'image sera verticale.

L'encodeur valide explicitement que l'index existe et que les coordonnées tiennent sur 16 bits avant d'insérer quoi que ce soit. Un sprite dont l'image n'est pas dans la bonne orientation se parque hors écran avec `y=255`.

### Orientation: une seule décision

Les dimensions de `SAKURA.bmp` décident de tout le reste, dans les deux sens:

| `SAKURA.bmp` | records 1–3 | arguments du mouvement | rangement du mot |
| --- | --- | --- | --- |
| `152x168` (horizontal, US) | `-128,-48` `152x56` | `E7 07`, `E6 13`, `48 10` | cellules ligne par ligne, tuiles à plat |
| `56x456` (vertical, japonais) | `-24,-104` `56x152` | `E7 13`, `E6 07`, `41 44` | cellules colonne par colonne, tuiles transposées |

Les trois arguments du mouvement sont ceux de l'appel à la routine d'entrée du mot (`0x387A`, `0x387E`, `0x392A`). Les deux premiers changent l'ordre de lecture des cellules; le troisième est celui qui fait réellement traverser l'écran au mot. Le rangement des tuiles suit la même décision: la version japonaise est tournée par la routine, donc ses données sont stockées transposées pour compenser, alors que la version US ne l'est pas.

Si aucune `SAKURA.bmp` n'est fournie, l'encodeur lit les mots déjà présents dans le module et s'aligne dessus; un module qui n'en porte aucun des deux jeux connus n'est jamais touché.

## Notes

Contrairement au menu principal, il n'y a ici qu'un seul budget non extensible (celui du mot) et un budget de bloc pour tout le reste: redessiner le cartouche ou le disque ne coûte cher que si la nouvelle image se compresse moins bien que l'ancienne.

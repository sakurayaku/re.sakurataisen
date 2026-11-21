# Cartouches de lieux des cartes

**Codecs:**
```
SakTaiCD1_Track1.bin
├── SAKURA
│   ├── [decode] EMPTY_ROOM — scripts/map/empty_room.lua
│   └── [decode] META_THEATER_MAP - scripts/theater_map_metadata.lua
└── SAKURA1
    └── TMAPSP.BIN
        └── [decode] THEATER_MAP - scripts/theater_map_gfx.lua
```

**Fichiers concernés:**
- `SAKURA/EMPTY_ROOM/EmptyRoom.bmp`
- `SAKURA1/TMAPSP.bin/51.bmp`
- (etc...)
- `SAKURA1/TMAPSP.bin/92.bmp`

Les images sont tous des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés. La couleur d'index 0 (le vert caca d'oie) indique la transparence. Tout le reste sera visible.

> [!CAUTION]
> La palette n'est PAS modifiable. 

## Description

Ces images contiennent tous les cartouches qui s'affichent sur la carte, lorsque vous contrôlez Ôgami dans le théâtre, ou dans le manoir Fukagawa. Vous pouvez toutes les modifier, tant que vous conservez leurs palettes, que la longueur est un multiple `8px`, et que vous respectez leur budget.. Elles sont réparties entre trois fichiers.

## SAKURA: Pièce vide

Le cartouche de pièce vide se trouve dans `SAKURA` et est commun aux deux cartes. Il contient uniquement `空室` ce qui est littéralement "Pièce vide" et ne rentre pas dans le budget car...c'est la seule image de ce genre, elle est seule dans son slot, et donc son budget de `56x24px` (ou `672 octets`). Le meilleur compromis a été de mettre "Réserve" et lorgner sur la hauteur.

| Fichier | Japonais | Anglais | Français |
| --- | --- | --- | --- |
| `SAKURA/EMPTY_ROOM/EmptyRoom.bmp` | 空室 | Empty Room | Réserve |

## TMAPSP.BIN: Le théâtre

Vous pouvez modifier ces images, à condition que leur longueur reste un multiple de `8px` et que leur hauteur soit supérieure à `1px`, et que vous respectiez leur budget total. Le budget total pour TOUTES ces images, en prenant en compte `00.bmp` à `50.bmp` est de `106 496px`.

> [!NOTE]
> Les images `00.bmp` à `50.bmp` contiennent les sprites d'Ôgami. On ne s'en sert pas, et je n'ai aucune idée de leurs limites, mais si vous le désirez... amusez-vous avec =)

| Fichier | Japonais | Anglais | Français |
| --- | --- | --- | --- |
| `51.bmp` | さくらの部屋 | Sakura's Room | CH Sakura |
| `52.bmp` | カンナの部屋 | Kanna's Room | CH Kanna |
| `53.bmp` | マリアの部屋 | Maria's Room | CH Maria |
| `54.bmp` | 紅蘭の部屋 | Kohran's Room | CH Kôran |
| `55.bmp` | アイリスの部屋 | Iris's Room | CH Iris |
| `56.bmp` | すみれの部屋 | Sumire's Room | CH Sumire |
| `57.bmp` | 書庫 | Library | Bibliothèque |
| `58.bmp` | あやめの部屋 | Ayame's Room | CH Ayame |
| `59.bmp` | 隊長室 | Captain's Quarter | CH Ôgami |
| `60.bmp` | サロン | Salon | Salon |
| `61.bmp` | ホール | Hall | Foyer |
| `62.bmp` | 二階客席 | 2nd Floor Seating | Balcon |
| `63.bmp` | テラス | Terrace | Terrasse |
| `64.bmp` | ↧一階 | To 1st Floor | ⬇ RDC |
| `65.bmp` | 宿直室 | Night Watchman's Room | Gardien |
| `66.bmp` | 支配人室 | Manager's Office | Direction |
| `67.bmp` | 事務局 | Secretarial Office | Secrétariat |
| `68.bmp` | 厨房 | Kitchen | Cuisines |
| `69.bmp` | 衣装部屋 | Costume Room | Vestiaires |
| `70.bmp` | 食堂 | Dining Hall | Réfectoire |
| `71.bmp` | 楽屋 | Backstage | Loges |
| `72.bmp` | 道具部屋 | Prop Room | Accessoires |
| `73.bmp` | 舞台袖 | Stage Wing | Coulisses |
| `74.bmp` | 大道具部屋 | Large Prop Room | Décors |
| `75.bmp` | 舞台 | Stage | Scène |
| `76.bmp` | 一階客席 | 1st Floor Seating | Orchestre |
| `77.bmp` | ロビー | Lobby | Vestibule |
| `78.bmp` | 玄関 | Entrance Hall | Entrée |
| `79.bmp` | 売店 | Gift Shop | Boutique |
| `80.bmp` | ↥二階 | To 2nd Floor | ⬆Étage |
| `81.bmp` | ↧地下 | To Basement | ⬇Sous-sol |
| `82.bmp` | 倉庫 | Storeroom | Entrepôt |
| `83.bmp` | 訓練室 | Training Room | Entraînement |
| `84.bmp` | 医務室 | Infirmary | Infirmerie |
| `85.bmp` | 更衣室 | Dressing Room | Vestiaires |
| `86.bmp` | 水泳場 | Swimming Pool | Piscine |
| `87.bmp` | シャワー室 | Shower Room | Douches |
| `88.bmp` | 作戦室 | War Room | Opérations |
| `89.bmp` | 指令室 | Command Room | Commandement |
| `90.bmp` | 蒸気演算機室 | Steam Processor | Ordinateur à vapeur |
| `91.bmp` | 地下格納庫 | Hangar | Hangar |
| `92.bmp` | ↥一階 | To 1st Floor | ⬆RDC |


## FUKAGAWA.BIN: Le manoir Fukagawa

(J'y viendrais quand je m'en serais occupé)

# Auto-génération des cartouches

Vu que modifier 42 cartouches à la main, c'est laborieux, un script automatise le processus.

Tout d'abord, il faut séparer les bordures en huit fichiers:
- `BORDER_TOP_LEFT.bmp`: Bordure haut-gauche (`3x3px`)
- `BORDER_TOP.bmp`: Bordure du haut (`3x1px`)
- `BORDER_TOP_RIGHT.bmp`: Bordure haut-droite (`4x3px`)
- `BORDER_LEFT.bmp`: Bordure gauche (`3x1px`)
- `BORDER_RIGHT.bmp`: Bordure droite (`4x1px`)
- `BORDER_BOTTOM_LEFT.bmp`: Bordure haut-gauche (`3x3px`)
- `BORDER_BOTTOM.bmp`: Bordure du haut (`3x1px`)
- `BORDER_BOTTOM_RIGHT.bmp`: Bordure haut-droite (`4x3px`)

Puis, faire le fichier de textes: `TEXTS.bmp`. Dans notre cas, chaque ligne fait `14px` de haut dans GIMP, donc on écrit un cartouche, on passe à la ligne, etc... La palette est la même que celle attendue par les BMPs du jeu.

Ensuite, lancer le script Python à la racine:
```bash
$ uv run --with pillow generate_map_boxes.py workspace/SakTaiCD1_Track1.bin/SAKURA1/TMAPSP.BIN 51 92
```

Le script prend chaque ligne, la découpe dès qu'il découvre la première "colonne vide" (donc attention à ne pas foutre d'espace trop violent)

Le script est modifiable et vous pouvez l'ajuste: par exemple la taille de chaque ligne, ou pour rogner la première ligne (qui fait office de marge dans mes tests). C'est comme ça qu'on est passés de lignes de `15px` à des lignes de `14px`. La team US employait des textes bien plus petit (genre ils font rentrer deux lignes dans `16px`!), donc en théorie on a de la marge, c'est sûrement mon "oeil de gamer Full-HD-1080p-4k60fps" qui est pas habitué à penser en "ça se lira différemment une fois élargi sur un vrai écran".

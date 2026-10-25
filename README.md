# Sakurayaku

Projet de traduction française de Sakura Taisen, basée sur le travil effectué par la traduction anglaise de l'équipe de NoahSteam. La plupart des algorithmes d'extraction/insertion sont basés sur [leur travail](https://github.com/NoahSteam/RomHackingTools/blob/master/SakuraTaisen/SakuraTaisen.cpp).

Le projet utilise [ludared](LUDARED-HOWTOUSE.md) comme système de build.

# Contenus

## Dialogues
### SAKURA1/{nnnn}TBL.BIN/{nnnn}TBL.TXT

Ces fichiers correspondent à des sections de script, et chaque ligne préfixée d'un `{numéro index}:` désigne une unité de dialogue.

Afin de permettre une facilité de lecture, vous pouvez le commenter avec `#`, espacer les lignes pour séparer des blocs,... Toutefois, vous devez respecter les règles suivantes:
- les numéros de lignes doivent rester SÉQUENTIELS
- un retour à la ligne dans une unité de dialogue doit être représenté par `<br>`
- il n'y a pas de notion de "commentaire terminal" comme dans un langage de programmation: une ligne est intégralement un commentaire, ou elle est intégralement du texte
- si vous ne faites pas de césure propre, le script d'insertion s'en chargera, mais ce sera moche

Exemple de script:
```txt
# Premier texte du jeu
0001:Ceci est le premier texte du jeu !<br>Bienvenu dans le monde magi-<br>que de Sakura Wars!

# Discussion avec Sakura
0002:Bonjour Ogami ! Vous avez bien dormi?
# CHOICE: => 0004 => 0006
0003:Ouais super !<br>Euh...bof ?

# RESULT <= 0003
0004: J'ai super bien dormi, merci Sakura !
0005: Je suis ravie de l'entendre

# RESULT <= 0003
0006: Euh...bof ? Je crois que je suis malade
0007: Oh non ! Pauvre Ogami

# Discussion avec Sumire
```

Les annotations `CHOICE` et `RESULT` sont totalement arbitraires pour faciliter la relecture des traducteurs, et peuvent être employés par un (futur) outil de traduction collaboratif pour modifier la preview de l'affichage.

## Images

### SAKURA1/LOGO.SH2/MAINMENU/{00_NEW_GAME,01_OPTIONS,02_CONTINUE,03_RESUME,04_THEATER,05_BATTLE_TRIAL,BG}.bmp

Sept images composent l'écran du menu principal: les six entrées du menu et le fond. Le rendu SH-2, les transferts VDP1 et le budget PRS sont détaillés dans [SAKTAI_MAIN_MENU.md](SAKTAI_MAIN_MENU.md).

Les six fichiers `nn_NOM.bmp` sont les étiquettes, en [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexé 4 bits. Le préfixe numérique est l'indice dans la table de descripteurs du module, pas l'ordre à l'écran:
- `00_NEW_GAME.bmp` — "CD1の最初から" (`128×16px`)
- `01_OPTIONS.bmp` — "オプション" (`80×16px`)
- `02_CONTINUE.bmp` — "セーブの続きから" (`128×16px`)
- `03_RESUME.bmp` — "中断の続きから" (`112×16px`)
- `04_THEATER.bmp` — "帝劇の長い一日" (`112×16px`)
- `05_BATTLE_TRIAL.bmp` — "戦闘お試しモード" (`128×16px`)

Chaque BMP représente l'étiquette entière telle qu'elle s'affiche, pas une planche de glyphes `16×16`. Le jeu, lui, stocke chaque étiquette comme une suite d'enregistrements de 10 octets (`x`, `y`, `w`, `h`, `characterOffset`) qui pointent dans un atlas 4bpp commun, transféré en VRAM VDP1 à `0xA000`. Les étiquettes japonaises y sont des tuiles de `16×16px`, souvent partagées entre plusieurs entrées; le décodeur les assemble pour vous. `characterOffset` est l'adresse VDP1 de la texture divisée par 8, d'où l'alignement de 8 octets.

`BG.bmp` est le fond du menu, en BMP indexé 8 bits, `208×152px`, avec ses 256 couleurs. Sa palette, elle, est réelle: elle est lue en `0x29324` et réécrite à l'encodage. Vous pouvez donc changer les couleurs en même temps que les pixels.

En pratique, pour modifier ce menu:
- chaque étiquette doit faire exactement `16px` de haut, et une largeur multiple de `8px`, jusqu'à `2040px` (le champ de largeur d'un sprite VDP1). Au-delà de `320px` l'écran coupe les bords, mais l'encodeur ne l'interdit pas. Chacune garde sa propre largeur: rien n'est aligné sur une allocation commune de `144px`.
- l'index 0 est la transparence: laissez-le à 0 pour le fond d'une étiquette. La palette des BMP d'étiquettes n'est qu'un repère visuel (la rampe du texte ADV); le jeu applique sa propre palette, ces couleurs ne partent jamais sur le disque, et une modification de palette seule n'est pas considérée comme un changement.
- dès qu'une étiquette change, les six sont reconstruites en textures linéaires indépendantes, dans l'ordre de la table de descripteurs. Chaque étiquette n'a plus qu'un seul enregistrement: `x = -largeur/2`, `y = -8`, `w = largeur`, `h = 16`, `count = 1`. Les enregistrements d'origine suivants restent en place, inutilisés.
- si aucune étiquette ne change, l'atlas japonais, les six tables d'enregistrements, les compteurs et la longueur DMA sont recopiés OCTET POUR OCTET. Modifier seulement `BG.bmp` ne transforme donc jamais les glyphes japonais en bandes.
- `BG.bmp` doit rester en `208×152px`: le jeu transfère ce bloc à taille fixe, l'encodeur refuse toute autre dimension.
- la longueur du transfert DMA de la police, mot de 16 bits en `0x3890` lu par `mov.w` (`0x1600` = `5 632` octets à l'origine), est remontée à la taille décompressée de l'atlas et jamais abaissée. `mov.w` étend le signe: `0x7FFF` est le maximum positif, et l'atlas doit aussi rester sous le prochain transfert VDP1 à `0xA000 + 0x18800`.
- aucune instruction SH-2 n'est modifiée: `0x3890` est un mot du pool de littéraux, pas du code.
- les deux blocs PRS doivent tenir ensemble dans `6 222 octets` (`2 280` pour l'atlas, `3 942` pour le fond), entre `0xFF20` et `0x1176E`.
- si l'atlas tient dans ses `2 280 octets`, le fond garde son adresse. Sinon il se décale vers la droite dans la même zone et le pointeur en `0x38A0` est réécrit en conséquence. `LOGO.SH2` garde TOUJOURS sa taille: rien à partir de `0x1176E` ne bouge. Cette limite est réelle: `0x11770` est le début du fond PRS de la scène du disque 1, utilisé par l'export #6 du module (`0x204B18`) et décompressé en `0xF240` octets. Les deux octets de `0x1176E` à `0x11770` sont le seul rembourrage.
- si le fond n'a pas été modifié et que l'atlas ne rentre plus, l'encodeur le recompresse pour récupérer la place (avec l'encodeur actuel, `3 942` → `3 781` octets).
- dépasser le budget est une erreur explicite, pas une troncature silencieuse: l'encodeur indique les tailles réelles et le nombre d'octets à récupérer.
- l'encodeur ne réutilise jamais un décode mis en cache par une version précédente du codec: les sept images ci-dessus sont toujours relues par la version courante.

### SAKURA/OPTIONS/{CURSOR_SPEED,SOUND,VOICE,CONTROLS,EXIT}.bmp

Les cinq étiquettes de l'écran Options, dans l'exécutable `SAKURA` (disque 1) et non dans `LOGO.SH2`. Chaque BMP est l'étiquette entière assemblée (`256×16`, `256×16`, `240×16`, `256×16`, `64×16`), en BMP indexé 4 bits, l'index 0 étant la transparence.

Le jeu dessine ces lignes à partir d'un atlas 4bpp dédié (`0x5B320`, 73 tuiles, base de texture VDP1 `0xD860`) et d'enregistrements de 10 octets. Le rendu, les descripteurs et le budget PRS sont détaillés dans [SAKTAI_OPTIONS_MENU.md](SAKTAI_OPTIONS_MENU.md).

En pratique, pour modifier ce menu:
- hauteur fixe de `16px`, largeur multiple de `8px` (jusqu'à `2040px`); les cinq largeurs ensemble doivent tenir dans `64 + 8 × Σlargeurs ≤ 11 520` octets, soit `1 432px` au total.
- dès qu'une étiquette change, les cinq sont réécrites en bandes indépendantes et chaque descripteur passe à un seul enregistrement (`+12 = 1`) pointant sur sa bande. L'enregistrement reprend l'origine de l'étiquette remplacée (les quatre premières lignes commencent à `x = -128`, EXIT à `-32`), donc rien ne se déplace; une étiquette plus large s'étend vers la droite. Les anciens enregistrements restent en place, inutilisés.
- si aucune étiquette ne change, l'atlas japonais, les descripteurs et les enregistrements sont recopiés OCTET POUR OCTET: une modification de palette seule n'est pas considérée comme un changement.
- la palette des BMP n'est qu'un repère visuel (elle est lue en `0x5ADB8`); ces couleurs ne partent jamais sur le disque.
- le flux PRS doit tenir dans les `3 782` octets de son emplacement et l'atlas décompressé dans `11 520` octets; au-delà, l'encodeur refuse explicitement.
- rien d'autre n'est touché: `OptionsSubmenu`, `SystemMenu`, `PauseOptions`, `GameOptions` et le bloc LoadMenu sont des blocs séparés.

### SAKURA/OPTIONS/{BACKGROUND,BRACKET_LEFT,BRACKET_RIGHT}.bmp et BRACKET_POSITIONS.json

Le fond de l'écran (`BACKGROUND.bmp`, `288×144`, 4bpp) et les deux marques de sélection (`BRACKET_LEFT.bmp`, `BRACKET_RIGHT.bmp`, `8×16`, 4bpp) viennent du même flux PRS à `0x5AE38`. Le fond compose les `20 736` premiers octets décodés; les deux marques sont les `128` derniers octets du flux décodé (`0xC280..0xC2FF`). Les trois BMP sont donc trois vues d'une seule ressource: l'encodeur les compose en un seul flux et ne le recompresse qu'une fois.

- les marques doivent rester en `8×16`, 4bpp. Leur palette BMP (banque `0x5AD98`) est un repère visuel et n'est jamais écrite.
- une modification du fond ou d'une seule marque préserve OCTET POUR OCTET tous les autres octets décodés, y compris le reste des `29 184` octets de queue. Les trois modifications peuvent être combinées sans s'écraser.
- le flux doit tenir dans les `1 256` octets de son emplacement; au-delà, l'encodeur refuse explicitement. Tant que le fond et les deux marques sont identiques au parent, rien n'est recompressé.
- les deux marques sont des textures **partagées par toutes les lignes**. Modifier leur apparence change donc chaque ligne qui en dessine, pas seulement Cursor Speed. Les deux BMP ne peuvent pas donner un indicateur différent à une seule ligne.
- `BRACKET_POSITIONS.json` règle la position, pas l'apparence: une entrée par ligne et par choix, avec `center` (centre du choix) et les décalages `left`/`right` des marques. Le fichier est optionnel; sans lui, les coordonnées d'origine sont conservées. Les rectangles de saisie `+8` et les routines SH-2 de dessin ne sont jamais modifiés.
- pour une marque propre à une ligne (par exemple un curseur pour Cursor Speed), il faudrait de nouvelles textures et un autre `characterOffset` par enregistrement `+24`; voir les limites détaillées dans [SAKTAI_OPTIONS_MENU.md](SAKTAI_OPTIONS_MENU.md).

### SAKURA1/LOGO.SH2/SUBTITLES/{nn.bmp}

Ces images correspondent aux sous-titres de la séquence d'introduction du jeu. Les 11 à 16 semblent ne pas être utilisées par le jeu, l'équipe US ne les ayant même pas remplacées.

Les images sont en [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexé, avec une palette figée. La couleur d'index 0 (ce joli jaune criard) indique la transparence. Tout le reste sera visible.

Il y a des limites sur la quantité d'espace disponible en VRAM pour la totalité de ces images. Pour y pallier, les images 11 à 16 sont remplacées par un _placeholder_ (une image totalement transparente de `8×2px`). De plus, un hack "safe" permet d’exploiter une zone de VRAM supplémentaire, qui semble inutilisée pendant l’introduction.

En pratique, pour modifier ces sous-titres:
- la largeur de chaque image DOIT être un multiple de `8px`.
- la hauteur de chaque image (à part les _placeholder_) doit être de `8px` ou de `16px`. Une tentative à `24px` a donné du _garbage_, et des tentatives intermédiaires n'ont pas été essayées car jugées sans intérêt.
- au total, les 17 images doivent tenir dans une surface cumulée équivalente à `2 224×16px` de base, et à `2 560×16px` avec le hack "safe".

À noter: une fonctionnalité a été ajoutée à l'encoder qui lui permet d'utiliser une image à la place d'une autre. Ainsi, lorsqu’une image de `8×2px` est rencontrée, l’encoder réutilise automatiquement l’image précédente. Le patch s'en sert pour `10.bmp`, qui réutilise donc `09.bmp` en jeu sans avoir à dupliquer ses données.

C'est notamment utile car la ligne finale "Rugis\nPuissant corps d'élite impérial !" est séparée en deux sous-titres dans la version japonaise, alors qu'elle fonctionne mieux sur un sous-titre de deux lignes (mais elle occupe aussi plus d'espace, d'où le hack "safe").

### SAKURA1/TITLE{nn}.BIN/TITLE{nn}.BMP

Ces images correspondent aux titres d'épisodes.

Les images sont en [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexé, avec une palette figée. Vous pouvez modifier les couleurs de la palette, mais vous devez faire attention à enregistrer le fichier en BMP indexé, sinon vous aurez une erreur.

En revanche, vous ne pouvez pas modifier ses dimension.

# Credits & attributions

- TOUT le travail, TOUTE la recherche, TOUS les putains d'efforts,... c'est le boulot de la team US menée par [NoahSteam](https://github.com/NoahSteam/RomHackingTools). Ses membres méritent tous vos éloges, et sans leur boulot, ce projet n'existerait pas.

- La font utilisée dans le jeu est [DejaVu Sans](https://dejavu-fonts.github.io/).


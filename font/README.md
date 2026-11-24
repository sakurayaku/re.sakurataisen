# Génération de police pour le jeu

> [!NOTE]
> J'utilise le terme [glyphe](https://fr.wikipedia.org/wiki/Glyphe) au lieu de [caractère](https://fr.wikipedia.org/wiki/Caract%C3%A8re_(typographie)), ou même "lettre", mais dans notre usage, c'est la même chose.

> [!NOTE]
> J'approfondis volontairement tous les termes techniques en donnant des liens vers des sources, afin de satisfaire la curiosité du lecteur qui souhaite s'informer. Dans la pratique, il n'est pas nécessaire de savoir comment tout fonctionne, une vue d'ensemble suffit.

La police du jeu est limitée à 256 glyphes de 16x16 pixels chacun, en [4bpp](https://sneslab.net/wiki/Graphics_Format#4bpp).

En pratique, tant que vous avez un [.bmp](https://fr.wikipedia.org/wiki/Windows_bitmap) à [palette indexée](https://learn.microsoft.com/fr-fr/dotnet/desktop/winforms/advanced/types-of-bitmaps), vous pourrez en faire la police de vos rêves. Ce fichier doit s'accompagner d'un [.tbl](https://datacrystal.tcrf.net/wiki/Text_Table), qui fera la correspondance entre le glyph, sa valeur unicode[^unicode], sa longueur, et son emplacement dans la police du jeu.

# Générer sa propre police

Le jeu utilise la police [DejaVu Sans](https://fr.wikipedia.org/wiki/DejaVu). Parmi les autres propositions de police qui ont été retenues, il y a:
- [Silkscreen](https://www.dafont.com/silkscreen.font)
- [Liberation Sans](https://www.dafont.com/fr/liberation-sans.font)
- [Noto Sans](https://fonts.google.com/noto/specimen/Noto+Sans)
- [Source Sans 3](https://fonts.google.com/specimen/Source+Sans+3)
- [Trebuchet MS](https://fonts.adobe.com/fonts/trebuchet-ms)
- [Futura PT](https://fonts.adobe.com/fonts/futura-pt)
- [Helvetica](https://font.download/font/helvetica-255)
- [Eurostile](https://font.download/font/eurostile)
- [Intel Clear](https://font.download/font/intel-clear)
- [Helvetica 65](https://fontsgeek.com/fonts/helvetica65-medium-medium)

## 0. Palette et quantification des glyphes

La police utilise une palette de 16 couleurs (4 bpp), mais **tous les indices ne sont pas interchangeables**.

La version américaine utilisait une palette différente de celle du jeu japonais, notamment pour l'index `15`, qui correspondait à un gris foncé (`0x0C63`) au lieu du blanc (`0x7FFF`). Les glyphes générés avec cette palette produisaient donc des artefacts lorsqu'ils étaient affichés avec la palette japonaise.

La police française conserve désormais la palette japonaise originale (`adv_dialogue_jp`), avec les particularités suivantes :

- **Index 0** : blanc, utilisé comme couleur transparente.
- **Indices 1 à 14** : dégradé de gris (*grayscale ramp*), du plus sombre au plus clair.
- **Index 15** : blanc dans le jeu original, mais rouge dans le BMP généré pour empêcher GIMP de traiter l'image comme une image en niveaux de gris. Cet index n'est jamais utilisé par les glyphes.

L'analyse des 629 tuiles de la police japonaise originale (`0100KNJ.BIN`) a également révélé que seuls **10 indices** étaient effectivement utilisés pour dessiner les caractères :

`1, 2, 3, 6, 7, 8, 9, 11, 13, 14`

Les indices `4, 5, 10, 12 et 15` ne sont jamais utilisés.

Le générateur reproduit désormais cette distribution grâce à `INK_WEIGHTS`, plutôt que de simplement associer chaque pixel au gris le plus proche.

Cette particularité est importante pour les sélections **LIPS** : le jeu remplace temporairement la palette normale par `adv_lips_jp`, dont certains indices clairs deviennent rosés. En reproduisant les indices de la police originale, les caractères français conservent un rendu cohérent avec les caractères japonais, y compris cet effet rosé intentionnel.


## 1. Étape automatisable

> [!CAUTION]
> Ce script a été lancé initialement avec [Pillow 12.3.0](https://github.com/python-pillow/Pillow/releases/tag/12.3.0). Lors du passage à 13.0.0, un _breaking change_ (no shit!) dans le calcul des métriques des caractères a modifié les largeurs générées, généralement d’un pixel. Le script a donc été figé sur Pillow 12.3.0, car je n’ai pas envie de revérifier tous les dialogues du jeu traduits jusque-là.

Placez-vous dans ce répertoire, et lancez le script de transformation de police [TrueType](https://fr.wikipedia.org/wiki/TrueType) en atlas de glyphes. Ce script génère ses caractères à partir de la table d'encodage [Windows-1252](https://fr.wikipedia.org/wiki/Windows-1252), qui augmente la [table ASCII](https://fr.wikipedia.org/wiki/American_Standard_Code_for_Information_Interchange) avec des accents et autres caractères européens.

Utilisez [ttf_to_font.py](./ttf_to_font.py) pour générer votre atlas de glyphes, et la table correspondante (basée sur les indications de la police).

Par exemple, pour générer la police actuelle du jeu:

```bash
$ uv run ttf_to_font.py DejaVu/DejaVuSans.ttf \
  --size 12 \
  --output FONT_DEJA_VU_SANS.bmp \
  --table I18N_DEJA_VU_SANS.tbl
```

Dans [ttf_to_font.py](./ttf_to_font.py), vous pouvez utiliser le tableau `OVERRIDE_GLYPHS` pour indiquer qu'un index sera utilisé par un autre caractère de votre choix, que cette font peut fournir. Par défaut, les 32 indexes de 0x00 à 0x19 sont libres, vous pouvez donc y mettre ce que vous voulez, mais vous pouvez remplacer n'importe quel index jusqu'à 0xFF.

## 2. Convertir la police

Utilisez [font.py](./font.py) pour transformer votre atlas de glyphes dans un format compréhensible par le jeu.

Dans notre exemple:
```bash
$ python3 font.py encode FONT_DEJA_VU_SANS.bmp FONT_DEJA_VU_SANS.BIN
```

## 3. Remplacer les fichiers

Vous avez enfin vos deux fichiers nécessaires: les glyphes (ici: `FONT_DEJA_VU_SANS.BIN`), et la table (ici: `I18N_DEJA_VU_SANS.tbl`). Chacun doit être renommé et aller dans un emplacement différent:

TODO: Une fois que `std/magic/replace-with` est dispo, le fichier de glyphes doit avoir un seul emplacement.

Les glyphes doivent remplacer le fichier `./workspace/SakTaiCD1_Track1.bin/SAKURA1/0100KNJ.BIN`.

La table doit aller remplacer le fichier `./workspace/tables/I18N_FONT.tbl`.

Une fois le remplacement fait, vous pouvez lancer un `ludared build`.

# Générer votre propre police, comme un pro

Si vous ne voulez pas vous baser sur une police existante, vous pouvez générer votre propre police, en générant votre propre `.bmp` et la `.tbl` correspondante.

Le fichier .bmp:
- 256x256 pixels
- chaque bloc de 16x16 pixels est un glyph, aucun dépassement autorisé
- palette indexée
- la première couleur de la palette est transparente

Le fichier .tbl est un peu plus complexe car il alimente la VWF[^vwf]. Son format est le suivant:
```.tbl
{hex}={width}={glyph unicode}
0001=9=♪
0002=12=♫
0003=12=♬
0004=10=♀
(...)
00FC=9=ü
00FD=8=ý
00FE=9=þ
00FF=8=ÿ⏎
```

Sachant que la police du jeu ne peut contenir que 256 glyphs, `{hex}` est limité à 256 (0xFF). Pour la `width`, si toute votre police est [monospace](https://fr.wikipedia.org/wiki/Police_de_caract%C3%A8res_%C3%A0_chasse_fixe), vous pouvez ignorer ce paramètre, auquel cas il sera égal à `16` par défaut. Par exemple:

```.tbl
0001=A
0002=B
(...)
00FF=Z
```

# International-only: Using more than 256 glyphs

While it appears that the game is limited to 256 unique glyphs, which is something both the original project, and this one, have decided to go with for ease of work, you can actually use tricks to go A BIT over that limit.

Each "section" of the game (you can delimitate them by using `ludared artifacts list | grep TBL.BIN`) uses its own font file (the corresponding `(nnnn)KNJ.BIN`). In the japanese version of the game, it means that if a section doesn't use a glyph, there's no reason to add it to that section's font, and there's a tighter control on "what glyph is available to what section".

So while you ARE limited to 256 glyphs per font file, you are not limited to 256 glyphs across the game.

If you decide to go that way, you'll need to:
- Make a font+table for each section
- Modify [scripts/dialogues.lua](../scripts/dialogues.lua), so it uses the output table for the section you're encoding.

You could also go ONE STEP FURTHER and generate your font per section on-the-fly when you insert your dialogue table: fetch unique glyphs in that script section, confrm there're less than 256, build font, inject it, and then insert your text.

But that's a whole other level of pipeline.

***
[^unicode]: C'est-à-dire, "tel que votre machine l'affiche".
[^vwf]: Une _Variable-Width Font_, ou en français "police proportionnelle" est une police où chaque caractère peut avoir sa propre largeur. Ainsi "lili" prendra moins de place à l'affichage que "mumu".
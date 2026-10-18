# Génération de police pour le jeu

> [!NOTE]
> J'utilise le terme [glyphe](https://fr.wikipedia.org/wiki/Glyphe) au lieu de [caractère](https://fr.wikipedia.org/wiki/Caract%C3%A8re_(typographie)), ou même "lettre", mais dans notre usage, c'est la même chose.

> [!NOTE]
> J'approfondis volontairement tous les termes techniques en donnant des liens vers des sources, afin de satisfaire la curiosité du lecteur qui souhaite s'informer. Dans la pratique, il n'est pas nécessaire de savoir comment tout fonctionne, une vue d'ensemble suffit.

La police du jeu est limitée à 256 glyphes de 16x16 pixels chacun, en [4bpp](https://sneslab.net/wiki/Graphics_Format#4bpp).

En pratique, tant que vous avez un [.bmp](https://fr.wikipedia.org/wiki/Windows_bitmap) à [palette indexée](https://learn.microsoft.com/fr-fr/dotnet/desktop/winforms/advanced/types-of-bitmaps), vous pourrez en faire la police de vos rêves. Ce fichier doit s'accompagner d'un [.tbl](https://datacrystal.tcrf.net/wiki/Text_Table), qui fera la correspondance entre le glyph, sa valeur unicode[^unicode], sa longueur, et son emplacement dans la police du jeu.

# Générer sa propre police

## 1. Étape automatisable

Placez-vous dans ce répertoire, et lancez le script de transformation de police [TrueType](https://fr.wikipedia.org/wiki/TrueType) en atlas de glyphes. Ce script génère ses caractères à partir de la table d'encodage [Windows-1252](https://fr.wikipedia.org/wiki/Windows-1252), qui augmente la [table ASCII](https://fr.wikipedia.org/wiki/American_Standard_Code_for_Information_Interchange) avec des accents et autres caractères européens.

Utilisez [ttf_to_font.py](./ttf_to_font.py) pour générer votre atlas de glyphes, et la table correspondante (basée sur les indications de la police).

Par exemple, pour générer la police actuelle du jeu:

```bash
$ python3 ttf_to_font.py DejaVuSans.ttf \
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

Les glyphes doivent remplacer le fichier `./workspace/SakTaiCD1_Track1.bin/data.bin/SAKURA1/0100KNJ.BIN`.

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
[^vwf]: Une _Variable-Width Font_, ou en français "police proportionnelle" est une police où chaque caractère peut avoir sa propre largeur. Ainsi "lili" prendra moins de place à l'affichaque que "mumu".
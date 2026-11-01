# Menu principal du jeu

**Fichiers concernés:**
- `SAKURA1/LOGO.SH2/MAINMENU/00_NEW_GAME.bmp`
- `SAKURA1/LOGO.SH2/MAINMENU/01_OPTIONS.bmp`
- `SAKURA1/LOGO.SH2/MAINMENU/02_CONTINUE.bmp`
- `SAKURA1/LOGO.SH2/MAINMENU/03_RESUME.bmp`
- `SAKURA1/LOGO.SH2/MAINMENU/04_THEATER.bmp`
- `SAKURA1/LOGO.SH2/MAINMENU/05_BATTLE_TRIAL.bmp`
- `SAKURA1/LOGO.SH2/MAINMENU/BG.bmp`

Tous sont des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés. La couleur d'index 0 (bleu azur, ou blanc pur) indique la transparence. Tout le reste sera visible.

## Description

Ces images permettent de dessiner le menu principal du jeu. Elles se composent d'un cartouche de fond, `BG.bmp`, et de six étiquettes nommées sous le format `{nn}_{NOM}.bmp`, `nn` étant un index de `00` à `05` et `NOM` étant leur description.

Tous les éléments ont un budget commun, après [compression PRS](https://segaretro.org/PRS_compression), de `6 222 octets`. Si vous dépassez celui-ci, l'encodeur refusera l'insertion.

### Cartouche de fond

Le fichier `BG.bmp` est le cartouche sur lequel les entrées textuelles de choix seront dessinées. Il utilise sa propre palette de 256 couleurs, avec un bleu azur comme couleur transparente.

Vous pouvez le modifier mais:
- L'image doit faire `208x152px`[^dimension_bg].
- Vous pouvez modifier les couleurs de la palette.

L'encodeur valide explicitement ces règles avant d'insérer l'image.

### Étiquettes de choix

Les six fichiers `{nn}_{nom}.bmp` sont les étiquettes. Le préfixe numérique est juste l'indice utilisé par le module, pas leur ordre à l'écran:
- `00_NEW_GAME.bmp`: En japonais `CD1の最初から`
- `01_OPTIONS.bmp`: En japonais `オプション`
- `02_CONTINUE.bmp`: En japonais `セーブの続きから`
- `03_RESUME.bmp`: En japonais `中断の続きから`
- `04_THEATER.bmp`: En japonais `帝劇の長い一日`
- `05_BATTLE_TRIAL.bmp`: En japonais `戦闘お試しモード`

La palette BMP des étiquettes a été adaptée pour permettre l'édition, mais le jeu emploie ses propres palettes: une noire, partagée avec les dialogues, et une rouge, qui indique quel élément est actuellement choisi.

> [!CAUTION]
> Sur les étiquettes, le blanc est employé comme couleur de la transparence pour conserver l'anti-aliasing du texte lors de la conversion en fichiers .bmp par GIMP. De plus, la toute dernière couleur de la palette est un rouge criard: ce n'est PAS un accident, et elle n'est PAS transparente: c'est une limite de GIMP qui interprète la palette comme "grayscale" si elle ne contient pas au moins une "couleur colorée", et cela impactait la réinsertion.

Vous pouvez modifier ces étiquettes, mais:
- Leur hauteur doit obligatoirement faire `16px`.
- Leur largeur doit obligatoirement être un multiple de `8px`.
- Leur largeur ne doit pas dépasser les `208px` (soit la largeur du cartouche).

L'encodeur valide explicitement ces règles avant d'insérer l'image. L'encodeur recalcule aussi la position de chaque étiquette pour qu'elle soit centrée selon la largeur qu'elle occupe.

## Notes

Contrairement à d'autres éléments, qui convertissent en "atlas" pour réutiliser les éléments de commun, ce n'est pas le cas ici: les six étiquettes sont TOUTES stockées dans le jeu comme "six bandes". Toutefois, la [compression PRS](https://segaretro.org/PRS_compression) devrait éviter la duplication de données.

Le budget total de `6 222 octets` n'est **PAS DU TOUT** extensible. Toutefois, les budgets individuels de chaque morceau (`3 942 octets` pour le cartouche, `2 280 octets` pour les étiquettes) peuvent être modifiés pour privilégier les étiquettes[^bigger_bg]. L'encodeur fait l'échange de budget automatiquement en déplaçant l'adresse de départ des données du cartouche, et en changeant le pointeur vers celle-ci.

Notre [encodeur PRS](https://github.com/joshleaves/ludared/blob/master/src/codecs/sega/compression/prs/mod.rs) est plutôt performant. Ainsi, si le fond n'a pas été modifié, et que les étiquettes ont besoin d'espace, le fond sera re-compressé et déplacé.

***
[^dimension_bg]: En pratique, on a jamais tenté plus, il faudrait voir avec la routine qui le dessine.
[^bigger_bg]: Le codec ne le permet pas, mais **en théorie**, il est possible de déplacer l'adresse du cartouche pour qu'il soit positionné plus tôt.

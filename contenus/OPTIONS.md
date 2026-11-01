# Options du jeu

**Fichiers concernés:**
- `SAKURA/OPTIONS/{nn}_{NOM}.bmp`: Cinq étiquettes d'options principales, avec `nn` de `00` à `04` et `NOM` désignant l'option
- `SAKURA/OPTIONS/BACKGROUND.bmp`
- `SAKURA/OPTIONS/BRACKET_{LEFT,RIGHT}.bmp`: Deux fichiers représentant les crochets autour des éléments sélectionnés
- `SAKURA/OPTIONS/BRACKET_POSITIONS.json`: Les positions des crochets de sélection pour chaque option
- `SAKURA/OPTIONS/BUTTON_{ABC,XYZLR}.bmp`: Les glyphes de boutons de la manette
- `SAKURA/OPTIONS/SUB_{nn}_{NOM}.bmp`: Douze étiquettes, avec `nn`de `00` à `11`, désignant les actions assignables aux boutons de la manette.
- `SAKURA/OPTIONS/TEXT_ORIGINS.json`: Les positions de dessin de chaque option

La palette BMP des étiquettes a été adaptée pour permettre l'édition, mais le jeu emploie ses propres palettes: une noire, partagée avec les dialogues, et une rouge, qui indique quel élément est actuellement choisi.

> [!CAUTION]
> Sur TOUTES les étiquettes, le blanc est employé comme couleur de la transparence pour conserver l'anti-aliasing du texte lors de la conversion en fichiers .bmp par GIMP. De plus, la toute dernière couleur de la palette est un rouge criard: ce n'est PAS un accident, et elle n'est PAS transparente: c'est une limite de GIMP qui interprète la palette comme "grayscale" si elle ne contient pas au moins une "couleur colorée", et cela impactait la réinsertion.

## Description

Ces images, et ces fichiers [JSON](https://fr.wikipedia.org/wiki/JavaScript_Object_Notation), permettent de dessiner l'écran d'options du jeu, affichage depuis le [menu principal du jeu](/contenus/MAIN_MENU.md), mais aussi à tout moment en plein jeu. Ils décomposent ainsi:

### Cartouche de fond

Le fichier `BACKGROUND.bmp` est le cartouche sur lequel les options seront dessinées. Il utilise sa propre palette de 256 couleurs, avec un bleu azur comme couleur transparente.

Vous pouvez le modifier, mais:
- L'image doit faire `288x144px`.
- Vous pouvez modifier les couleurs de la palette.

L'encodeur valide explicitement ces règles avant d'insérer l'image.

### Les cinq étiquettes d'options principales

Ce sont les cinq premières options visibles:

- `00_CURSOR_SPEED.bmp`: Vitesse d'affichage du texte. Cinq choix, du plus lent au plus rapide.
- `01_SOUND.bmp`: Mode sonore: Mono ou Stéréo
- `02_VOICE.bmp`: Voix: Sans ou avec.
- `03_CONTROLS.bmp`: Contrôles: les deux options ("Modifier" et "Voir") ouvrent des sous-menus liés aux contrôles du jeu
- `04_EXIT.bmp`: Fermer le menu d'option

Vous pouvez modifier ces étiquettes, mais:
- Leur hauteur doit obligatoirement faire `16px`.
- Leur largeur doit obligatoirement être un multiple de `8px`.

L'encodeur valide explicitement ces règles avant d'insérer l'image.

### Les crochets de sélection

#### Images
Les crochets gauche et droite indiquant l'option sélectionnée ont chacun leur fichier, avec les mêmes règles de transparence que pour les labels.

Vous pouvez les modifier, mais:
- Leur hauteur doit obligatoirement faire `16px`.
- Leur largeur doit obligatoirement faire `8px`.

L'encodeur valide explicitement ces règles avant d'insérer l'image.

#### Positions
Vous pouvez adapter la position des crochets en éditant le fichier `BRACKET_POSITIONS.json` afin qu'elle colle à vos étiquettes d'options: il décrit chacun des éléments, et les choix possibles. Par exemple, pour les voix:

```json
{
  "name": "02_VOICE",
  "choices": [
    { "center": -4, "left": -8, "right": 8 },
    { "center": 12, "left": -8, "right": 8 }
  ]
},
```

L'encodeur transformera automatiquement ces valeurs en positions de dessin pour les crochets:
- `center`: Le nombre de pixels depuis le milieu de l'écran, désigne la position horizontale centrale du choix.
- `left`: Le nombre de pixels à AJOUTER à la position horizontale d'origine. Vous pouvez donc indiquer une position horizontale négative.
- `right`: Le nombre de pixels à ajouter à la position horizontale d'origine.

> [!CAUTION]
> Les positions obtenues sont les positions de "départ" pour dessiner chaque crochet. Cela signifie que si la position horizontale du crochet de gauche est de `8`, il sera dessiné de `8` à `16`.

### Les glyphes des boutons

Rien à ajouter ici. Ces glyphes représentent les boutons de la manette, sur deux fichiers: A/B/C et X/Y/Z/L/R.

Vous pouvez les modifier, mais:
- Chaque glyphe doit garder son bloc de `16x16px`.

### Les étiquettes des actions

- `SUB_00_NONE.bmp`: Pas d'action définie
- `SUB_01_CONFIRM.bmp`: Japonais `決定`
- `SUB_02_CANCEL.bmp`: Japonais  `取り消し`
- `SUB_04_MAP.bmp`: Japonais  `全図`
- `SUB_05_CONSULT.bmp`: Japonais  `相談`
- `SUB_06_DEFEND.bmp`: Japonais  `防御`
- `SUB_07_WAIT.bmp`: Japonais  `ため`
- `SUB_08_ATTACK.bmp`: Japonais  `通常攻撃`
- `SUB_09_MOVE.bmp`: Japonais  `移動`
- `SUB_10_DEFAULT.bmp`: Japonais  `初期設定`
- `SUB_11_EXIT.bmp`: Fermer ce menu d'options

Ces étiquettes désignent (de `00` à `09`) des actions assignables aux différents boutons de la manette, ou (de `10` à `11`) des actions.

Vous pouvez les modifier, mais:
- Leur hauteur doit obligatoirement faire `16px`.
- Leur largeur doit obligatoirement être un multiple de `8px`.

L'encodeur valide explicitement ces règles avant d'insérer l'image.

## Notes

### Budget total de l'atlas

Dans le jeu, tous ces éléments graphiques sont présentés sous la forme d'un "atlas": ils sont découpés en sprites (dont la longueur est invariablement un multiple de `8px`), et dessinés au besoin. Par exemple, `04_EXIT.bmp` et `SUB_11_EXIT.bmp` utilisent les mêmes caractères, ils sont donc le même sprite dans l'atlas, et le jeu indique pour les deux menus "dessine-moi ce sprite". Ceci est le premier budget, celui de l'atlas[^atlas_budget].

Le second budget est celui des instructions d'affichage: dans l'exemple plus haut, nous avons une sprite affichée deux fois, donc deux instructions d'affichage. Si nous avions séparé le "EXIT" en deux sprites, nous aurions quatre instructions d'affichage. C'est le second budget, celui des instructions.

L'encodeur a donc été révisé pour tester plusieurs stratégies de découpage des sprites, pour rentrer dans les budgets (qui font au total `3 782 octets`).

Vous pouvez participer à l'amélioration du découpage en alignant des morceaux de mots sur les mêmes découpages. Par exemple:
- Pour l'audio `Mono` et `Stéréo`, les étiquettes sont alignées pour que le `o` final occupe son propre bloc, et soit réutilisable.
- Pour les voix `On` et `Off`, les deux `O` occupent chacun leur propre bloc de 8px, ils sont donc réutilisables.
- Toutes les terminaisons en `-er` des verbes d'action ont été alignées (quitte à tricher sur quelques espacements de caractères des verbes), et réutilisables.
- Certaines réutilisations "accidentelles": par exemple `Défaut` et `Défendre` partagent le même `Déf`.

En pratique, si vous évitez d'utiliser trop de glyphes différents, ou de mettre des tailles de polices différentes partout, ça devrait rentrer.

L'encodeur vous préviendra s'il ne trouve pas de stratégie viable pour rentrer dans les budgets.

### UX des crochets

Pour la traduction française, vu que les crochets ne sont pas très "UX européenne", le crochet de droite est entièrement transparent, et le crochet de gauche est un "diamant" (mais une flèche, genre celle dans Pokémon, aurait eu le même effet).

***
[^atlas_budget]: Techniquement, l'atlas a AUSSI un budget décompressé de `11 520 octets`, qui est la limite qu'il peut occuper dans la mémoire vidéo de la console.
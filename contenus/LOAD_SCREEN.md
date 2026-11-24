# Écran de sauvegarde

**Codecs:**
```
SakTaiCD1_Track1.bin
└── SAKURA
│   └── [decode] LOAD_SCREEN — scripts/load_screen_gfx.lua
```

**Fichiers concernés:**
- `SAKURA/LOAD_SCREEN/COMMANDS_CHOICE_{command}.bmp`: Labels de choix d'actions (en bas à droite)
- `SAKURA/LOAD_SCREEN/COMMANDS_CONFIRM.bmp`: Labels de confirmation.
- `SAKURA/LOAD_SCREEN/COMMANDS_CONTEXT.bmp`: Labels de l'action en cours.
- `SAKURA/LOAD_SCREEN/COMMANDS_RESULT.bmp`: Labels de résultat des actions.
- `SAKURA/LOAD_SCREEN/EMPTY_SAVE.bmp`: Indicateur "Pas de sauvegarde ici".
- `SAKURA/LOAD_SCREEN/EPISODE_NUMBERS.bmp`: Labels des numéros d'épisodes.
- `SAKURA/LOAD_SCREEN/EPISODE_TITLES.bmp`: Labels des titres d'épisodes.
- `SAKURA/LOAD_SCREEN/ERRORS.bmp`: Labels d'erreurs.
- `SAKURA/LOAD_SCREEN/LOAD_MENU.bmp`: Background du menu.
- `SAKURA/LOAD_SCREEN/LOAD_MENU_COPY_SOURCE.bmp`: Indicateur de la "source" lors d'une copie.
- `SAKURA/LOAD_SCREEN/LOAD_MENU_MEMCARD.bmp`: Background du menu en mode "cartouche mémoire".
- `SAKURA/LOAD_SCREEN/UNUSED.bmp`: Labels inutilisés.
- `SAKURA/LOAD_SCREEN/UNUSED_ALONE_GLYPH.bmp`: Un glyph seul non utilisé.
- `SAKURA/LOAD_SCREEN/UNUSED_EPISODE_10.bmp`: Le numéro d'épisode pour l'épisode 10, mais non utilisé.

Les images sont tous des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés. La couleur d'index 0 (le bleu clair pour les `LOAD_MENU_*`, le blanc pour le reste) indique la transparence. Tout le reste sera visible.

> [!CAUTION]
> La palette n'est PAS modifiable.

## Description

Ces images permettent de totalement modifier l'écran de gestion des sauvegardes du jeu.

### Image de décor

Tout le "background" de l'image. À noter que si une cartouche de sauvegarde (l'équivalent Saturn des cartes mémoires) est insérée, aller à gauche utilisera les éléments dans `LOAD_MENU_MEMCARD` pour dessiner la version "cartouche" et affichera les sauvegardes du jeu contenues sur celle-ci.

L'élément `LOAD_MENU_COPY_SOURCE` apparaît sur une sauvegarde lorsque vous la copiez: il indique la "source" de la copie en cours.

Vous pouvez modifier autant que vous voulez, tant que vous ne changez pas leur dimensions (ou leur palette) et que vous restez dans le budget de leur block [PRS](https://segaretro.org/PRS_compression) de `2 292 octets`.

### Les étiquettes de texte

> [!CAUTION]
> Sur les étiquettes, le blanc est employé comme couleur de la transparence pour conserver l'anti-aliasing du texte lors de la conversion en fichiers .bmp par GIMP. De plus, la toute dernière couleur de la palette est un rouge criard: ce n'est PAS un accident, et elle n'est PAS transparente: c'est une limite de GIMP qui interprète la palette comme "grayscale" si elle ne contient pas au moins une "couleur colorée", et cela impactait la réinsertion.

Tous les textes affichables sont contenus là-dedans. On est sur la même problématique que [le menu d'options](./OPTIONS.md): tous les textes sont découpés en tuiles de `16x16px`, unifiées dans un atlas de symboles, puis chaque étiquette fait intervenir les tuiles qui l'intéressent. Très pratique en Japonais, moins quand vous avez une VWF[^vwf].

Ce qui nous amène au premier budget: 144 tuiles uniques dans le patch US. On a grimpé la limite à 181 et ça fonctionne toujours, donc pour le moment, on croise les doigts. Sachant qu'en plus, cet atlas de tuiles doit tenir dans un block [PRS](https://segaretro.org/PRS_compression) de `6 970 octets`.

Et enfin, dernier budget: une fois votre atlas employé, les étiquettes de texte (à l'exception des cinq `COMMANDS_CHOICE`) partagent un "budget de déclaration des sprites" de `762 octets` qui correspond à la manière dont le code dira "Pour former cette étiquette, affiche les sprites `0x0001 0x0002 0x0003 0x0025 0x0049 0x0END`" (soit 5 fois `2 octets`, plus `2 octets` pour indiquer la fin de la chaine, un total de `12 octets` pour 5 sprites de `16x16px`), et un dernier marqueur "fin de block" de deux octets, vous laissant donc un budget de "335 références de tuiles". Vous pouvez raccourcir les étiquettes: les espaces vides à droite n'entrent pas dans ce budget.

> [!NOTE]
> Si vous vous retrouvez à dépasser ce budget, vous pouvez (essayer de) modifier le comportement du jeu pour qu'il n'utilise qu'un seul octet par sprite de `16x16px`. La méthode a été documentée [dans le codec](/scripts/load_screen_gfx.lua), à côté de `local STRING_BUDGET`, mais elle n'a PAS été testée, et peut briser d'autres sections du jeu. Étant donné que les étiquettes de la version française rentrent, je n'ai pas creusé ni testé dans cette direction, mais ça peut être utile à l'avenir.

Les feuilles à plusieurs lignes gardent leurs dimensions. Les étiquettes isolées et les boutons peuvent changer de largeur dans les limites indiquées ci-dessous.

#### EPISODE_NUMBERS

Pour chaque sauvegarde, deux lignes: la première contient le numéro de l'épisode. En Japonais, elle est sur 3 tuiles (`第1話` ou `最終話` pour le dernier épisode), et centrée dans un espace qui mériterait d'avoir cinq tuiles. Le codec réunit donc tous les bitmaps dans une image commune, où change rangée (de `16px` de haut) sera pour un épisode différent.

#### EPISODE_TITLES

Même principe que pour `EPISODE_NUMBERS`: dix rangées de `16px` de haut, et `208px` de large, une par épisode.

#### EMPTY_SAVE

Lorsqu'un emplacement de sauvegarde ne contient pas de sauvegarde, le jeu affiche cette étiquette pour indiquer "emplacement vide". Vu que les tuiles sont limitées, et que l'espace est déjà vide, pas besoin d'indiquer "Pas de sauvegarde ici" textuellement. Donc, vide.

#### COMMANDS_CONTEXT

Même principe de tuiles: cinq rangées de `16px` de haut, et `144px` de large, une par message. Les cinq messages correspondent au contexte de l'action en cours, qui est indiquée en haut de l'écran:
- "Choisissez une partie à copier"
- "Choisissez où copier la partie"
- "Choisissez une partie à charger"
- "Choisissez un emplacement où sauvegarder"
- "Choisissez une partie à effacer"

#### COMMANDS_CONFIRM

Même principe de tuiles: quatre rangées de `16px` de haut, et `128px` de large, une par message. Les quatre messages sont des messages de demande de confirmation qui apparaissent en bas à gauche de l'écran:
- "Êtes-vous sûr de vouloir effacer cette partie ?"
- "Êtes-vous sûr de vouloir copier cette partie ?"
- "Êtes-vous sûr de vouloir sauvegarder ?"
- "Êtes-vous sûr de vouloir charger cette partie ?"

#### COMMANDS_RESULT

Même principe de tuiles: trois rangées de `16px`de haut et `176px`de large, une par message. Les trois messages sont des messages de résultats après avoir confirmé une action:
- "Sauvegarde effectuée"
- "Suppression effectuée"
- "Copie effectuée"

#### ERRORS

Même principe de tuiles: quatre rangées de `16px` de haut, et `272px` de large, une par message. Les quatre messages sont des messages d'erreur, que je n'ai jamais réussi à trigger:
- "Pas de données de sauvegarde"
- "Impossible de lire la sauvegarde"
- "Insérer le CD 2"
- "Insérer le CD 1"

> [!NOTE]
> Oui, "CD 2" avant "CD 1", car ce message apparaîtra forcément en premier!

#### COMMANDS_CHOICE_*

Sous la liste de sauvegardes, le jeu vous propose `COPY`, `DELETE` et `EXIT`. Choisissez `DELETE`, sélectionnez une sauvegarde, et les deux premiers se transformeront en `YES` et `NO`. Ces cinq boutons occupent le même budget de DOUZE tuiles totales.

Leur répartition Japonaise étaient de "1 caractère par tuile", on avait donc la répartition suivante:
- `COPY` => 3 tuiles (`コピー`)
- `DELETE` => 2 tuiles (`消去`)
- `YES` => 2 tuiles (`はい`)
- `NO` => 3 tuiles (`いいえ`)
- `EXIT` => 2 tuiles (`終了`)

Pour arranger, le codec a flippé ça: `NO` perd une tuile, et `DELETE` en gagne une.

Vous avez donc cinq images, avec une largeur modifiable tant que leur somme ne dépasse pas douze tuiles de `16x16px`.

#### Éléments non-utilisés

Les fichiers `UNUSED`, `UNUSED_ALONE_GLYPH` et `UNUSED_EPISODE_10` sont apparemment non-utilisés. Ils ont donc été rempli de tuiles vides. On verra plus tard s'il faut les mettre à jour.

***
[^vwf]: Une _Variable-Width Font_, ou en français "police proportionnelle" est une police où chaque caractère peut avoir sa propre largeur. Ainsi "lili" prendra moins de place à l'affichage que "mumu".

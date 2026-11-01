# Sakurayaku

Projet de traduction française de Sakura Taisen, basée sur le travail effectué par la traduction anglaise de l'équipe de NoahSteam. La plupart des algorithmes d'extraction/insertion sont basés sur [leur travail](https://github.com/NoahSteam/RomHackingTools/blob/master/SakuraTaisen/SakuraTaisen.cpp).

Le projet utilise [ludared](LUDARED-HOWTOUSE.md) comme système de build.

# Contenus modifiables

## Textes

- [Textes de dialogue du jeu](/contenus/DIALOGUES_TBL.md)

## Éléments graphique

> [!CAUTION]
> L'affichage des [sprites](https://fr.wikipedia.org/wiki/Sprite_(jeu_vid%C3%A9o)) sur Saturn repose sur des [palettes](https://fr.wikipedia.org/wiki/Palette_de_couleurs) qui représentent les couleurs auxquelles ils ont accès. Ainsi, afin de faciliter le travail d'adaptation, la palette originale de chaque élément graphique est extraite du jeu, et les graphismes produisent un [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexé, qui est le meilleur moyen de sauvegarder l'information et de la restituer dans le jeu. Cela ne signifie pas que toutes les palettes sont modifiables. La description de chaque élément vous indiquera ce qui est permis.

Seuls les fichiers `.bmp` sont importants. Les fichiers `.xcf` (format de travail [GIMP](https://fr.wikipedia.org/wiki/GIMP)) sont conservés pour pouvoir faire diverses éditions à la volée sans tout redessiner, et doivent manuellement être exportés en `.bmp`.

- [Sous-titres de la séquence d'introduction](/contenus/SUBTITLES.md)
- [Écrans de titres des épisodes](/contenus/TITLE.md)
- [Menu principal du jeu](/contenus/MAIN_MENU.md)
- [Options du jeu](/contenus/OPTIONS.md)

# Credits & attributions

- TOUT le travail, TOUTE la recherche, TOUS les putains d'efforts,... c'est le boulot de la team US menée par [NoahSteam](https://github.com/NoahSteam/RomHackingTools). Ses membres méritent tous vos éloges, et sans leur boulot, ce projet n'existerait pas.

- La font utilisée dans le jeu est [DejaVu Sans](https://dejavu-fonts.github.io/).

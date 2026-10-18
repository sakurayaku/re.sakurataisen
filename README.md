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

### SAKURA1/TITLE{nn}.BIN/TITLE{nn}.BMP

Ces images correspondent aux titres d'épisodes.

Les images sont en [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indéxé, avec une palette figée. Vous pouvez modifier les couleurs de la palette, mais vous devez faire attention à enregistrer le fichier en BMP indéxé, sinon vous aurez une erreur.

En revanche, vous ne pouvez pas modifier ses dimension.

# Credits & attributions

- TOUT le travail, TOUTE la recherche, TOUS les putains d'efforts,... c'est le boulot de la team US menée par [NoahSteam](https://github.com/NoahSteam/RomHackingTools). Ses membres méritent tous vos éloges, et sans leur boulot, ce projet n'existerait pas.

- La font utilisée dans le jeu est [DejaVu Sans](https://dejavu-fonts.github.io/).


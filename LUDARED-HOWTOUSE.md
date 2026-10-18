# Ludared

Ce projet **SakuraYaku** utilise [ludared](https://github.com/joshleaves/ludared) comme système de build afin de décomposer l'ISO original en un ensemble de fichiers qu'il est plus simple de modifier.

Les instructions qui suivent partent du principe que vous êtes à peu près habitués aux lignes de commande Linux/Mac.

## Installation locale du repo git

Ce repo git sert à regrouper et centraliser le travail effectué.

```bash
# 1. Récupérer le projet
# Cette commande créera le dossier `sakurayaku`, qui contiendra le projet
# synchronisé à la version commune en ligne.
~/ $ git clone git@github.com:joshleaves/sakurayaku.git

# 2. Mettre à jour le projet
# Cette commande récupérera les derniers changements de la version en ligne
# pour les appliquer à la version sur votre machine
~/sakurayaku/ $ git pull
```

## Initialiser le projet ludared

Le projet ne contient pas de fichiers propriétaires ou sous copyright, uniquement les recettes de décomposition, et les fichiers modifiés. Ainsi, vous devrez fournir vous-même les fichiers originaux, et les placer dans le dossier `sources`.

```bash
~/sakurayaku/ $ ludared sources list
SakTaiCD1_Track1.bin
  Label:  Sakura Taisen (Japan) (Disc 1) (6M) (Track 1).bin
  Size:   606.5 MiB (635,917,296 bytes)
  SHA256: 98892052bc069767171e2db2fc2bce45760163b11412f35037a22ed398d9ea58
```

Vous pouvez utiliser `ludared doctor` pour vérifier que les sources sont les bonnes:

```bash
~/sakurayaku/ $ ludared doctor
✓ All sources OK
✓ Doctor check passed
```

Une fois les fichiers sources au bon endroit, vous pourrez lancer la recette de décomposition:

```bash
~/sakurayaku/ $ ludared unpack
✓ Restored 1792 artifact(s) from 8 decode(s)
```

Cette commande permet de décomposer totalement l'iso en arbre de sous-fichiers sur lesquels vous pourrez travailler

## Travailler sur le projet ludared

Le dossier `worksaces` contient tous les fichiers modifiés par **SakuraYaku** et qui seront insérés dans l'iso du jeu pour sa reconstruction. La section [Contenus](README.md#contenus) indique comment travailler avec les divers types de fichiers.

## Construire un iso modifié

À tout moment, vous pouvez produire un iso modifié et tester vos changements.

```bash
~/sakurayaku/ $ ludared build
✓ Built builds/Sakura Taisen (Japan) (Disc 1) (6M) (Track 1).bin
```

Votre iso reconstruit sera disponible dans le dossier `builds`. Attention: chaque opération de build effacera le build précédent.
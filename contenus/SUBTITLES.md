# Sous-titres de la séquence d'introduction

**Fichiers concernés:**
- `SAKURA1/LOGO.SH2/SUBTITLES/{nn}.bmp` où `nn` est un décimal de `00` à `16`.
  Des [BMP](https://fr.wikipedia.org/wiki/Windows_bitmap) indexés. La couleur d'index 0 (ce joli jaune criard) indique la transparence. Tout le reste sera visible.

## Description

Ces images correspondent aux sous-titres de la séquence d'introduction du jeu. Les 11 à 16 semblent ne pas être utilisées par le jeu, l'équipe US ne les ayant même pas remplacées.

Il y a des limites sur la quantité d'espace disponible en VRAM pour la totalité de ces images. 

Vous pouvez les modifier, mais:
- La largeur de chaque image DOIT être un multiple de `8px`.
- La hauteur de chaque image (à part les _placeholder_) doit être de `8px` ou de `16px`[^hauteur]. 
- Au total, les 17 images doivent tenir dans une surface totale de `2 224×16px` de base, et de `2 560×16px` avec le hack "safe".

L'encodeur valide explicitement ces règles avant d'insérer l'image.

## Notes

Pour pallier les limites d'espace disponible pour ces images, les images 11 à 16 (celles non utilisées) ont été remplacées par un _placeholder_ (une image totalement transparente de `8×2px`). De plus, un hack "safe" permet d’exploiter une zone de VRAM supplémentaire, qui semble inutilisée pendant l’introduction.

Une fonctionnalité a été ajoutée à l'encodeur qui lui permet d'utiliser une image à la place d'une autre. Ainsi, lorsqu’une image de `8×2px` est rencontrée, l’encodeur réutilise automatiquement l’image précédente. Le patch s'en sert pour `10.bmp`, qui réutilise donc `09.bmp` en jeu sans avoir à dupliquer ses données.

C'est notamment utile car la ligne finale "_Rugis\nPuissant corps d'élite impérial !_" est séparée en deux sous-titres dans la version japonaise, alors qu'elle fonctionne mieux sur un sous-titre de deux lignes (mais elle occupe aussi plus d'espace, d'où le hack "safe").

Dans le cas où vous désireriez qu'une ligne de sous-titres soit transparente, remplacez-la par une image transparente de `8x16px`.

***
[^hauteur]: Une tentative à `24px` a donné du _garbage_, et des tentatives intermédiaires n'ont pas été essayées car jugées sans intérêt.
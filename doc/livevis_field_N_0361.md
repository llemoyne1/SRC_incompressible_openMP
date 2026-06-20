# 0361 — Champ live `N` / population particulaire

Cette mise à jour ajoute le champ `N` à la visualisation live SRC/MPCD, dans le chemin CUDA compact et dans le fallback CPU/host.

## Définition

`N` est le nombre de particules fluides déposées dans chaque cellule de la grille de visualisation live. Les alias acceptés sont :

- `N`
- `n`
- `count`
- `population`
- `particle_count`
- `cell_count`

Le champ est volontairement distinct de `mass`/`density` : `mass` somme les masses particulaires, tandis que `N` compte les particules. Les deux champs ne coïncident que si toutes les masses particulaires valent 1.

## Grille de visualisation

La valeur de `N` est comptée sur la grille live `SRC_LIVE_VIS_NX` × `SRC_LIVE_VIS_NY`. Si cette grille est plus grossière que la grille collision `Nx` × `Ny`, chaque pixel live agrège plusieurs cellules SRC/MPCD. Pour visualiser la population par cellule collision, utiliser :

```bash
SRC_LIVE_VIS_NX=$NX \
SRC_LIVE_VIS_NY=$NY \
SRC_LIVE_VIS_FIELD=N
```

## Réglages conseillés

Pour détecter les cellules vides ou les surpopulations, éviter le lissage :

```bash
SRC_LIVE_VIS_FIELD=N \
SRC_LIVE_VIS_CLIP=-1 \
SRC_LIVE_VIS_SMOOTH_PASSES=0 \
SRC_LIVE_VIS_COLORMAP=thermal
```

Dans le chemin CUDA compact, si `SRC_LIVE_VIS_CLIP<=0`, l'échelle automatique utilisée pour `N` est :

```text
scale_N = max(1, 2 * activeFluid / (liveNx * liveNy))
```

Ce choix donne une référence visuelle fondée sur la population moyenne par cellule live et évite une saturation immédiate sur les affichages grossiers.

## Fichiers modifiés

- `src/live_visualization_0335.cpp` : fallback CPU/host, ajout de `sumCount` et des alias du champ `N`.
- `src/cuda_live_field_0337.cu` : chemin CUDA compact, ajout d'un accumulateur `d_count`, dépôt par `atomicAdd(..., 1.0)`, rendu du champ `N`, échelle automatique spécifique.
- `livevis_control.kv` : commentaire de configuration mis à jour.
- `doc/README_live_visualization_0335a.md` : documentation utilisateur mise à jour.

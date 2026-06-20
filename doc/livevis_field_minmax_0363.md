# 0363 — Affichage min/max du champ live

Cette mise à jour ajoute l'affichage du minimum et du maximum du champ scalaire rendu dans la fenêtre livevis.

## Chemin CUDA compact

Le chemin `SRC_LIVE_VIS_CUDA_FIELD=1` calcule les min/max sur GPU après construction du champ scalaire et après les passes de lissage. Pour limiter le coût, la réduction est faite en deux étapes :

1. un kernel CUDA calcule un min/max par bloc ;
2. seuls ces min/max par bloc sont copiés sur l'hôte et réduits côté CPU.

Cela évite de recopier tout le champ scalaire `nx * ny` à chaque frame. Pour une grille live `1200 x 640`, le transfert supplémentaire est de l'ordre de quelques kilo-octets par frame au lieu de plusieurs mégaoctets.

Les nouveaux champs de diagnostic CUDA sont :

- `minMaxComputed` ;
- `fieldMin` ;
- `fieldMax` ;
- `fieldScale` ;
- `minMaxSeconds`.

Le titre de fenêtre reçoit par exemple :

```text
SRC/MPCD live 0335a | N | cmap=thermal | cuda_field_0337 min=0 max=23 scale=24 | step 1200 | t=0.600
```

## Chemin CPU/host

Le fallback CPU calcule les min/max sur `displayScalar`, donc sur le champ effectivement affiché après lissage et relaxation temporelle.

## Fichiers modifiés

- `include/cuda_live_field_0337.h`
- `src/cuda_live_field_0337.cu`
- `src/main_src_mpcd_base.cpp`
- `src/live_visualization_0335.cpp`
- `doc/README_live_visualization_0335a.md`

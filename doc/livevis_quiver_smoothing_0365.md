# 0365 — Lissage de l’overlay quiver

## Objectif

Le patch 0364 ajoutait un overlay quiver sous forme de segments vitesse, mais les vecteurs étaient échantillonnés directement depuis les vitesses moyennes locales de la grille live. En MPCD, ce champ vectoriel peut être très bruité, surtout lorsque la grille quiver est fine ou lorsque la population locale est faible.

Le correctif 0365 ajoute un lissage spatial optionnel des vecteurs quiver sur la grille décimée `quiverNx × quiverNy`.

## Contrôle

Nouveau contrôle :

```text
quiverSmoothPasses = -1
```

Sémantique :

- `quiverSmoothPasses < 0` : réutilise `smoothPasses` ;
- `quiverSmoothPasses = 0` : aucun lissage des vecteurs ;
- `quiverSmoothPasses > 0` : applique ce nombre de passes 3×3 aux vecteurs quiver.

Variables d'environnement équivalentes :

```bash
SRC_LIVE_VIS_QUIVER_SMOOTH_PASSES=2
MPCD_LIVE_VIS_QUIVER_SMOOTH_PASSES=2
```

## Exemple pour `N` + vecteurs lissés

Pour garder `N` non lissé tout en lissant les vecteurs :

```text
field = N
clip = -1
gain = 1
smoothPasses = 0
colormap = thermal
quiverNx = 60
quiverNy = 32
quiverScale = 12
quiverMinSpeed = 0
quiverSmoothPasses = 2
```

## Coût

Le lissage est effectué côté hôte sur les deux petits tableaux de taille `quiverNx × quiverNy`, après l’échantillonnage CUDA ou CPU. Pour `60 × 32`, le coût est négligeable par rapport au dépôt particulaire et au transfert RGBA.

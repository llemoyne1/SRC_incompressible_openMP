# 0306 — diagnostic CUDA des cellules aberrantes et outliers de vitesse

## Objectif

Le patch 0306 prolonge le diagnostic géométrique 0305. Il vise à distinguer deux phénomènes qui peuvent être confondus visuellement :

1. des cellules effectivement vides ou très pauvres ;
2. des cellules non vides, parfois bien peuplées, dont la vitesse cellulaire moyenne devient aberrante parce que la distribution de vitesses locale est déformée.

Le module reste passif : il ne déclenche pas le guard, ne répare pas les cellules vides, ne change aucune masse, aucun rôle et aucune vitesse.

## Position dans le step

Le diagnostic est calculé au même point que 0304/0305 : après SRC classic et après thermostat éventuel, sur la grille physique non shiftée, juste avant le resampling post-SRC.

## Mesures ajoutées

Le fichier `cuda_resampling_adaptive_flag_0304.csv` reçoit des colonnes 0306 :

- population bins : `N=1`, `N=2`, `N=3`, `N=4..6`, `N=7..Nmin`, `N>=Nmin` ;
- nombre de cellules à vitesse élevée dans chaque bin ;
- `maxAbsU` par bin ;
- `maxKBT` par classe géométrique bulk/wall/solid/open/corner ;
- pire cellule instantanée : coordonnées, population, masse, vitesse, norme de vitesse, énergie relative, estimateur kBT et classe géométrique.

Le seuil d'outlier est contrôlé par :

```bash
MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD=1.0
```

Par défaut il reprend le seuil 0305 `MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U` si celui-ci est défini.

## Interprétation attendue

Si les vitesses aberrantes viennent de cellules pauvres, on s'attend à voir des valeurs fortes dans :

```text
maxAbsUN1_0306, maxAbsUN2_0306, maxAbsUN3_0306
```

Si elles se produisent dans des cellules bien peuplées, le signal apparaîtra plutôt dans :

```text
maxAbsUNgeNmin_0306
```

Si elles sont associées aux parois/solides, les maxima géométriques montreront :

```text
maxKBTWallAdjacent0306, maxKBTSolidAdjacent0306,
worstCellWallAdjacent0306, worstCellSolidAdjacent0306
```

## Cas de validation

Le script `run_cuda_resampling_outlier_diagnostics_0306.sh` lance par défaut :

- backward step ;
- Von Kármán cylindre ;
- Taylor--Green avec trou initial.

Poiseuille peut être activé avec `RUN_POISEUILLE=1`.


# 0143 — Relative segmented inlet/outlet boundaries

## Objectif

Le patch 0143 remplace l'ancien mécanisme d'ouverture partielle

```text
openBoundaryApertureEnable = true
leftOpenYMin = ...
leftOpenYMax = ...
...
```

par une définition compacte, relative et explicite des segments ouverts.  Le but est de permettre plusieurs `inlet` et/ou `outlet` sur une même face, par exemple une injection en haut de la face gauche et une sortie en bas de cette même face, tout en gardant les portions non couvertes comme parois solides.

Les anciens paramètres d'aperture sont volontairement supprimés : un ancien script échoue maintenant au parsing au lieu de produire une configuration hybride difficile à contrôler.

## Formalisme retenu

Un segment est déclaré par une seule ligne :

```text
openBoundarySegmentK = face mode sMin sMax ux uy type mass
```

avec :

```text
face = left | right | bottom | top
mode = inlet | outlet
sMin, sMax = coordonnées tangentielles relatives dans [0,1]
ux, uy = vitesse d'injection finale pour un inlet, ignorée pour un outlet
type = type particulaire injecté
mass = masse particulaire injectée
```

La coordonnée `s` est toujours relative :

- face `left` ou `right` : `s = (y - yMin)/(yMax - yMin)` ;
- face `bottom` ou `top` : `s = (x - xMin)/(xMax - xMin)`.

Aucun mode `physical` n'est conservé dans ce patch afin d'éviter des aiguillages supplémentaires.

## Exemple : remplissage par une ouverture locale

```text
bcLeft   = solid
bcRight  = solid
bcBottom = solid
bcTop    = solid

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 1
openBoundarySegment0 = left inlet 0.48 0.52 0.10 0.00 0 1.0

inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletTargetOccupancy = 20
```

Ici seule une petite ouverture centrée en hauteur injecte du fluide. Le reste de la face gauche reste une paroi solide.

## Exemple : inlet et outlet sur la même face

```text
bcLeft   = solid
bcRight  = solid
bcBottom = solid
bcTop    = solid

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet  0.65 0.90  0.10 0.00  0 1.0
openBoundarySegment1 = left outlet 0.10 0.35  0.00 0.00  0 1.0

openBoundaryOutletMode = neumann
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletTargetOccupancy = 20
```

C'est le cas de validation ajouté par :

```bash
bash scripts/run_same_face_segmented_io_validation_0143.sh
```

## Règles de validation

Le parser impose :

- `openBoundarySegmentCount <= 16` ;
- `0 <= sMin < sMax <= 1` ;
- pas de recouvrement entre segments sur une même face ;
- les segments doivent être placés sur des faces globalement wall-like (`solid`, `specular`, `bounceback`) ;
- on ne mélange pas `bcLeft=inlet/outlet` pleine face avec des segments sur cette même face ;
- les segments sont incompatibles avec une face périodique ;
- les segments utilisent le chemin réservoir `hard_cell_density` afin que les sorties convertissent les particules en `Inactive` et que les entrées réutilisent le pool inactif ;
- les outlets segmentés demandent `openBoundaryOutletMode=neumann` ou `hybrid` ; `balanced_flux` est refusé pour éviter une définition ambiguë du débit dans les configurations same-face ou multi-outlets ;
- en mode `hybrid` segmenté, seul le feedback outlet est conservé pour l'instant ; il faut donc garder `openBoundaryOutletHybridBlend=0`.

## Effet dans le code

Le traitement particulaire devient local par segment :

- une particule qui sort par un segment `outlet` est désactivée ;
- une particule qui sort par un segment `inlet` est considérée comme du backflow et désactivée ;
- une particule qui sort par une portion non couverte de la face est réfléchie comme sur une paroi solide ;
- le réservoir `hard_cell_density` reconstruit uniquement les cellules adjacentes aux segments `inlet` ;
- les particules injectées reçoivent le `type` et la `mass` déclarés dans le segment.

Côté Q6, les profils de flux de frontière sont maintenant construits par cellule de face à partir des segments relatifs. Les portions solides gardent un flux nul. Les outlets segmentés en mode `neumann` reprennent le flux normal local issu du champ de base.

## Compatibilité

Les conditions pleine face historiques restent disponibles :

```text
bcLeft = inlet
bcRight = outlet
```

mais elles ne doivent pas être combinées avec `openBoundarySegmentsEnable=true` sur la même face. Les anciens paramètres `openBoundaryApertureEnable`, `leftOpenYMin`, `rightOpenYMax`, etc. sont supprimés et déclenchent une erreur explicite.

## Tests effectués

Compilation du cœur :

```bash
g++ --std=c++17 -O2 -Wall -Wextra -fopenmp -Iinclude \
  src/main_src_mpcd_base.cpp src/params_io_base.cpp src/cell_grid.cpp \
  src/boundary_base.cpp src/fluid_domain.cpp src/immersed_solid.cpp \
  src/src_collision.cpp src/thermostat.cpp src/elliptic_projection.cpp \
  src/q6_projection_adapter.cpp src/src_mpcd_base.cpp src/runtime_summary.cpp \
  src/particle_state.cpp src/state_smpcd_io.cpp src/weighted_resampling.cpp \
  -o build/src_mpcd_base
```

Smoke test remplissage segmenté inlet seul :

```bash
RUN_ROOT=/tmp/test_fill_0143 \
FILL_STEPS=5 FILL_SUMMARY_EVERY=1 FILL_DUMP_EVERY=0 FILL_THREADS=2 \
bash scripts/run_injection_fill_resampling_validation_0139.sh
```

Smoke test same-face inlet/outlet :

```bash
RUN_ROOT=/tmp/test_segio_0143 \
SEGIO_STEPS=5 SEGIO_SUMMARY_EVERY=1 SEGIO_DUMP_EVERY=0 SEGIO_THREADS=2 \
bash scripts/run_same_face_segmented_io_validation_0143.sh
```

Les deux tests tournent en `classic` et `q6_resampling` avec `bc=[L:solid, R:solid, B:solid, T:solid]`, l'ouverture étant portée uniquement par les segments.

# 0307 — Diagnostics et prévention des cascades de split CUDA

## Motivation

Les diagnostics 0306 ont montré que certaines vitesses aberrantes ne proviennent pas d'une température relative locale excessive, mais de particules représentatives de masse quasi nulle dans des cellules proches des solides. Dans ce cas, un re-thermostatage relatif ne peut pas corriger le problème : `Krel` et `kBT` peuvent être nuls alors que la vitesse moyenne cellulaire `U = P/M` devient énorme parce que `M` est dégénérée.

Le mécanisme suspect est une cascade de split local : une cellule durablement pauvre, en particulier solid-adjacent, déclenche le guard très souvent, et la même masse représentative peut être divisée de façon géométrique.

## Objectif du patch

Le patch 0307 ajoute deux éléments dans le module `cuda_resampling_population_guard_0297` :

1. des diagnostics sur la masse des donneurs et des particules créées par split ;
2. une prévention optionnelle empêchant les splits qui créeraient des particules trop légères.

Par défaut, le comportement reste diagnostic-only sauf activation explicite de :

```bash
MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
```

## Nouveaux diagnostics

Le fichier existant :

```text
<outputDir>/cuda_resampling_population_guard_0297.csv
```

gagne les colonnes :

```text
splitSafety0307
preferMaxMassDonor0307
splitDonorMinMass0307
splitNewParticleMinMass0307
solidAdjacentDonorMinMass0307
solidAdjacentSplitMode0307
solidAdjacentHaloCells0307
tinyMassThreshold0307
splitCandidatesSolidAdjacent0307
splitAppliedSolidAdjacent0307
splitSkippedDonorMass0307
splitSkippedNewMass0307
splitSkippedSolidAdjacent0307
splitFromMassBelow0p5_0307
splitFromMassBelow0p25_0307
splitFromMassBelow0p1_0307
minSplitDonorMass0307
minSplitNewParticleMass0307
minPostSplitDonorMass0307
```

Ces colonnes permettent de vérifier si les splits partent progressivement de donneurs de masse faible et si les événements se concentrent près des solides.

## Prévention optionnelle

Variables principales :

```bash
MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307=0.5
MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307=0.25
```

Avec ces valeurs, un donneur ne peut pas être splitté s'il est trop léger, et une particule nouvellement créée ne peut pas avoir une masse inférieure au seuil demandé.

Pour les cellules proches solides :

```bash
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_HALO_CELLS_0307=1
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=0   # normal
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=1   # cautious
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=2   # off
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_DONOR_MIN_MASS_0307=1.0
```

Le mode `cautious` impose un plancher de masse donneur plus strict près des solides. Le mode `off` désactive les splits dans les cellules solid-adjacent, sans empêcher les merges ailleurs.

## Validation prévue

Le runner fourni compare quatre modes :

```text
diag_only
safe_floor
solid_cautious
solid_off
```

sur backward step et Von Kármán, en stressant volontairement le guard avec `GUARD_EVERY=1`.

Commande typique :

```bash
BIN=build/src_mpcd_base_cuda_0307 \
FORCE_REBUILD=0 \
RUN_STEP=1 \
RUN_VK=1 \
STEP_NX=128 STEP_NY=48 STEP_STEPS=6000 STEP_UIN=0.60 \
VK_NX=128 VK_NY=48 VK_STEPS=6000 VK_UIN=0.45 \
GUARD_EVERY=1 \
bash scripts/run_cuda_resampling_split_safety_0307.sh
```

Sorties :

```text
dev_history/artifacts/gpu_cuda_resampling_split_safety_0307/
  cuda_resampling_split_safety_0307_run_manifest.csv
  cuda_resampling_split_safety_0307_per_run.csv
```

## Critères d'interprétation

Le mode `diag_only` doit reproduire le comportement antérieur et révéler si les donneurs deviennent de plus en plus légers :

```text
minSplitDonorMass0307
minPostSplitDonorMass0307
splitFromMassBelow0p5_0307
splitFromMassBelow0p25_0307
splitFromMassBelow0p1_0307
```

Les modes de prévention doivent réduire ou éliminer les splits depuis masse faible :

```text
splitSkippedDonorMass0307 > 0
minPostSplitDonorMass0307 >= seuil
splitFromMassBelow0p25_0307 réduit
```

Ils doivent aussi conserver les budgets déjà validés :

```text
maxAbsCellMassError
maxAbsCellMomentumError
maxAbsCellKrelError0298
```

## Limites

0307 ne résout pas encore la question physique complète : « par quoi remplir une cellule proche paroi naturellement vidée ? ». Il empêche d'abord le mécanisme pathologique de création de particules quasi sans masse. Les étapes suivantes pourront ensuite introduire un traitement wall-aware ou un réservoir statistique contrôlé, mais sur une base où les masses représentatives ne dégénèrent plus.

# 0308 — Consolidation du resampling CUDA avec sécurité de split

## Statut

Ce jalon consolide le mode nominal du resampling CUDA post-SRC après les diagnostics 0306/0307.
Il ne modifie pas l'ordre physique du step SRC classic :

```text
advection / conditions limites CUDA
→ collision SRC CUDA
→ thermostat CUDA si activé
→ resampling post-SRC CUDA
```

Le changement consolidé concerne uniquement le module de population guard local : les splits représentatifs ne doivent plus créer de particules de masse dégénérée.

## Cause identifiée

Les diagnostics 0306 ont mis en évidence des cellules proches solides contenant quelques particules de masse quasi nulle et des vitesses cellulaires énormes. Le pire profil observé était du type :

```text
N ≈ 2
M ≈ 1e-9
|U| ≫ 1
solidAdjacent = 1
Krel ≈ 0
kBT ≈ 0
```

Ce profil ne correspond pas principalement à un excès de température relative. Il correspond à une dégénérescence masse/vitesse, avec `U = P/M` mal conditionné quand `M` devient très petit.

Les diagnostics 0307 ont confirmé la cause : le split local pouvait être répété sur des particules déjà allégées, générant une cascade géométrique de masses.

## Mode nominal consolidé

Le mode nominal provisoire active :

```bash
MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307=0.5
MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307=0.25
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=0
```

Interprétation :

- choisir le donneur local le plus massif quand une cellule pauvre est splittée ;
- interdire le split d'un donneur trop léger ;
- interdire la création d'une nouvelle particule sous le plancher de masse ;
- conserver pour l'instant le split près des solides, mais le protéger par les mêmes planchers.

Le mode `solid_off` reste un mode diagnostic, pas le mode nominal : il peut laisser des cellules solid-adjacent durablement pauvres.

## Scripts modifiés / ajoutés

- `scripts/src_gpu_resampling_demo_common_0303.sh` : active maintenant la sécurité de split par défaut dans les démonstrations resampling.
- `scripts/build_src_mpcd_cuda_0308.sh` : build CUDA consolidé, liant 0295--0307.
- `scripts/run_cuda_resampling_split_safety_consolidated_0308.sh` : validation de consolidation via le diagnostic outlier 0306 avec sécurité de split activée.

## Validation recommandée

```bash
OUT=build/src_mpcd_base_cuda_0308 \
CUDA_ARCH_FLAGS="--generate-code=arch=compute_89,code=sm_89 --generate-code=arch=compute_89,code=compute_89" \
bash scripts/build_src_mpcd_cuda_0308.sh
```

Puis :

```bash
BIN=build/src_mpcd_base_cuda_0308 \
FORCE_REBUILD=0 \
bash scripts/run_cuda_resampling_split_safety_consolidated_0308.sh
```

Sorties principales :

```text
dev_history/artifacts/gpu_cuda_resampling_split_safety_consolidated_0308/
  cuda_resampling_split_safety_consolidated_0308_run_manifest.csv
  cuda_resampling_split_safety_consolidated_0308_per_run.csv
  cuda_resampling_split_safety_consolidated_0308_timeseries.csv
  cuda_resampling_split_safety_consolidated_0308_worst_cells.csv
```

## Critères attendus

Sur backward step et Von Karman :

```text
maxWorstAbsU ≲ O(1)
sumHighUN1 = 0 ou très faible
sumHighUNgeNmin = 0 ou très faible
worstCellMass non dégénérée
pas de worst cell M ≈ 1e-9
```

La validation récente avec sécurité activée montrait des pires cellules de masse normale (`N ≈ 20`, `M ≈ 20`) et des vitesses maximales de cellule inférieures à `1`, contre des vitesses de plusieurs dizaines lorsque la cascade de split était autorisée.

## Points non résolus

Ce jalon ne résout pas encore la question générale du repeuplement des cellules structurellement vidées par la géométrie pariétale. Il empêche d'abord le mécanisme pathologique identifié : la fragmentation indéfinie de particules représentatives.

Les chantiers futurs restent :

- seuils effectifs wall/solid-aware ;
- mémoire eulérienne `last-valid` ;
- éventuel refill de cellules vides ;
- éventuel thermostat post-resampling borné, seulement pour les vrais excès de `Krel/kBT`.

# 0158 — optimisation ciblée des points chauds 0157

Ce zip différentiel applique uniquement trois corrections de performance identifiées par le profilage 0157. Il ne change pas les fonctionnalités physiques du code, les paramètres de simulation, ni les algorithmes SRC/Q6/resampling actifs.

## Modifications

1. `closed_capacity_virial` : retour immédiat dans `apply_closed_capacity_virial_kick()` lorsque `closedCapacityResponseEnable=false`. L'ancien chemin déposait les masses cellule avant de retourner un diagnostic vide.
2. Diagnostics resampling : lorsque `resamplingEnable=false`, `run_src_mpcd_base_step()` ne reconstruit plus le pool resampling et ne redépose plus les masses à chaque pas. Ces diagnostics sont conservés aux pas de résumé (`summaryEvery`) et au dernier pas.
3. Double redépôt post-guard/post-edit : séparation des flags `populationGuardEdited` et `planOrTransferEdited`. Si le population guard agit mais qu'aucune activation latente, extraction ou insertion n'agit ensuite, le second redépôt `post_edit` est évité.

## Fichiers modifiés ou ajoutés

```text
include/src_mpcd_base.h
src/src_mpcd_base.cpp
src/main_src_mpcd_base.cpp
src/closed_capacity_response.cpp
scripts/run_performance_profile_0158.sh
doc/README_0158_HOTSPOT_OPTIMIZATION.md
```

## Application

Depuis le dépôt où 0156 puis 0157 ont déjà été appliqués :

```bash
unzip -o SRC_MPCD_openmp_hotspot_0158_files_only.zip
chmod +x scripts/run_performance_profile_0158.sh
```

## Compilation

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

ou, pour une option portable :

```bash
BUILD_PROFILE=release ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Validation recommandée

Run standard comparable au profil 0157 :

```bash
RUN_ROOT=runs/performance_profile_0158 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="classic q6 q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0158.sh
```

Run ciblé resampling :

```bash
RUN_ROOT=runs/performance_profile_0158_resampling_2000 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=2000 \
./scripts/run_performance_profile_0158.sh
```

## Fichiers de sortie

```text
perf_summary_0158.csv
phase_profile_0158.csv
phase_profile_top_0158.csv
```

Comparer prioritairement avec les fichiers 0157 :

```text
perf_summary_0157.csv
phase_profile_0157.csv
phase_profile_top_0157.csv
```

Les compteurs fonctionnels à surveiller sont `q6Iterations`, `resampMRelRms`, `resampTransferPairs` et `resampSelectedDonorParticles`. Ils doivent rester cohérents avec 0157 à configuration identique.

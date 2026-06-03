# 0157 — Profilage fin OpenMP du code SRC/MPCD incompressible

## Objectif

Ce différentiel ajoute une instrumentation temporelle légère au pas de temps SRC/MPCD afin d'identifier les points chauds sans modifier les fonctionnalités physiques du code.

Le patch mesure les grandes phases de `run_src_mpcd_base_step` :

- accélération/streaming ;
- conditions aux limites ;
- solide immergé ;
- collision SRC ;
- projection Q6 ;
- fermeture virielle/capacité ;
- thermostat ;
- maintien du débit moyen ;
- phases resampling : pool, dépôt pondéré, guard, activation latente, extraction, insertion, remap, renormalisation thermique, mass guard, redépôts et diagnostics.

Le patch ne change pas les seuils, les plans, les transferts, les projections ou les opérations particulaires. Il ne fait qu'accumuler des durées et écrire un CSV de profilage.

## Fichiers modifiés ou ajoutés

```text
include/src_mpcd_base.h
src/src_mpcd_base.cpp
src/main_src_mpcd_base.cpp
scripts/run_performance_profile_0157.sh
doc/README_0157_FINE_PERFORMANCE_PROFILING.md
```

## Préparation

Appliquer le zip différentiel depuis la racine du dépôt optimisé, c'est-à-dire après application de l'état 0156 :

```bash
cd SRC_openMP_optimized
unzip -o SRC_MPCD_openmp_profile_0157_files_only.zip
chmod +x scripts/run_performance_profile_0157.sh
```

## Compilation

Utiliser le script de compilation 0156, conservé comme script de build de référence pour cette phase :

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

Pour une compilation plus portable :

```bash
BUILD_PROFILE=release ./scripts/build_src_mpcd_base_optimized_0156.sh
```

Le binaire attendu est :

```text
build/src_mpcd_base
```

## Exécution recommandée

Test standard comparable aux mesures 0156 :

```bash
RUN_ROOT=runs/performance_profile_0157 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="classic q6 q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0157.sh
```

Test plus ciblé sur le resampling :

```bash
RUN_ROOT=runs/performance_profile_0157_resampling_2000 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=2000 \
./scripts/run_performance_profile_0157.sh
```

## Fichiers produits

Le script produit trois CSV globaux dans `RUN_ROOT` :

```text
perf_summary_0157.csv
phase_profile_0157.csv
phase_profile_top_0157.csv
```

Chaque sous-dossier de run contient aussi :

```text
summary_runtime.csv
phase_profile_0157.csv
params_used.kv
```

`perf_summary_0157.csv` reprend les indicateurs globaux de 0156 : temps total, temps final du runtime, itérations Q6 et compteurs resampling.

`phase_profile_0157.csv` contient toutes les phases instrumentées :

```text
case,threads,phase,total_s,ms_per_step,percent_total
```

`phase_profile_top_0157.csv` extrait les douze phases dominantes pour chaque couple `(case, threads)`.

## Lecture attendue

Pour identifier les points chauds, commencer par :

```bash
column -s, -t < runs/performance_profile_0157/phase_profile_top_0157.csv | less -S
```

Les phases à surveiller en priorité sont :

- `src_collision` ;
- `q6_projection` ;
- `resampling_deposit_initial` ;
- `resampling_pool_initial` ;
- `resampling_remap` ;
- `resampling_thermal_late` ou `resampling_thermal_after_remap` ;
- `resampling_post_remap_deposit` ;
- `thermostat`.

Si `q6_projection` domine, la suite logique est un profilage interne du solveur elliptique/CG : application opérateur, produits scalaires, updates vectoriels, réductions OpenMP.

Si les phases `resampling_*deposit*`, `resampling_pool*` ou `resampling_thermal*` dominent, la suite logique est d'optimiser les redépôts, les reconstructions de pool et la renormalisation thermique locale.

## Remarque sur le coût de l'instrumentation

Le profilage utilise `std::chrono::steady_clock` autour des grandes phases. Il introduit un faible overhead, acceptable pour localiser les points chauds. Pour les mesures de performance définitives, il faudra revenir au binaire non instrumenté ou garder les comparaisons strictement entre deux binaires instrumentés de la même manière.

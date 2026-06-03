# 0159 — Profilage fin Q6 / elliptic CG

Ce patch ajoute une instrumentation temporelle interne au chemin Q6 sans modifier les opérations numériques de projection, de collision, de resampling ou de thermostat. Il part de l'état 0158 et complète le profilage global `phase_profile_0159.csv` par un fichier dédié au verrou Q6/CG.

## Objectif

Le profil 0158 a montré que, après suppression des coûts parasites `closed_capacity_virial` et diagnostics resampling désactivés, la phase `q6_projection` devient le verrou principal : environ 70 % du mode `q6` et une part dominante du mode `q6_resampling` à 8 threads. Le patch 0159 décompose cette phase en deux niveaux :

- `q6_adapter` : dépôt particules -> cellules, construction du flux de base, préparation des conditions aux limites, appel de projection, reconstruction de la correction et application aux particules ;
- `elliptic_cg` : préparation du problème elliptique, jauge du second membre, boucle CG, application opérateur, produits scalaires/réductions, mises à jour vectorielles, reconstruction des flux projetés et statistiques finales.

## Fichiers produits

Le lanceur `scripts/run_performance_profile_0159.sh` écrit :

```text
RUN_ROOT/perf_summary_0159.csv
RUN_ROOT/phase_profile_0159.csv
RUN_ROOT/phase_profile_top_0159.csv
RUN_ROOT/q6_cg_profile_0159.csv
RUN_ROOT/q6_cg_profile_top_0159.csv
```

Le fichier principal pour décider du patch d'optimisation suivant est :

```text
q6_cg_profile_top_0159.csv
```

Il contient, pour chaque couple `(case, threads, group)`, les phases internes dominantes par pourcentage du groupe.

## Phases Q6 adapter

Les phases `q6_adapter` incluent notamment :

```text
q6_resize_workspace
q6_deposit_cell_velocity
q6_build_base_flux
q6_fill_alpha
q6_prepare_immersed_mask
q6_apply_immersed_alpha
q6_target_divergence
q6_setup_boundary_conditions
q6_project_face_field
q6_capacity_strength
q6_build_scaled_fluxes
q6_enforce_immersed_flux
q6_div_projected_after
q6_solid_leak_stats
q6_face_correction_to_cell
q6_build_corrected_cell_velocity
q6_div_cell_after
q6_apply_particle_velocity_correction
```

## Phases elliptic / CG

Les phases `elliptic_cg` incluent notamment :

```text
project_div_before
project_build_solve_base_flux
project_zero_alpha_faces
project_div_for_solve
project_build_rhs
project_rhs_gauge
cg_initialize
cg_rhs_norm_and_stats
cg_apply_operator
cg_dot_pAp
cg_axpy_phi_residual
cg_periodic_mean_removal
cg_dot_residual
cg_update_direction
cg_final_mean_removal
cg_final_residual
project_build_correction_flux
project_div_after
project_stats_div_before
project_stats_target
project_stats_div_after
project_stats_correction_flux
project_stats_projected_flux
```

## Application

Depuis le dépôt déjà patché en 0158 :

```bash
unzip -o SRC_MPCD_openmp_q6cg_profile_0159_files_only.zip
chmod +x scripts/run_performance_profile_0159.sh
```

## Compilation

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

ou, pour une compilation plus portable :

```bash
BUILD_PROFILE=release ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Run standard

```bash
RUN_ROOT=runs/performance_profile_0159 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="classic q6 q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0159.sh
```

## Run ciblé Q6

Pour réduire le bruit et analyser uniquement le verrou Q6 :

```bash
RUN_ROOT=runs/performance_profile_0159_q6_2000 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6 q6_resampling" \
STEPS=2000 \
./scripts/run_performance_profile_0159.sh
```

## Lecture rapide

```bash
column -s, -t < runs/performance_profile_0159/q6_cg_profile_top_0159.csv | less -S
```

Les lignes à regarder en priorité sont celles où `group=elliptic_cg` et `threads=8`. Si `cg_apply_operator` domine, la suite logique est une optimisation stencil/cache/fusion operator. Si `cg_dot_pAp` et `cg_dot_residual` dominent, le verrou principal est la réduction globale OpenMP. Si les phases `project_*stats*` dominent, on pourra déplacer certains diagnostics hors des pas non résumés.

## Validation attendue

Les compteurs fonctionnels doivent rester cohérents avec 0158 :

```text
q6Iterations
q6ResidualRel
q6DivAfterProjectedFluxRms
resampMRelRms
resampTransferPairs
resampSelectedDonorParticles
```

Le patch mesure le code ; il n'est pas censé accélérer la simulation. Une petite surcharge est normale, surtout à faible nombre de steps.

# SRC/MPCD incompressible — branche `SRC_GPU`

Ce dépôt contient la branche CUDA/OpenMP du code `SRC_incompressible_openMP`. Le jalon courant fournit un chemin **SRC/MPCD classic full CUDA résident** pour les cas où la fermeture liquide n'est pas activée, tout en conservant les modules CPU/OpenMP ou hybrides nécessaires à la fermeture liquide.

## Terminologie utilisée dans cette branche

Dans ce dépôt, **SRC classic** désigne le pas MPCD complet suivant :

```text
advection / streaming des particules
+ décalage aléatoire de grille
+ rotation / collision SRC
+ thermostat cellulaire
```

La **fermeture liquide incompressible/faiblement compressible** est une extension séparée :

```text
SRC classic
+ projection Q6
+ resampling pondéré
+ fermeture virielle / réponse de capacité
```

Il ne faut donc pas assimiler Q6, resampling ou viriel au SRC classic. Le jalon CUDA courant porte sur le SRC classic. Q6 CUDA reste un chantier futur séparé.

## État validé au jalon 0286

Après les validations 0260--0286, la branche dispose d'un chemin résident CUDA pour les familles SRC classic suivantes :

| Famille | Chemin validé | Statut |
|---|---|---|
| périodique / Taylor--Green | streaming + collision + thermostat CUDA | validé |
| wall-simple / Poiseuille | paroi + SRC + thermostat CUDA | validé |
| solide / obstacle rectangle / step | solide fixe + SRC + thermostat CUDA | validé |
| solide circulaire périodique | réflexion cercle CUDA + SRC + thermostat CUDA | validé |
| piston / mobile wall legacy | mobile wall + SRC CUDA, thermostat CUDA post-CPU si une étape CPU est intercalée | validé |
| inlet/outlet full-face | inlet/outlet résident CUDA + SRC + thermostat CUDA | validé |
| inlet/outlet segmenté | inlet/outlet segmenté résident CUDA + SRC + thermostat CUDA | validé |
| inlet/outlet full-face + cylindre | inlet/outlet résident CUDA + cercle solide + SRC + thermostat CUDA | validé |

Les validateurs consolidés vérifient `failed_metrics=0` sur les familles testées, avec thermostat CUDA actif et température ramenée à la cible. Le jalon 0285 a validé le cas `open_circle_obstacle_classic` en `64x64_s300` et `128x128_s300`, avec `ioFullfaceResidentFlag=1`, `immersedCircleFlag=1`, `fusedSrcThermostatUse=1` et `thermostatGpuAppliedFraction=1`.

## Compilation

Depuis la racine du dépôt :

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
bash scripts/build_src_mpcd_cuda_0286.sh
```

Le binaire CUDA consolidé est produit par défaut dans :

```text
build/src_mpcd_base_cuda_0286
```

Les flags d'architecture CUDA peuvent être transmis par l'environnement :

```bash
CUDA_ARCH_FLAGS="-arch=sm_89" bash scripts/build_src_mpcd_cuda_0286.sh
```

Le chemin CPU/OpenMP explicite reste disponible :

```bash
bash scripts/build_src_mpcd_base.sh
```

## Validation principale

Validation consolidée du SRC classic full CUDA :

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_src_classic_full_consolidated_0286.sh
```

Sorties attendues :

```text
dev_history/artifacts/gpu_cuda_src_classic_full_consolidated_0286/cuda_src_classic_full_consolidated_0286_manifest.csv
dev_history/artifacts/gpu_cuda_src_classic_full_consolidated_0286/cuda_src_classic_full_consolidated_0286_summary.txt
```

Critère nominal :

```text
result=PASS
errors=none
```

Le consolidé 0286 réexécute les validateurs de référence suivants avec le binaire 0286 :

```text
0281 : thermostat boundary-aware wall / rectangle / piston / IO full-face / IO segmenté
0284 : cercle solide périodique
0285 : cercle solide + inlet/outlet full-face
```

## Démonstrations SRC classic CUDA

Les scripts de démonstration produisent des dumps fréquents, par défaut tous les `100` steps, afin de faciliter les animations :

```bash
bash scripts/run_demo_src_classic_cuda_all_0286.sh
```

Scripts individuels :

```text
scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh
scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh
scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh
scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh
```

La démonstration Von Karman utilise désormais le chemin 0285 : inlet/outlet full-face résident CUDA, cylindre solide circulaire CUDA, collision SRC CUDA et thermostat CUDA fusionné.

## Lancement utilisateur : CUDA ou OpenMP

Le wrapper général de branche reste :

```bash
bash scripts/run_src_mpcd_cuda_primary_0275.sh --backend cuda params.kv
```

et le chemin OpenMP explicite :

```bash
bash scripts/run_src_mpcd_cuda_primary_0275.sh --backend openmp params.kv
# ou
bash scripts/run_src_mpcd_openmp_0275.sh params.kv
```

Le wrapper général est volontairement conservateur lorsque `projectionEnable`, `resamplingEnable`, `closedCapacityResponseEnable` ou d'autres modules de fermeture liquide sont actifs. Dans ces cas, il ne doit pas forcer un fast path classic-only qui garderait l'état hôte obsolète avant Q6, resampling ou viriel.

## Architecture CUDA

L'architecture CUDA est organisée autour de deux idées : état persistant et chemins spécialisés par famille de frontière.

| Couche | Rôle | État |
|---|---|---|
| état particulaire persistant | positions, vitesses, masses, rôles et métadonnées sur GPU | actif pour les chemins résidents validés |
| workspace cellule persistant | dépôts, moments, vitesses moyennes, énergie thermique | actif dans les chemins résidents optimisés |
| streaming / frontières | périodique, paroi, rectangle/step, cercle, piston, inlet/outlet | validé par familles |
| collision SRC | rotation par cellule, signes aléatoires, gestion des rôles et masses | validé CUDA résident |
| thermostat | rescale thermique cellulaire | validé CUDA boundary-aware |
| Q6 | projection elliptique incompressible | CPU/OpenMP pour l'instant |
| resampling | support particulaire, extraction/insertion/remap | chemin CPU/OpenMP et briques CUDA déjà explorées, non assimilé au SRC classic full CUDA |
| viriel / capacité | réponse pression-density et charge pariétale | CPU/OpenMP ou hybride, chantier CUDA futur |

## Invariant important du thermostat

La collision SRC peut utiliser des moyennes cellule enrichies par particules virtuelles de paroi ou de solide. Le thermostat, lui, doit reconstruire ses moments à partir des seules particules réelles après collision.

```text
moyenne collision SRC       = particules réelles + particules virtuelles éventuelles
moyenne thermostat CUDA     = particules réelles post-collision uniquement
```

Pour les cas classic-only, le chemin fusionné est valide :

```text
frontière / streaming CUDA -> collision SRC CUDA -> thermostat CUDA
```

Pour les cas où une étape CPU peut modifier vitesses ou masses après collision, le thermostat fusionné ne doit pas être utilisé :

```text
collision SRC CUDA -> Q6/resampling/viriel/capacité CPU -> thermostat CUDA post-CPU
```

Ce second ordre est celui validé pour le piston/mobile wall.

## Conditions limites validées

| Famille | Script de validation typique | Remarque |
|---|---|---|
| périodique | `run_cuda_classic_src_periodic_resident_0260.sh` | socle résident classique |
| wall-simple | `run_cuda_persistent_src_thermostat_wall_0276.sh` | thermostat CUDA avec moments réels post-collision |
| solide rectangle | `run_cuda_persistent_src_thermostat_solid_0277.sh` | obstacle fixe / rectangle |
| piston / mobile wall | `run_cuda_persistent_src_thermostat_piston_0278.sh` | thermostat CUDA post-CPU |
| inlet/outlet full-face | `run_cuda_persistent_src_thermostat_io_fullface_0279b.sh` | résident actif après correctif 0280c |
| inlet/outlet segmenté | `run_cuda_persistent_src_thermostat_io_segmented_0280c.sh` | résident actif, état partagé |
| cercle périodique | `run_cuda_persistent_src_thermostat_circle_0284.sh` | réflexion cercle CUDA + SRC + thermostat |
| cercle + inlet/outlet | `run_cuda_persistent_src_thermostat_circle_io_0285.sh` | cylindre / Von Karman, full-face résident |
| consolidé final | `run_cuda_src_classic_full_consolidated_0286.sh` | validation globale 0276--0285 |

## Résultats représentatifs

| Validateur | Cas | Grille | Statut | Speedup total observé |
|---|---|---:|---|---:|
| IO full-face 0279b | `open_rect_obstacle_full` | `64x64_s300` | PASS | 1.74x |
| IO full-face 0279b | `open_rect_obstacle_full` | `128x128_s300` | PASS | 3.27x |
| IO segmenté 0280c | `segmented_u_turn_full` | `64x64_s300` | PASS | 1.91x |
| IO segmenté 0280c | `segmented_u_turn_full` | `128x128_s300` | PASS | 5.11x |
| cercle périodique 0284 | `periodic_circle_obstacle_classic` | `64x64_s300` | PASS | 0.47x environ |
| cercle périodique 0284 | `periodic_circle_obstacle_classic` | `128x128_s300` | PASS | 0.80x environ |
| cercle + IO 0285 | `open_circle_obstacle_classic` | `64x64_s300` | PASS | 1.60x |
| cercle + IO 0285 | `open_circle_obstacle_classic` | `128x128_s300` | PASS | 3.00x |

Les petits cas wall/solid/périodiques ne doivent pas être interprétés comme des benchmarks définitifs : sur des runs courts, le coût fixe de synchronisation et de validation domine. Les gains deviennent nets pour les chemins inlet/outlet résidents, où l'état GPU partagé évite davantage de transferts.

## Fichiers et organisation

```text
src/                    sources C++/CUDA du solveur
include/                en-têtes
scripts/                builds, validateurs, lanceurs d'exemples
doc/                    documentation technique récente
dev_history/artifacts/  CSV, logs et artefacts de validation
init/                   états initiaux .smpcd
runs/                   sorties de simulation
```

Les nouveaux documents Markdown techniques doivent être placés dans `doc/`, sauf ce `README.md` qui reste à la racine.

## Contraintes de développement à préserver

- Ne pas court-circuiter Q6, resampling ou viriel avec un fast path SRC classic-only.
- Garder le chemin OpenMP explicite disponible.
- Garder possible la réactivation future de Q6 CPU/OpenMP, resampling CUDA/CPU, viriel et Q6 CUDA.
- Ne pas confondre la validation SRC classic full CUDA avec la migration CUDA complète de la fermeture liquide.
- Pour les modifications distribuées, fournir des archives différentielles `*_files_only.zip`, pas de fichiers `.patch`.

## Prochain gros chantier

Le prochain chantier algorithmique majeur reste la migration CUDA de Q6. Elle doit être traitée séparément, car elle touche le solveur elliptique, les opérateurs divergence/gradient, les masques de conditions limites et la synchronisation avec resampling/viriel.

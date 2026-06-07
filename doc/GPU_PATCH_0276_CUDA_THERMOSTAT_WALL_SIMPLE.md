# GPU patch 0276 — CUDA thermostat wall-simple aware

## Objectif

Ce patch ouvre l'étape A du chantier thermostat CUDA. Il corrige le chemin CUDA persistant `deposit -> SRC collision -> thermostat` pour qu'il puisse être utilisé sur un cas `wall-simple` sans hériter de l'hypothèse périodique du validateur 0259.

Le périmètre reste volontairement limité :

- cas validateur : `poiseuille_wall_full` ;
- SRC classique uniquement ;
- `projectionEnable=false` ;
- `resamplingEnable=false` ;
- viriel / closed-capacity désactivés ;
- `wallThermalNoise=0`, comme dans les validations CUDA wall-simple précédentes.

Q6 CPU/OpenMP, resampling CUDA/CPU, viriel et une future migration Q6 CUDA ne sont pas court-circuités : les gardes existantes dans `src_collision.cpp` continuent d'interdire le chemin fusionné thermostat lorsque Q6 ou les kicks capacité/viriel doivent modifier les vitesses entre collision et thermostat.

## Audit du thermostat CUDA existant

Le noyau thermostat CUDA autonome de `src/cuda_cell_thermostat.cu` est suffisamment général lorsqu'il reçoit des moments cellulaires réels. Il utilise les tableaux `cellId`, `cellCount`, `cellUx`, `cellUy` et ne transforme que les particules `role == Fluid`.

Le problème de 0259 se trouve dans le chemin persistant fusionné de `src/cuda_persistent_mpcd_step.cu` :

1. dépôt des particules réelles ;
2. ajout éventuel des contributions virtuelles de paroi/solide pour la collision SRC ;
3. calcul de la vitesse moyenne de cellule ;
4. rotation SRC ;
5. thermostat relatif utilisant la même moyenne de cellule.

Cette séquence est correcte en périodique, car aucune contribution virtuelle n'est ajoutée. Elle est en revanche biaisée près des parois : la moyenne utilisée par le thermostat contient les particules virtuelles de collision, alors que le thermostat CPU reconstruit ses moments à partir des particules réelles post-collision uniquement.

## Correction 0276

Le patch ajoute deux noyaux dans `src/cuda_persistent_mpcd_step.cu` :

- `reset_thermostat_real_moments_persistent_0276_kernel` ;
- `deposit_thermostat_real_moments_persistent_0276_kernel`.

Après `src_rotate_persistent_kernel` et avant le calcul de l'énergie cinétique relative du thermostat, le chemin CUDA reconstruit maintenant :

- `cellMass` ;
- `cellPx` ;
- `cellPy` ;
- `cellUx` ;
- `cellUy` ;
- `cellKinetic` ;
- `cellScale` ;

à partir des seules particules réelles, avec les vitesses post-collision. `cellCount` reste celui du dépôt réel initial et n'inclut pas les particules virtuelles. La sémantique reproduit donc le thermostat CPU de `src/thermostat.cpp`.

La correction est appliquée aux trois variantes thermostat persistant :

- état transient `ParticleState` ;
- `CudaParticleState` avec workspace transient ;
- `CudaParticleState + CudaCellWorkspace`.

## Validation proposée

Construire :

```bash
bash scripts/build_src_mpcd_cuda_0276.sh
```

Validation courte discriminante :

```bash
GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_wall_0276.sh
```

Validation un peu plus robuste, si le smoke passe :

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_wall_0276.sh
```

Le résumé principal est écrit dans :

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_wall_0276/cuda_persistent_src_thermostat_wall_0276.csv
```

Critères attendus :

- `verdict=PASS` ;
- `failed_metrics=0` ;
- `thermostatGpuAppliedFraction=1` ;
- `thermostatCellsRescaled > 0` ;
- `thermostatKBTAfterMean` proche de la cible du cas.

## Suite logique

Si 0276 passe sur `wall-simple`, l'étape suivante peut être :

1. 0277 : brancher explicitement le cas thermostat wall-simple dans la politique CUDA principale lorsque `projectionEnable=false`, `resamplingEnable=false` et viriel désactivé ; ou
2. 0277 : étendre la même séparation `moyenne collision` / `moyenne thermostat` au validateur obstacle/solide rectangle.

Le choix dépendra du résultat du premier smoke 0276.

# 0317 — harnais de profiling objectif GPU SRC/MPCD vs `mpcd_vkkh_play.cu`

Ce jalon est volontairement **script-only** : il ne modifie pas le solveur SRC/MPCD. Il sert à mesurer objectivement les coûts avant toute nouvelle optimisation.

## Objectif

Comparer, sur un cas Von Kármán directement exécutable et aussi proche que possible :

- `src_cuda_v2` dans l’état rollback/restauré 0315m ;
- le code spécialisé `mpcd_vkkh_play.cu` fourni séparément.

Le harnais produit :

- un manifeste des runs ;
- un résumé `totalTime`, `steps`, `timePerStep` ;
- si Nsight Systems est disponible : temps kernels, CUDA API, memcpys HtoD/DtoH, memset, nombre de kernels, kernels par step, top kernels et top CUDA API calls ;
- sinon : un fallback robuste par `/usr/bin/time` et logs existants, sans instrumentation lourde du code.

## Fichiers ajoutés

- `scripts/run_gpu_objective_profile_0317.sh`
- `scripts/summarize_gpu_objective_profile_0317.py`
- `doc/GPU_OBJECTIVE_PROFILE_0317.md`

Aucun fichier `.patch` n’est fourni. Aucun fichier source du solveur n’est modifié.

## Utilisation recommandée

Depuis la racine du dépôt local :

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
```

Copier ou référencer le fichier spécialisé fourni :

```bash
# Option A : le copier dans le dépôt sous ce nom
cp /chemin/vers/mpcd_vkkh_play.cu ./mpcd_vkkh_play.cu

# Option B : ne pas copier, mais fournir son chemin
export VKKH_CU=/chemin/vers/mpcd_vkkh_play.cu
```

Lancer le profilage standard :

```bash
bash scripts/run_gpu_objective_profile_0317.sh
```

Pour un run plus court de fumée :

```bash
STEPS=1000 WARMUP=0 REPEATS=1 bash scripts/run_gpu_objective_profile_0317.sh
```

Pour reproduire le format long utilisé dans les mesures 0315m :

```bash
STEPS=10000 REPEATS=1 INACTIVE_SLOTS=100000 \
  bash scripts/run_gpu_objective_profile_0317.sh
```

Pour forcer Nsight Systems :

```bash
USE_NSYS=1 bash scripts/run_gpu_objective_profile_0317.sh
```

Pour désactiver Nsight Systems même s’il est présent :

```bash
USE_NSYS=0 bash scripts/run_gpu_objective_profile_0317.sh
```

Pour profiler seulement SRC ou seulement VKKH :

```bash
RUN_VKKH=0 bash scripts/run_gpu_objective_profile_0317.sh
RUN_SRC=0  bash scripts/run_gpu_objective_profile_0317.sh
```

## Paramètres de comparaison par défaut

Le cas par défaut est VK :

```text
Lx=3.0, Ly=1.0, NX=192, NY=64, gamma=20,
steps=10000, dt=0.001, kBT=0.001, Uin/U0=0.2,
cylinder=(0.65, 0.50, R=0.15), seed=1628505.
```

Côté SRC, le script utilise `scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh` avec :

- `DUMP_STATE_EVERY=0` ;
- `SUMMARY_EVERY=1000000000` ;
- `RESAMPLING_ENABLE=0` ;
- `RESAMPLING_SURVEY_ENABLE=0` ;
- filtres dumps/summaries `fluid` ;
- `INACTIVE_SLOTS` contrôlé par variable d’environnement.

Côté `mpcd_vkkh_play.cu`, le script compile avec `nvcc -O3 -std=c++17 -Xcompiler -fopenmp` et lance :

- `--mode vk` ;
- `--vis 0` ;
- `--writeCSV 0` ;
- `--dumpStride 1000000000` ;
- `--logStride 1000000000`.

## Sorties

Par défaut :

```text
dev_history/artifacts/gpu_objective_profile_0317/
```

Fichiers principaux :

- `gpu_objective_profile_0317_manifest.csv`
- `gpu_objective_profile_0317_summary.csv`
- `gpu_objective_profile_0317_top_kernels.csv`
- `gpu_objective_profile_0317_top_cuda_api.csv`
- `logs/*.stdout.log`, `logs/*.stderr.log`
- `time/*.time.csv`
- `nsys/*.nsys-rep` si Nsight Systems est disponible
- `nsys_stats/*` exports CSV/TXT si Nsight Systems est disponible

## Règle d’interprétation

Ce jalon ne justifie aucun patch d’optimisation par lui-même. La suite doit partir des tableaux produits, par exemple :

```text
X représente Y % du temps total / temps kernel / temps CUDA API,
donc le patch suivant cible X.
```

En particulier, le chantier float/double ne doit pas être relancé tant que le profil ne montre pas que le cœur double, `atomicAdd(double)` ou les kernels associés dominent objectivement le coût.

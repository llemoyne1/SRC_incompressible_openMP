# 0317b — harnais de profiling objectif GPU SRC/MPCD vs `mpcd_vkkh_play.cu`

Ce jalon est **script-only** et ne modifie pas le solveur SRC/MPCD. Il corrige le harnais 0317, qui échouait avec certaines versions de Nsight Systems parce que l’option `--cpuctxsw=true` n’est pas acceptée. Les valeurs valides observées sont typiquement `process-tree`, `system-wide` ou `none`.

## Correction par rapport à 0317

- `NSYS_CPUCTXSW=process-tree` par défaut au lieu de `--cpuctxsw=true`.
- Repli automatique :
  1. essai Nsight complet ;
  2. si échec, essai Nsight minimal ;
  3. si nouvel échec, fallback `/usr/bin/time`.
- Le manifeste est écrit même si Nsight échoue.
- Les warmups sont maintenant réellement chronométrés par `/usr/bin/time`.
- Les sorties sont isolées dans `dev_history/artifacts/gpu_objective_profile_0317b/`.

Aucun fichier `.patch` n’est fourni. Aucun fichier source du solveur n’est modifié.

## Fichiers ajoutés

- `scripts/run_gpu_objective_profile_0317b.sh`
- `scripts/summarize_gpu_objective_profile_0317b.py`
- `doc/GPU_OBJECTIVE_PROFILE_0317B.md`

## Utilisation recommandée

Depuis la racine du dépôt local :

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
```

Copier ou référencer le code spécialisé :

```bash
# Option A
cp /chemin/vers/mpcd_vkkh_play.cu ./mpcd_vkkh_play.cu

# Option B
export VKKH_CU=/chemin/vers/mpcd_vkkh_play.cu
```

Profil standard :

```bash
STEPS=10000 REPEATS=1 INACTIVE_SLOTS=100000 \
  bash scripts/run_gpu_objective_profile_0317b.sh
```

Forcer Nsight :

```bash
USE_NSYS=1 STEPS=10000 REPEATS=1 \
  bash scripts/run_gpu_objective_profile_0317b.sh
```

Désactiver Nsight :

```bash
USE_NSYS=0 STEPS=10000 REPEATS=1 \
  bash scripts/run_gpu_objective_profile_0317b.sh
```

Changer explicitement le mode de context-switch CPU Nsight :

```bash
NSYS_CPUCTXSW=none STEPS=10000 REPEATS=1 \
  bash scripts/run_gpu_objective_profile_0317b.sh
```

## Résultats attendus

Répertoire :

```text
dev_history/artifacts/gpu_objective_profile_0317b/
```

Fichiers principaux :

```text
gpu_objective_profile_0317b_manifest.csv
gpu_objective_profile_0317b_summary.csv
gpu_objective_profile_0317b_top_kernels.csv
gpu_objective_profile_0317b_top_cuda_api.csv
```

Puis transmettre les résultats avec :

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
zip -r gpu_objective_profile_0317b_results.zip \
  dev_history/artifacts/gpu_objective_profile_0317b
```

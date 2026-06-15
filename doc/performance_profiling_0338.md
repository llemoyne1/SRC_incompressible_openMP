# Profiling 0338 — protocole objectif end-to-end CUDA/SRC/VIZ

## But

Le but du chantier 0338 est de mesurer objectivement l’écart end-to-end entre :

1. le monolithique CUDA VK ;
2. `SRC_GPU` ;
3. `SRC_GPU-VIZ`.

Aucune optimisation ne doit être appliquée avant diagnostic. Le protocole cherche à isoler : coût du wrapper/génération d’état, dumps, summaries, stdout, appels CUDA API, synchronisations, copies host-device, allocations répétées, kernels, runtime OS et I/O.

## Point important avant comparaison

Les commandes observées ne sont pas encore strictement iso-cas :

- le monolithique lancé dans le terminal utilise `gamma=20`, donc environ 8.19 M particules sur 640×640 ;
- les scripts SRC/VIZ attachés utilisent `GAMMA=6`, donc environ 2.42 M particules ;
- le script `SRC_GPU` est `VK_MODE=periodic` par défaut ;
- le script `SRC_GPU-VIZ` est `VK_MODE=io` par défaut et active le bloc live visualization 0337 ;
- `SRC_GPU` utilise 8 threads par défaut, tandis que VIZ en utilise 12.

Le script `profile_0338_end_to_end.sh` lance donc :

- `mono` : commande monolithique telle que fournie ;
- `src_gpu_periodic` : SRC_GPU classique périodique, livevis désactivé ;
- `src_gpu_viz_periodic_live` : VIZ en périodique, livevis activé, pour isoler l’effet VIZ à conditions proches ;
- `src_gpu_viz_io_live_observed` : VIZ en IO, proche du cas observé.

## Installation

Depuis le dépôt principal :

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU
unzip /mnt/data/src_gpu_profile_0338_files_only.zip
chmod +x scripts/profile_0338_end_to_end.sh
```

Le script peut être lancé depuis `SRC_GPU` mais pilote aussi `SRC_GPU-VIZ` via `SRC_GPU_VIZ_ROOT`.

## Commande standard

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU
SRC_GPU_ROOT=/mnt/e/SRC_MPCD_DEV/SRC_GPU \
SRC_GPU_VIZ_ROOT=/mnt/e/SRC_MPCD_DEV/SRC_GPU-VIZ \
RUN_TIME_V=1 RUN_NSYS=1 RUN_STRACE=1 RUN_PERF_STAT=0 \
bash scripts/profile_0338_end_to_end.sh
```

## Variante légère si `nsys` est trop intrusif

```bash
RUN_NSYS=0 RUN_STRACE=1 RUN_TIME_V=1 bash scripts/profile_0338_end_to_end.sh
```

## Variante sans `strace`

```bash
RUN_NSYS=1 RUN_STRACE=0 RUN_TIME_V=1 bash scripts/profile_0338_end_to_end.sh
```

## Variables utiles

```bash
# Binaries
MONO_BIN=./build/mpcd_vkkh_play_timed_0333
SRC_GPU_BIN=build/src_mpcd_base_cuda_0334a
SRC_GPU_VIZ_BIN=build/src_mpcd_base_cuda_livevis_0337d

# Problem size
NX=640 NY=640 GAMMA=6 STEPS=500 DT=0.0005 KBT=0.5 U0=0.45

# Profiling toggles
RUN_TIME_V=1
RUN_NSYS=1
RUN_STRACE=1
RUN_PERF_STAT=0
INCLUDE_VIZ_IO_AS_OBSERVED=1
```

Si le binaire monolithique accepte un paramètre de densité particulaire, l’ajouter via :

```bash
MONO_EXTRA_ARGS="--gamma 6"
```

Ne l’utiliser que si l’option est effectivement reconnue par le binaire.

## Sorties produites

Le script écrit une session dans :

```text
runs/profile_0338/session_YYYYMMDD_HHMMSS/
```

Chaque cas contient des sous-dossiers `time_v`, `nsys_run`, `strace`, éventuellement `perf`.

Fichiers importants :

- `host_manifest.txt` : machine, chemins, paramètres globaux ;
- `nvidia_smi.txt` : état GPU ;
- `exact_command.txt` : commande réellement exécutée ;
- `env.filtered` et `env.effective_before_wrapper` : variables `MPCD_`, `SRC_`, `LIVE_`, `OMP_`, `CUDA_` ;
- `git.txt` : branche, commit, tag dirty éventuel ;
- `time_v.txt` : `/usr/bin/time -v` ;
- `stdout.txt`, `stderr.txt` : sortie du run ;
- `generated_files.txt` : fichiers produits ;
- `key_generated_texts.txt` : `.kv`, `.env`, `.time`, `.log` extraits ;
- `nsys/*.csv` : rapports `summary`, `cuda_api_sum`, `cuda_gpu_kern_sum`, `cuda_gpu_mem_time_sum`, `osrt_sum` ;
- `strace_c.txt` : résumé `strace -f -c`.

Le fichier `TRANSMIT_THESE_FILES.txt` liste automatiquement les fichiers à transmettre.

## Lecture attendue du profil

Priorité d’analyse :

1. `time_v.txt` : wall-time, CPU user/sys, max RSS, filesystem outputs/inputs, context switches ;
2. `nsys/cuda_api_sum.csv` : `cudaDeviceSynchronize`, `cudaStreamSynchronize`, `cudaMemcpy`, `cudaMemcpyAsync`, `cudaMalloc`, `cudaFree`, `cudaMemset` ;
3. `nsys/cuda_gpu_kern_sum.csv` : kernels dominants, nombre d’appels, durée totale ;
4. `nsys/cuda_gpu_mem_time_sum.csv` : volume et temps HtoD/DtoH ;
5. `nsys/osrt_sum.csv` : temps dans `read`, `write`, `open`, `futex`, `poll`, `pthread_*`, etc. ;
6. `strace_c.txt` : validation indépendante des coûts I/O et stdout.

Critères de diagnostic :

- beaucoup de temps API CUDA mais peu de temps kernel : synchronisation/copies/allocations ;
- beaucoup de `cudaMalloc/cudaFree` : allocation répétée à éliminer ensuite ;
- beaucoup de DtoH/HtoD : fallback host, summaries, dumps ou diagnostics ;
- beaucoup de `write/open/fsync` dans `strace`/`osrt_sum` : I/O/logging ;
- `src_gpu_viz_periodic_live` proche de `src_gpu_periodic` : VIZ non responsable ;
- `src_gpu_viz_io_live_observed` beaucoup plus lent : coût inlet/outlet ou livevis IO, à isoler ensuite.

## Ce qu’il faut transmettre après exécution

Copier-coller d’abord la fin terminale incluant :

```text
[0338] done: .../runs/profile_0338/session_...
[0338] transmit .../TRANSMIT_THESE_FILES.txt plus the listed files.
```

Puis transmettre les fichiers listés dans `TRANSMIT_THESE_FILES.txt`, ou au minimum :

```bash
find runs/profile_0338/session_* -maxdepth 4 -type f \
  \( -name 'time_v.txt' -o -name 'env*.filtered' -o -name 'env.effective_before_wrapper' \
     -o -name 'git.txt' -o -name 'exact_command.txt' -o -name 'generated_files.txt' \
     -o -name 'key_generated_texts.txt' -o -name 'strace_c.txt' -o -name '*.csv' \
     -o -name 'stdout.txt' -o -name 'stderr.txt' -o -name 'host_manifest.txt' \
     -o -name 'nvidia_smi.txt' \) \
  | sort
```

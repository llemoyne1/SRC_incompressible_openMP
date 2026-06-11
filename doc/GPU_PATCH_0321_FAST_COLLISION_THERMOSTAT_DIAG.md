# GPU patch 0321 — fast persistent SRC collision/thermostat diagnostics

## Objectif mesuré

Après les validations 0318b, 0319 et 0320, le profil VK périodique 192x64, gamma=20, 10000 steps donne :

- `elapsed_s` ≈ 18.23 s ;
- `src_collision` ≈ 14.45 s ;
- `srcPersistentDownload_s` ≈ 5.89 s ;
- `wall_simple_0246` ≈ 0.34 s ;
- `immersed_circle_0284` ≈ 1.80 s.

Le coût prioritaire restant est donc le bloc D2H/synchronisation de la collision persistante avec thermostat, pas le noyau float/double.

## Changement

Ajout du flag :

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1
```

dans `src/cuda_persistent_mpcd_step.cu`.

Lorsque ce flag est actif dans le chemin persistent collision + thermostat résident :

- les kernels collision + thermostat GPU restent exécutés ;
- le téléchargement par step de `cellCount`, `cellKinetic`, `cellScale` et des compteurs scalaires est sauté ;
- les diagnostics thermostat retournés au résumé runtime deviennent synthétiques ;
- les espaces de travail hôte cellule sont vidés, ce qui rend explicite qu'ils ne doivent pas être consommés par Q6/resampling/capacity dans ce mode classic-only benchmark.

Le runner VK CUDA active ce mode par défaut :

```bash
SRC_GPU_FAST_THERMOSTAT_DIAG_0321=1
```

On peut restaurer l'ancien comportement avec :

```bash
SRC_GPU_FAST_THERMOSTAT_DIAG_0321=0
```

## Domaine de validité

Ce patch est destiné au chemin classic SRC CUDA résident benchmark :

- Q6 désactivé ;
- resampling désactivé ;
- viriel / closed capacity désactivés ;
- thermostat cell-relative exécuté par le kernel persistent GPU ;
- summary/dumps non utilisés comme consommateurs physiques par step.

Il ne change pas la dynamique particulaire GPU attendue, mais réduit la précision des colonnes runtime liées aux diagnostics thermostat/population par cellule pendant ce mode rapide.

## Validation attendue

Après rebuild, comparer à 0320 :

- `srcPersistentDownload_s` doit chuter fortement depuis ≈ 5.9 s ;
- `src_collision` doit chuter depuis ≈ 14.45 s ;
- `elapsed_s` doit se rapprocher du coût kernel collision + wall/circle ;
- le run doit rester `exitCode=0`.

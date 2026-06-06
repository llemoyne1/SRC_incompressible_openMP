# GPU patch 0262 — classic SRC CUDA résident avec solide rectangle périodique

## Objet

Ce patch étend le mode **classic SRC CUDA résident** validé en 0260/0261 à un cas avec solide immergé rectangle statique, en restant volontairement borné :

- cas validé : `periodic_rect_obstacle_classic` ;
- conditions limites externes : périodiques en x et y ;
- solide : rectangle statique immergé ;
- Q6/Q9 : désactivés ;
- resampling : désactivé ;
- viriel / closed-capacity : désactivé ;
- thermostat : désactivé pour ce premier jalon solide-résident.

L'objectif est d'isoler la composition :

```text
streaming périodique CUDA
→ réflexion rectangle immergé CUDA
→ collision SRC CUDA avec contribution solide 0254
→ synchronisation host seulement aux summaries/final
```

## Nouvelles options

```bash
MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=1
MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0
```

Le mode est accepté seulement si :

- `srcClassicCudaModeEnable=true` ;
- `projectionEnable=false` ;
- `resamplingEnable=false` ;
- `closedCapacityResponseEnable=false` ;
- les quatre frontières externes sont périodiques ;
- le solide immergé est un rectangle statique.

## Validation

```bash
bash scripts/run_cuda_classic_src_solid_resident_0262.sh
```

Le script compare :

```text
cpu_classic_solid_no_thermostat
0257_solid_cuda_download_each_step_no_thermostat
0262_solid_resident_classic_cuda_no_thermostat
```

sur :

```text
periodic_rect_obstacle_classic
64x64_s300
128x128_s300
```

Critère attendu :

```text
verdict=PASS
failed_metrics=0
```

## Remarques

Le cas `open_rect_obstacle_full` n'est pas utilisé ici, car il inclut aussi inlet/outlet et réservoir/injection CPU. Le 0262 cible uniquement le verrou solide/obstacle pour le mode résident. Les inlet/outlet résidents seront à traiter dans un jalon séparé.

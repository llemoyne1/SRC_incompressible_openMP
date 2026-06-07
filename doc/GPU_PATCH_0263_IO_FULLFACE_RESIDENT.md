# GPU patch 0263 — SRC classic CUDA résident inlet/outlet full-face

## Objectif

Ce jalon étend la branche performance SRC classic CUDA résident au premier cas ouvert contrôlé : `open_rect_obstacle_full` avec inlet pleine face à gauche, outlet pleine face à droite, parois solides haut/bas et obstacle rectangulaire statique.

Le périmètre reste volontairement strict :

- Q6/Q9 CPU non utilisé dans ce mode (`srcClassicCudaModeEnable=true`, `projectionEnable=false`) ;
- resampling désactivé ;
- viriel/capacity désactivé ;
- thermostat désactivé ;
- `wallThermalNoise=0` et `inletThermalNoise=0` ;
- pas de segmentation inlet/outlet ;
- pas d'append GPU : le réservoir hard-cell réutilise uniquement les slots inactifs existants.

## Modifications principales

### `src/cuda_classic_src_io_resident_0263.cu`

Ajout d'un chemin résident `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263` contenant deux opérations :

1. `try_apply_cuda_classic_src_io_fullface_stream_0263` : force + streaming sur l'état partagé CUDA 0251 pour un domaine ouvert en x et borné en y.
2. `try_apply_cuda_classic_src_io_fullface_boundary_0263` : condition limite hard-cell inlet/outlet sur l'état partagé CUDA.

Le noyau hard-cell est volontairement mono-thread dans ce jalon. Cela préserve l'ordre logique CPU : suppression des particules sortantes/réservoir, parcours croissant des slots inactifs, puis insertion déterministe par cellule de réservoir. Ce n'est pas encore le jalon de performance finale inlet/outlet ; c'est le verrou de résidence/correction.

### `src/src_mpcd_base.cpp`

Le mode 0263 est ajouté à la famille des modes SRC classic résidents. Le pipeline évite alors le retour CPU pendant :

- force + streaming ;
- boundary hard-cell full-face ;
- réflexion obstacle rectangle CUDA ;
- collision SRC persistante CUDA ;
- résumé final, avec téléchargement uniquement lors des pas de summary/final.

### `src/cuda_persistent_mpcd_step.cu`

La collision SRC persistante évite maintenant aussi `download_velocities()` quand `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1`.

### `src/cuda_immersed_rectangle_0247.cu`

La réflexion obstacle rectangle réutilise l'état partagé résident aussi pour 0263, comme pour 0262.

### `scripts/run_validation_mono_config_0162.sh`

`inletThermalNoise` peut être surchargé par l'environnement via `INLET_THERMAL_NOISE`. Le runner 0263 fixe cette valeur à zéro pour garder une comparaison déterministe CPU/GPU.

## Validation

Runner principal :

```bash
bash scripts/run_cuda_classic_src_io_fullface_resident_0263.sh
```

Valeurs par défaut :

```bash
GRID_CASES="64:64:300 128:128:300"
CASES="open_rect_obstacle_full"
GAMMA=20
THREADS=8
SUMMARY_EVERY_MODE=final
```

Le runner compare :

- baseline CPU classic sans Q6/resampling/thermostat ;
- mode `0263_io_fullface_resident_classic_cuda_no_thermostat`.

Le fichier de synthèse est écrit dans :

```text
dev_history/artifacts/gpu_cuda_classic_src_io_0263/cuda_classic_src_io_fullface_resident_0263.csv
```

Critère attendu :

```text
verdict=PASS
failed_metrics=0
```

## Limites connues

- Le hard-cell inlet/outlet 0263 est résident mais pas encore parallélisé.
- La segmentation `0249b` n'est pas encore portée en résident.
- L'insertion avec bruit thermique inlet n'est pas activée dans ce jalon.
- Le thermostat CUDA reste à traiter séparément pour les cas wall/solid/piston/inlet-outlet.
- Le mode ne couvre pas encore les entrées/sorties y, ni les configurations multi-segments.

## Suite logique

1. Valider 0263 sur `64x64` puis `128x128`.
2. Si PASS mais lenteur : paralléliser suppression/scan/activation du réservoir par préfixe ou liste compacte d'inactifs.
3. Étendre ensuite à la segmentation 0264, en gardant les segments U-turn comme cas discriminant.

# Catalogue des paramètres — SRC_GPU 0287

Ce dossier met à jour les deux CSV 0187 pour l’état CUDA consolidé 0286/0287.

## Source de vérité

- paramètres `.kv` acceptés : `src/params_io_base.cpp` ;
- défauts canoniques : `include/simulation_params.h` ;
- état CUDA validé : consolidé 0286, `SRC classic = advection/streaming + shift + collision/rotation + thermostat` ;
- fermeture liquide séparée : `Q6 + resampling + viriel`, préservée mais hors jalon SRC classic full CUDA.

## Modifications par rapport à 0187

Le parseur actuel accepte 261 clés ou formes dynamiques de clés `.kv`.
Les fichiers 0187 en listaient 254. Les ajouts sont :

```text
classicSrcCudaMode
classicSrcCudaModeEnable
classicSrcModeEnable
gpuProjectionBackend
projectionBackend
q6ProjectionBackend
srcClassicCudaModeEnable
```

Les nouveaux champs canoniques principaux sont :

- `srcClassicCudaModeEnable`, avec alias `classicSrcCudaModeEnable`, `classicSrcModeEnable`, `classicSrcCudaMode` ;
- `projectionBackend`, avec alias `q6ProjectionBackend`, `gpuProjectionBackend`.

## Fichiers produits

- `src_mpcd_params_catalogue_0287_cuda.csv` : catalogue canonique révisé ;
- `src_mpcd_params_cles_acceptees_0287_cuda.csv` : liste exhaustive des clés `.kv` acceptées par le parseur actuel ;
- `src_mpcd_cuda_env_flags_0287.csv` : inventaire des variables d’environnement CUDA/runtime, à ne pas mettre dans `.kv` ;
- `src_mpcd_params_cuda_0287.xlsx` : version tableur regroupant les trois tables.

## Point de vigilance

Les clés commençant par `q9`, `virial`, `massFlux` ou `lowK` sont rejetées par le parseur de cette branche, sauf les champs `closedCapacityVirial*` qui appartiennent explicitement au module `closedCapacity*`. Les anciens paramètres d’aperture `openBoundaryApertureEnable`, `leftOpenYMin`, etc. sont également retirés : utiliser les segments compacts `openBoundarySegmentK`.

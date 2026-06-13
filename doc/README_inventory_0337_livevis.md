# Inventaire flags/paramètres SRC GPU — mise à jour 0337 livevis

Cette mise à jour part des inventaires 0314 fournis par l'utilisateur et ajoute les éléments apparus depuis le checkpoint 0314 jusqu'au chantier live visualization 0337.

## Fichiers complets

- `src_mpcd_cuda_resampling_env_flags_delta_0314_to_0337_livevis.csv` : inventaire complet des variables d'environnement 0314 + ajouts 0331/0334/0335-0337.
- `src_mpcd_cuda_resampling_params_delta_0314_to_0337_livevis.csv` : inventaire complet des clés/alias de scripts 0314 + ajouts livevis 0337.

## Fichiers delta ajoutés

- `src_mpcd_cuda_env_flags_added_0331_to_0337_livevis.csv` : lignes ajoutées seulement pour revue rapide.
- `src_mpcd_cuda_params_added_0337_livevis.csv` : alias de scripts livevis ajoutés seulement.

## Points structurants ajoutés

- Sécurité VK 0331 : quarantaine par défaut du chemin `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318`, déverrouillable seulement par `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318_UNSAFE_ENABLE=1`.
- Résidence CUDA full-periodic + immersed circle 0334a : `MPCD_CUDA_STREAMING_PERIODIC_0245`, `MPCD_CUDA_IMMERSED_CIRCLE_0284`, état partagé 0251.
- Visualisation live 0335-0337 : `MPCD_ENABLE_LIVE_VIS`, `SRC_LIVE_VIS_*`, aliases scripts `LIVE_VIS_*`.
- Renderer CUDA field 0337 : `SRC_LIVE_VIS_CUDA_FIELD=1` recommandé pour visualisation rapide, y compris avec resampling.
- Snapshot compact 0336 : conservé comme expérimental (`SRC_LIVE_VIS_CUDA_SNAPSHOT=0` par défaut).
- Host mirror resampling 0335d : fallback fiable mais lent (`SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=1` seulement pour debug/fallback).

## Nombre de lignes ajoutées

- Flags ajoutés : 29
- Paramètres/alias ajoutés : 21

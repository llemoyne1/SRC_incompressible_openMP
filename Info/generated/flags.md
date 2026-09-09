# Flags et variables d’environnement / runners

> Ces entrées sont séparées des paramètres `.kv`. Lorsqu’un flag écrit un paramètre canonique, la relation est indiquée explicitement.

| Nom | Type | Défaut | Paramètre(s) ciblé(s) | Catégorie | Statut |
|---|---|---|---|---|---|
| `ALPHA` | double | DARCY_ALPHA_MAX ou valeur script |  | Alias script Darcy | ajout/documenté 0426 |
| `ALPHA_MIN` | double | DARCY_ALPHA_MIN ou 0.0 |  | Alias script Darcy | ajout/documenté 0426 |
| `ANALYZE_ONLY` | booléen/int | 0 |  | Alias runner / analyse | ajout/normalisé 0493w4–0493w8 |
| `AUTO_BUILD` | booléen | 1 |  | Alias script / build | mis à jour 0337 livevis |
| `BACKGROUND_MASS_CLOSURE_STRENGTH` | double | 0.0 pour gas; 1.0 pour liquid |  | Alias runner / injection multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `BACKGROUND_PHASE` | liquid\|gas | gas |  | Alias runner / injection multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `BACKGROUND_Q6_STRENGTH` | double | 0.0 pour gas; 1.0 pour liquid |  | Alias runner / injection multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `BIN` | chemin exécutable | build/src_mpcd_base_cuda_q6_resident_livevis_0486 dans les runners 0493w4–0493w8 |  | Alias script / binaire | mis à jour 0337 livevis |
| `CASES` | liste/chaîne | tg poiseuille bend_pipe io_box |  | Runner qualification 0493x7i / sélection de cas | profil final x7q/x7i |
| `CHI_FILE` | chemin fichier | DARCY_CHI_FILE ou chemin par défaut |  | Alias script Darcy | ajout/documenté 0426 |
| `CHI_FILE_FORMAT` | chaîne | DARCY_CHI_FILE_FORMAT ou float32 |  | Alias script Darcy | ajout/documenté 0426 |
| `CLEAN_RUN_ROOT` | booléen/int \| booléen | 1 |  | Alias runner / gestion des résultats \| Runner qualification 0493x7i / nettoyage campagne | ajout/normalisé 0493w4–0493w8 \| profil final x7q/x7i |
| `DARCY_ALPHA_MAX` | double | selon script |  | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_ALPHA_MIN` | double | 0.0 |  | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_BRINKMAN_FORCING_MODE` | chaîne | mean ou mean_outward_bath | darcyBrinkmanForcingMode | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_CHI_COLLISION_VP_ENABLE` | booléen | false ou true | darcyChiCollisionVpEnable | Alias script Darcy chiVP | ajout/documenté 0426 |
| `DARCY_CHI_COLLISION_VP_GAMMA` | entier/double | -1 | darcyChiCollisionVpGamma | Alias script Darcy chiVP | ajout/documenté 0426 |
| `DARCY_CHI_COLLISION_VP_LAYERS` | entier | 1 | darcyChiCollisionVpLayers | Alias script Darcy chiVP | ajout/documenté 0426 |
| `DARCY_CHI_COLLISION_VP_MASS` | double | 1.0 | darcyChiCollisionVpMass | Alias script Darcy chiVP | ajout/documenté 0426 |
| `DARCY_CHI_COLLISION_VP_MODE` | chaîne | interface_band | darcyChiCollisionVpMode | Alias script Darcy chiVP | ajout/documenté 0426 |
| `DARCY_CHI_COLLISION_VP_STRENGTH` | double | 0.25 ou 1.0 | darcyChiCollisionVpStrength | Alias script Darcy chiVP | ajout/documenté 0426 |
| `DARCY_CHI_COLLISION_VP_THRESHOLD` | double | 0.5 | darcyChiCollisionVpThreshold | Alias script Darcy chiVP | ajout/documenté 0426 |
| `DARCY_CHI_FILE` | chemin fichier | selon cas |  | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_CHI_FILE_FORMAT` | chaîne | float32 |  | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_COST_EVERY` | entier | SUMMARY_EVERY |  | Alias script Darcy diagnostics | ajout/documenté 0426 |
| `DARCY_INITIAL_DEACTIVATE_BELOW_CHI` | double | -1 ou 0.05 | darcyInitialDeactivateBelowChi | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_Q` | double | 0.1 |  | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_THREADS_PER_BLOCK` | entier | 256 |  | Alias script Darcy CUDA | ajout/documenté 0426 |
| `DARCY_USOLID_X` | double | 0.0 |  | Alias script Darcy | ajout/documenté 0426 |
| `DARCY_USOLID_Y` | double | 0.0 |  | Alias script Darcy | ajout/documenté 0426 |
| `DENSITY_RELAXATION_TIME` | double >0 | 0.25 |  | Alias runner de qualification 0493x7d/x7e | historique x7d/x7e; valeur reprise dans profil x7q |
| `DROP_CENTER_X` | double dans domaine | centre du domaine en x |  | Alias runner — splash x9s | ajout 0493x9s |
| `DROP_CENTER_Y` | double dans domaine | 1.25 pour le domaine x9s par défaut |  | Alias runner — splash x9s | ajout 0493x9s |
| `DROP_RADIUS_CELLS` | double >0 | 40 |  | Alias runner — splash x9s | ajout 0493x9s |
| `DROP_VX` | double | 0 |  | Alias runner — splash x9s | ajout 0493x9s |
| `DROP_VY` | double | -0.35 |  | Alias runner — splash x9s | ajout 0493x9s |
| `DUMP_ROLE_FILTER` | all\|fluid \| alias script utilisateur | fluid dans scripts visual 0309+ \| fluid dans scripts visuels 0309+ | dumpRoleFilter | Alias script \| CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0314 \| script 0314 |
| `EMPTY_INITIAL_MASS` | double >0 | PARTICLE_MASS |  | Alias script état initial / injection empty refill 0434 | option locale/proposée 0434; documenté 0436 |
| `EMPTY_INITIAL_SLOTS` | entier >=0 | gamma*Nx*Ny si vide |  | Alias script état initial / injection empty refill 0434 | option locale/proposée 0434; documenté 0436 |
| `EMPTY_INITIAL_TYPE` | entier type particulaire | BACKGROUND_TYPE |  | Alias script état initial / injection empty refill 0434 | option locale/proposée 0434; documenté 0436 |
| `EVAPORATION_TARGET_TYPE` | entier | -1 (runners x12 et SimulationParams) | phaseInterfaceEvaporationTargetType | Alias runner — interface cinétique / évaporation | runner alias courant; production x12 = -1 |
| `FILTERED_RECORDING_ENABLE` | booléen shell \| booléen/env truthy | 0 ou valeur script \| 0 sauf script/profil |  | Alias script filtered recording 0434/0436 | documenté 0436 |
| `GAMMA` | entier >0 | 20 |  | Validateurs CUDA resampling — population | lecture C++ directe dans validateurs shadow; également variable shell courante des runners |
| `GAS_KBT` | double >0 | dépend du benchmark; Couette x14w: 0.08 |  | Runner x14 — propriétés de phase | paramètre visible des runners x14 |
| `GAS_PRESSURE_CONSTANT` | double fini | GAS_PRESSURE_REFERENCE |  | Alias script 0493x6g | ajout runner 0493x6g |
| `GAS_PRESSURE_MODE` | enum string | eos |  | Alias script 0493x6g | ajout runner 0493x6g |
| `GAS_PRESSURE_REFERENCE` | double fini | pression EOS uniforme initiale |  | Alias script 0493x6g | ajout runner 0493x6g |
| `GAS_PRESSURE_SCALE` | double >= 0 | 1.0 |  | Alias script 0493x6g | ajout runner 0493x6g |
| `GRID_CASES` | liste/chaîne de cas | défini par le validateur |  | Validateurs CUDA resampling — entrée de test | présent code; ajouté consolidation 0493w8 |
| `INACTIVE_SLOTS` | entier \| alias script utilisateur | 50k-120k selon cas; pas de défaut universel \| selon script; éviter les millions | dumpRoleFilter | Capacité particulaire \| CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | consolidé 0311-0312 \| script/demo/audit |
| `INACTIVE_SLOTS_RESAMPLING` | entier | 750000 pour certains scripts |  | Alias script livevis/benchmark | confirmé 0337 |
| `INITIAL_DOMAIN_MODE` | full \| empty \| empty\|full | full \| empty dans le runner partagé; full dans le wrapper biphasique |  | Alias script état initial / injection empty refill 0434 \| Alias runner / injection multi-espèces | option locale/proposée 0434; documenté 0436 \| ajout/normalisé 0493w4–0493w8 |
| `INJECT_MASS_CLOSURE_STRENGTH` | double | 1.0 pour liquid; 0.0 pour gas |  | Alias runner / injection multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `INJECT_PHASE` | liquid\|gas | liquid pour le wrapper type1_into_type2 |  | Alias runner / injection multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `INJECT_Q6_STRENGTH` | double | 1.0 pour liquid; 0.0 pour gas |  | Alias runner / injection multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `INJECT_TO_BACKGROUND_MASS_RATIO` | double >0 | 100 liquid->gas; 0.01 gas->liquid; 10 sinon |  | Alias runner / injection multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `INLET_FACE` | double/chaîne selon variable | left |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `INLET_SMAX` | double/chaîne selon variable | 1.0 |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `INLET_SMIN` | double/chaîne selon variable | STEP_YMAX/Ly |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `INPUT_STATE` | chemin fichier | selon cas | inputState | Alias script état initial | ajout/documenté 0426 |
| `KINETIC_REFLECTION_FRACTION` | double [0,1] | 1.0 dans runners x12 de production; défaut SimulationParams=0.0 | phaseInterfaceKineticReflectionFraction, q6ForceProjectionMode, speciesQ6Mode | Alias runner — interface cinétique / évaporation | runner alias courant; production x12 = 1.0 |
| `LIQUID_KBT` | double >0 | dépend du benchmark; Couette x14w: 0.02 |  | Runner x14 — propriétés de phase | paramètre visible des runners x14 |
| `LIVE_PROGRESS` | booléen/int \| booléen | 1 |  | Alias runner / ergonomie \| Runner qualification 0493x7i / progression | ajout/normalisé 0493w4–0493w8 \| profil final x7q/x7i |
| `LIVE_VIS_ALPHA` | double | 0.08 |  | Alias script livevis 0337 | ajout 0337 \| précisé 0436b |
| `LIVE_VIS_CLIP` | double; <=0 auto | -1 |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_COLORMAP` | enum: blue_red \| gray \| thermal | blue_red |  | Alias script livevis colormap | ajout 0342a |
| `LIVE_VIS_CONTROL_BASENAME` | nom de fichier | livevis_control.kv |  | Alias script livevis runtime control | ajout 0341d |
| `LIVE_VIS_CONTROL_DIR` | chemin répertoire | vide |  | Alias script livevis runtime control | ajout 0341d |
| `LIVE_VIS_CONTROL_ENABLE` | booléen shell | 1 |  | Alias script livevis runtime control | ajout 0341b; export explicite 0341c |
| `LIVE_VIS_CONTROL_EVERY` | entier >= 1 | 1 |  | Alias script livevis runtime control | ajout 0341b; export explicite 0341c |
| `LIVE_VIS_CONTROL_FILE` | chemin fichier .kv | vide |  | Alias script livevis runtime control | ajout 0341b; clarifié 0341d |
| `LIVE_VIS_CONTROL_FILE_EFFECTIVE` | chemin fichier .kv résolu | résolu automatiquement |  | Alias script livevis runtime control interne | ajout 0341b; export explicite 0341c; clarifié 0341d |
| `LIVE_VIS_CONTROL_LOG` | booléen shell | 1 |  | Alias script livevis runtime control | ajout 0341b; export explicite 0341c |
| `LIVE_VIS_CUDA_FIELD` | booléen | 1 |  | Alias script livevis 0337 | ajout 0337a |
| `LIVE_VIS_CUDA_SNAPSHOT` | booléen | 0 |  | Alias script livevis 0337 | ajout 0336/0337 |
| `LIVE_VIS_ENABLE` | booléen \| booléen/int 0\|1 | 1 \| 0 dans le runner final x6g |  | Alias script livevis 0337 \| Alias script LiveVis / runners 0493x | ajout 0337 \| documenté/fix runner 0493x6g-fix3 |
| `LIVE_VIS_EVERY` | entier >0 | 25 \| 20 |  | Alias script livevis 0337 | ajout 0337 \| mis à jour 0339a \| mis à jour 0433a |
| `LIVE_VIS_FIELD` | ux\|uy\|speed\|vorticity\|mass\|density | dépend du script |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_FORCE_HOST_MIRROR` | booléen | 0 |  | Alias script livevis 0337 | ajout 0335c |
| `LIVE_VIS_GAIN` | double >0 | 1.0 |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_HOLD_ON_EXIT` | booléen \| booléen/int 0\|1 | 1 \| 0 dans le runner final x6g |  | Alias script livevis \| Alias script LiveVis / runners 0493x | ajout/documenté 0426 \| documenté/fix runner 0493x6g-fix3 |
| `LIVE_VIS_LOG_SOURCE` | booléen | 0 |  | Alias script livevis 0337 | ajout 0337d \| mis à jour 0339a |
| `LIVE_VIS_NX` | entier | 300 |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_NY` | entier | 80 |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_QUANTILE` | double dans (0,1] | 0.995 |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_QUIVER_MIN_SPEED` | double >= 0 | 0 |  | Alias script livevis quiver | ajout 0364 |
| `LIVE_VIS_QUIVER_NX` | entier >= 1 | 60 |  | Alias script livevis quiver | ajout 0364 |
| `LIVE_VIS_QUIVER_NY` | entier >= 1 | 32 |  | Alias script livevis quiver | ajout 0364 |
| `LIVE_VIS_QUIVER_SCALE` | double | -1 |  | Alias script livevis quiver | ajout 0364 |
| `LIVE_VIS_QUIVER_SMOOTH_PASSES` | entier; -1 ou >=0 | -1 |  | Alias script livevis quiver | ajout 0365 |
| `LIVE_VIS_RESAMPLING_HOST_MIRROR` | booléen | 0 |  | Alias script livevis 0337 | ajout 0335d/0337 |
| `LIVE_VIS_SMOOTH_PASSES` | entier >=0 | 1 |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_VSYNC` | booléen/int | 0 |  | Alias script livevis 0337 | ajout 0337 |
| `LIVE_VIS_WINDOW_SCALE` | entier >=1 | 1 |  | Alias script livevis 0337 | ajout 0337 |
| `MPCD_BACKEND` | string | cuda dans scripts/run_src_mpcd_cuda_primary_0275.sh; openmp si demandé explicitement |  | Backend principal | principal utilisateur |
| `MPCD_CUDA_ACTIVE_PREFIX_ASSUME_NO_HOST_CONSUMERS_0315D` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315d) |
| `MPCD_CUDA_ACTIVE_PREFIX_COMPACT_FULLSCAN_0315C` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315c) |
| `MPCD_CUDA_ACTIVE_PREFIX_COMPACT_FULLSCAN_0315K` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315k) |
| `MPCD_CUDA_ACTIVE_PREFIX_COMPACT_THREADS_0315C` | entier | 256 |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315c) |
| `MPCD_CUDA_ACTIVE_PREFIX_EAGER_HOST_MIRROR_0315D` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315d) |
| `MPCD_CUDA_ACTIVE_PREFIX_HOST_FULL_VALIDATE_0315H` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315h) |
| `MPCD_CUDA_ACTIVE_PREFIX_HOST_TAIL_FULL_REPAIR_0315H` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315h) |
| `MPCD_CUDA_ACTIVE_PREFIX_STRICT_EXPECTED_0315C` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315c) |
| `MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_ALL_FULL_VALIDATE_0315J` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315j) |
| `MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_ALL_LEGACY_0315J` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315j) |
| `MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315k) |
| `MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | réglage performance/interne |
| `MPCD_CUDA_CELL_MOMENTS_PERSISTENT_STATE_0251` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | interne/runtime |
| `MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | interne/runtime |
| `MPCD_CUDA_CELL_MOMENTS_SHADOW` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | debug/comparaison |
| `MPCD_CUDA_CELL_MOMENTS_SHADOW_EVERY` | entier | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | debug/comparaison |
| `MPCD_CUDA_CELL_MOMENTS_SHADOW_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA moments/workspace cellule | debug/comparaison |
| `MPCD_CUDA_CELL_MOMENTS_SHADOW_TOL` | double | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | debug/comparaison |
| `MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK` | entier | 256 le plus souvent |  | CUDA moments/workspace cellule | réglage performance/interne |
| `MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | réglage performance/interne |
| `MPCD_CUDA_CELL_MOMENTS_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | interne/runtime |
| `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — inlet/outlet full-face | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA SRC classic — inlet/outlet full-face | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet full-face | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_BOUNDARY_THREADS` | entier | 256 le plus souvent |  | Autres variables internes | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | Autres variables internes | interne/runtime |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_DISABLE_POOL` | booléen/env truthy sauf mention contraire | false/off |  | CUDA SRC classic — inlet/outlet full-face | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_INSERT_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet full-face | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_POOL_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet full-face | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_DISABLE_SEGMENTED_POOL` | booléen/env truthy sauf mention contraire | false/off |  | CUDA SRC classic — inlet/outlet segmenté | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_POOL_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet segmenté | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_SEGMENTED_INSERT_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet segmenté | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0291_FORCED_OUTLET_THREADS` | entier | 256 |  | CUDA SRC classic — inlet/outlet | présent état 36abd23; inventorié 0490p (0291) |
| `MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — inlet/outlet segmenté | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA SRC classic — inlet/outlet segmenté | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet segmenté | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260` | booléen/env truthy | false/off sauf scripts CUDA |  | SRC classic CUDA résident | validé 0286 \| existant; confirmé 0334a |
| `MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | Autres variables internes | réglage performance/interne \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_DISABLE_ASYNC_STREAM` | booléen/env truthy sauf mention contraire | false/off |  | Autres variables internes | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | Autres variables internes | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318` | booléen/env truthy | false/off |  | Sécurité VK / chemin wall+circle résident | existant 0318; quarantainé 0331 |
| `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318_UNSAFE_ENABLE` | booléen/env truthy | false/off |  | Sécurité VK / chemin wall+circle résident | ajout 0331 |
| `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_DISABLE_MINIMAL_DOWNLOAD_0338` | booléen/env truthy | false/off |  | CUDA sécurité / wall+circle resident 0318 | ajout 0338c; debug/rollback |
| `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_MINIMAL_DOWNLOAD_0338` | booléen/env truthy | false/off |  | CUDA performance / wall+circle resident 0318 | ajout 0338c; opt-in; validé classic wall+circle non-VIZ et VIZ |
| `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — wall-simple | validé 0286 |
| `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0270_DISABLE_BOUNDARY_SKIP` | booléen/env truthy sauf mention contraire | false/off |  | CUDA SRC classic — wall-simple | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_DISABLE_FAST_DIAGNOSTICS` | booléen/env truthy sauf mention contraire | false/off |  | CUDA SRC classic — wall-simple | réglage performance/interne |
| `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — wall-simple | interne/runtime |
| `MPCD_CUDA_COLLISION_WRAPPER_HOST_SYNC_0315F` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315f) |
| `MPCD_CUDA_DARCY_BRINKMAN_LOG_0343` | booléen/env truthy | false/off |  | CUDA Darcy–Brinkman | présent état 36abd23; inventorié 0490p (0343) |
| `MPCD_CUDA_IMMERSED_CIRCLE_0284` | booléen/env truthy | false/off sauf scripts VK |  | Obstacle immersed circle CUDA | validé 0286 \| confirmé 0334a |
| `MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL` | booléen/env truthy | false/off |  | Obstacle immersed circle CUDA | validé 0286 \| existant; à éviter en production |
| `MPCD_CUDA_IMMERSED_CIRCLE_0284_THREADS` | entier | 256 le plus souvent |  | CUDA solide immergé — cercle | validé 0286 |
| `MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330` | booléen/env truthy | false/off |  | Diagnostics rapides immersed circle CUDA | ajout 0330/0331 |
| `MPCD_CUDA_IMMERSED_RECTANGLE_0247` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA solide immergé — rectangle | interne/runtime |
| `MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA solide immergé — rectangle | réglage performance/interne |
| `MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS` | entier | 256 le plus souvent |  | CUDA solide immergé — rectangle | réglage performance/interne |
| `MPCD_CUDA_INACTIVE_TAIL_POOL_0313` | booléen/env truthy | true/on |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0313 |
| `MPCD_CUDA_INACTIVE_TAIL_POOL_MAX_SCAN_0313` | entier | 262144 |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0313 |
| `MPCD_CUDA_INACTIVE_TAIL_POOL_MIN_SCAN_0313` | entier | 8192 |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0313 |
| `MPCD_CUDA_INACTIVE_TAIL_POOL_NO_FALLBACK_0313` | booléen/env truthy | false/off |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0313 |
| `MPCD_CUDA_INACTIVE_TAIL_POOL_SCAN_MULT_0313` | réel/entier | 4 |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0313 |
| `MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — inlet/outlet full-face | interne/runtime |
| `MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet full-face | réglage performance/interne |
| `MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — inlet/outlet segmenté | interne/runtime |
| `MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — inlet/outlet segmenté | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA moments/workspace cellule | debug/comparaison |
| `MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA moments/workspace cellule | interne/runtime \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | Autres variables internes | interne/runtime \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_PARTICLE_STATE_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA état particulaire persistant | debug/comparaison |
| `MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA état particulaire persistant | interne/runtime \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | interne/runtime \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_DEVICE_ROTATION_0272` | booléen/env truthy sauf mention contraire | false/off |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_EXPLICIT_GAMMA_ROLE_FASTPATH_0273` | booléen/env truthy sauf mention contraire | false/off |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FAST_THERMOSTAT_DIAG_0321` | booléen/env truthy | false/off |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0321) |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FUSED_STREAM_DEPOSIT_0274` | booléen/env truthy sauf mention contraire | false/off |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_KERNEL_BREAKDOWN_0324` | booléen/env truthy | false/off |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0324) |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_KERNEL_BREAKDOWN_APPEND_0328` | booléen/env truthy | false/off |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0328) |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_LAZY_KERNEL_CHECK_0273` | booléen/env truthy sauf mention contraire | false/off |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_FINAL_SYNC_0272` | booléen/env truthy sauf mention contraire | false/off |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_HOST_CELLID_FILL_0327` | booléen/env truthy | false/off |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0327) |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_SETUP_SYNC_0273` | booléen/env truthy sauf mention contraire | false/off |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_WORKSPACE_DOWNLOAD_0272` | booléen/env truthy sauf mention contraire | false/off |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321` | booléen/env truthy | 1 |  | CUDA collision SRC résidente — diagnostic thermostat | ajout 0321; propagé Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | interne/runtime \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA solide immergé — cercle | validé 0286 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA solide immergé — rectangle | interne/runtime |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324` | booléen/env truthy | false/off |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0324) |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324_FILE` | chaîne/chemin | cuda_persistent_kernel_breakdown_0324.csv |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0324) |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_APPEND_0328` | booléen/env truthy | false/off |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0328) |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | réglage performance/interne \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — piston/mobile wall | interne/runtime |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251` | booléen/env truthy | false/off sauf chemin résident |  | État particulaire CUDA partagé | interne/runtime \| existant; réutilisé 0334/0337 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | réglage performance/interne \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327` | booléen/env truthy | 1 |  | CUDA collision SRC résidente — réduction transferts hôte | ajout 0327; propagé Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | réglage performance/interne \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319` | booléen/env truthy | 1 |  | CUDA collision SRC résidente — diagnostic wallVP | ajout 0319; propagé Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | réglage performance/interne \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | interne/runtime |
| `MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | interne/runtime |
| `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_DISABLE_SKIP_VELOCITY_DOWNLOAD_0315F` | booléen/env truthy | false/off |  | CUDA collision SRC — profilage et synchronisation | présent état 36abd23; inventorié 0490p (0315f) |
| `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés | thermostatEnable | CUDA thermostat | validé 0286 |
| `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA thermostat | validé 0286 |
| `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés | thermostatEnable | CUDA thermostat | validé 0286 |
| `MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK` | entier | 256 le plus souvent |  | Autres variables internes | réglage performance/interne \| propagé scripts Darcy 0426 |
| `MPCD_CUDA_PRIMARY_KEEP_TEMP` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | Backend principal | interne/runtime |
| `MPCD_CUDA_PRIMARY_VERBOSE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | Backend principal | interne/runtime |
| `MPCD_CUDA_Q6_DEBUG_SYNC` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | debug/comparaison |
| `MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_Q6_DEVICE_SCALAR_CG` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_Q6_DISABLE_PLAN_CACHE` | booléen/env truthy sauf mention contraire | false/off |  | CUDA Q6 — prototype/chantiers futurs | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_Q6_HOST_BLOCK_SUM` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_Q6_LEGACY_HOST_SCALAR_CG` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | debug/comparaison |
| `MPCD_CUDA_Q6_LEGACY_MEAN_REMOVAL_RESIDUAL_NORM` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | debug/comparaison |
| `MPCD_CUDA_Q6_RESIDENT_0400` | booléen/env truthy | false/off | projectionBackend, projectionEnable, speciesQ6Mode | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0400) |
| `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407` | booléen/auto | auto backend; x7i: 1 Q6 legacy petits cas, 0 Q6-g-f et grand IO |  | CUDA Q6 résident 0400–0409 | présent; politique de qualification précisée 0493x7q/x7i |
| `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_MAX_CELLS_0407` | entier | 65536 |  | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0407) |
| `MPCD_CUDA_Q6_RESIDENT_SKIP_STEP_BOUNDARY_SYNC_0400` | booléen/env truthy | false/off |  | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0400) |
| `MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404` | booléen/env truthy | false/off | speciesQ6Mode | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0404) |
| `MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409` | booléen/env truthy | false/off | speciesQ6Mode | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0409) |
| `MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401` | booléen/env truthy | false/off | speciesQ6Mode | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0401) |
| `MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402` | booléen/env truthy | false/off | speciesQ6Mode | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0402) |
| `MPCD_CUDA_Q6_RESIDENT_STRICT_0400` | booléen/env truthy | false/off | speciesQ6Mode | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0400) |
| `MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400` | booléen/env truthy | false/off | speciesQ6Mode | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0400) |
| `MPCD_CUDA_Q6_RESIDENT_WARM_START_0408` | booléen/env truthy | false/off |  | CUDA Q6 résident 0400–0409 | présent état 36abd23; inventorié 0490p (0408) |
| `MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA Q6 — prototype/chantiers futurs | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_Q6_TIMING` | booléen/env truthy sauf mention contraire | false/off |  | CUDA Q6 — prototype/chantiers futurs | diagnostic/profilage |
| `MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0472) |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304` | booléen/env truthy | false/off |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0304 |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY` | entier | 1 à 20 selon script |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0304 |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_THREADS` | entier | 256 |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0304) |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY` | booléen/env truthy | true dans les diagnostics |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0304 |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN` | entier | 6 dans les scripts de diagnostic |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0304 |
| `MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0458) |
| `MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0468) |
| `MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0455) |
| `MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461` | entier | 1 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0461) |
| `MPCD_CUDA_RESAMPLING_DIAG_CSV_0484` | booléen/env truthy | true sauf production strip 0484 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0484) |
| `MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0471) |
| `MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0459) |
| `MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319` | booléen/env truthy | false/off |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0319) |
| `MPCD_CUDA_RESAMPLING_EXTRACTION_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_EXTRACTION_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_RESAMPLING_FULL_GATE_0484` | booléen/env truthy | true sauf production strip 0484 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0484) |
| `MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U` | réel | 1.0 |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0305 |
| `MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0473) |
| `MPCD_CUDA_RESAMPLING_INSERTION_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_INSERTION_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296` | booléen/env truthy | false/off |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY` | entier | 10 ou 20 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH` | double | 1.0 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_THREADS` | entier | 256 |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0296) |
| `MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0475b) |
| `MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0475a) |
| `MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0475) |
| `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298` | booléen/env truthy | true en guard actif |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL` | double | 1e-14 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE` | double | 4.0 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MIN_CURRENT_KREL` | double >= 0 | 1e-30 |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0298) |
| `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL` | double | 1e-12 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0453) |
| `MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453` | entier | 1 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0453) |
| `MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD` | réel | 1.0 |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0306 |
| `MPCD_CUDA_RESAMPLING_PERSISTENT_0240` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES` | entier | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE` | string | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | prototype/préservé, hors jalon SRC classic 0286 |
| `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0243_STRICT_ROLES_ONLY` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0448) |
| `MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0445) |
| `MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_EVERY_0445` | entier | 1 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0445) |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297` | booléen/env truthy | false/off |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY` | entier | 20 nominal |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_LEGACY_TAIL_SPLIT` | booléen/env truthy | false/off |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0297) |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_MIN_DONOR_MASS_AFTER_SPLIT` | double >= 0 | 1e-12 |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0297) |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX` | entier | 32 nominal |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN` | entier | 12 nominal |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET` | entier | 20 nominal |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION` | double | 0.5 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_THREADS` | entier | 256 |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0297) |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE` | booléen/env truthy | true/on dans scripts 0300+ |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS` | entier | 0 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS` | entier | 1 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS` | entier | 0 |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_PRODUCTION_STRIP_0484` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0484) |
| `MPCD_CUDA_RESAMPLING_REMAP_CELL_COUNT_DIAG_0484` | booléen/env truthy | true sauf production strip 0484 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0484) |
| `MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0467b) |
| `MPCD_CUDA_RESAMPLING_RESIDENT_NO_FINAL_DOWNLOAD_PROBE_0469` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0469) |
| `MPCD_CUDA_RESAMPLING_RESIDENT_UPSTREAM_COUPLED_PROBE_0470` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0470) |
| `MPCD_CUDA_RESAMPLING_SHADOW` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_SHADOW_COMPARE_PLAN` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_SHADOW_CSV` | string | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_SHADOW_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0472) |
| `MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_DONOR_MIN_MASS_0307` | réel | 1.0 en mode cautious |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0307 |
| `MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_HALO_CELLS_0307` | entier | 1 |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0307) |
| `MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307` | entier/enum 0 normal, 1 cautious, 2 off | 0 nominal |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0307 |
| `MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0461) |
| `MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307` | réel | 0.5 |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0307; nominal 0308 |
| `MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307` | réel | 0.25 |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0307; nominal 0308 |
| `MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307` | booléen/env truthy | true |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0307; nominal 0308 |
| `MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307` | booléen/env truthy | true dans scripts resampling nominal 0308+ |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0307; nominal 0308 |
| `MPCD_CUDA_RESAMPLING_SUCCESS_CSV_0484` | booléen/env truthy | hérite de DIAG_CSV_0484 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0484) |
| `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295` | booléen/env truthy | false/off sauf scripts 0295+ |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY` | entier | 10 ou cadence script |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE` | string | full |  | CUDA resampling post-SRC — survey et guard | ajout 0295-0303 |
| `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_THREADS` | entier | 256 |  | CUDA resampling post-SRC — compléments 0295–0319 | présent état 36abd23; inventorié 0490p (0295) |
| `MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0460) |
| `MPCD_CUDA_RESAMPLING_TINY_MASS_THRESHOLD_0307` | réel | 0.1 ou valeur script |  | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0307 |
| `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_CSV` | string | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_MAX_TRANSFERS` | entier | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_UNIQUE_RECEIVER` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA resampling — prototype/préservé | debug/comparaison |
| `MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0451) |
| `MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451` | entier | 1 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0451) |
| `MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0450) |
| `MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450` | entier | 1 |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0450) |
| `MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0474) |
| `MPCD_CUDA_RESIDENT_PROFILE_0266` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0267` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0268` | booléen/env truthy sauf mention contraire | false/off |  | CUDA SRC classic — inlet/outlet full-face | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0269A` | booléen/env truthy sauf mention contraire | false/off |  | CUDA SRC classic — inlet/outlet segmenté | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0270` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0271` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0272` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0273` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_CUDA_RESIDENT_PROFILE_0274` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_CUDA_ROLE_FILTER_FULL_ROLE_SCAN_0315D` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315d) |
| `MPCD_CUDA_SHARED_STATE_DOWNLOAD_ALL_LEGACY_0315D` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315d) |
| `MPCD_CUDA_SRC_COLLISION_ACTIVE_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_SRC_COLLISION_SHADOW` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_SRC_COLLISION_SHADOW_EVERY` | entier | false/off sauf activation par scripts validés |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_SRC_COLLISION_SHADOW_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_SRC_COLLISION_SHADOW_TOL` | double | false/off sauf activation par scripts validés |  | CUDA collision SRC | debug/comparaison |
| `MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK` | entier | 256 le plus souvent |  | CUDA collision SRC | réglage performance/interne |
| `MPCD_CUDA_SRC_COLLISION_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA collision SRC | interne/runtime |
| `MPCD_CUDA_STREAMING_PERIODIC_0245` | booléen/env truthy | false/off sauf scripts CUDA |  | Streaming CUDA résident | interne/runtime \| confirmé 0334a |
| `MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — périodique | réglage performance/interne |
| `MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — périodique | réglage performance/interne |
| `MPCD_CUDA_STREAMING_PISTON_0247B` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — piston/mobile wall | interne/runtime |
| `MPCD_CUDA_STREAMING_PISTON_0247B_DOWNLOAD_ALL` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — piston/mobile wall | réglage performance/interne |
| `MPCD_CUDA_STREAMING_PISTON_0247B_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — piston/mobile wall | réglage performance/interne |
| `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — wall-simple | interne/runtime |
| `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA SRC classic — wall-simple | réglage performance/interne |
| `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS` | entier | 256 le plus souvent |  | CUDA SRC classic — wall-simple | réglage performance/interne |
| `MPCD_CUDA_STREAMING_WALL_SIMPLE_DOWNLOAD_ALL_LEGACY_0315K` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315k) |
| `MPCD_CUDA_THERMOSTAT_PERSISTENT_0258` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA thermostat | interne/runtime |
| `MPCD_CUDA_THERMOSTAT_PERSISTENT_0258_METADATA_CACHE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA thermostat | interne/runtime |
| `MPCD_CUDA_THERMOSTAT_PERSISTENT_0258_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_THERMOSTAT_SHADOW` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_THERMOSTAT_SHADOW_DIAG_TOL` | double | false/off sauf activation par scripts validés |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_THERMOSTAT_SHADOW_EVERY` | entier | false/off sauf activation par scripts validés |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_THERMOSTAT_SHADOW_STRICT` | booléen/env truthy sauf mention contraire | souvent true dans validateurs; dépend du module |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_THERMOSTAT_SHADOW_TOL` | double | false/off sauf activation par scripts validés |  | CUDA thermostat | debug/comparaison |
| `MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK` | entier | 256 le plus souvent |  | CUDA thermostat | réglage performance/interne |
| `MPCD_CUDA_THERMOSTAT_USE` | booléen/env truthy sauf mention contraire | false/off sauf activation par scripts validés |  | CUDA thermostat | interne/runtime |
| `MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1` | booléen/env truthy | false/off |  | CUDA wall-simple / boîte fermée | présent depuis 0493x1; ajouté lors du contrôle exhaustif 0493x7q |
| `MPCD_DARCY_EXACT_MOMENTUM_DIAG_0493X8A` | booléen/env truthy | 0/off |  | Darcy — diagnostic impulsion exacte | présent source courant; diagnostic; absent inventaire précédent |
| `MPCD_DARCY_FASTFLAGS_ENABLE` | booléen \| booléen/env truthy | 1 |  | Alias script fastflags Darcy \| Darcy/Brinkman CUDA résident — fastflags | ajout/documenté 0426 \| ajout 0426 |
| `MPCD_DEPOSIT_PROFILE` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_DISABLED_RESAMPLING_SUMMARY_DIAGNOSTICS_0315G` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315g) |
| `MPCD_ELLIPTIC_PROFILE` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_ENABLE_LIVE_VIS` | booléen/env truthy | false/off |  | Build option live visualization | ajout 0335 |
| `MPCD_ENSURE_PARTICLE_ROLES_FULL_REFRESH_0315M` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315m) |
| `MPCD_FILTERED_FIELD_RECORD_EVERY` | entier > 0 si présent | absent par défaut; sinon override explicite |  | Filtered field recording 0432a | ajout 0432a \| mis à jour 0433a |
| `MPCD_FILTERED_FIELD_RECORD_FIELDS` | liste CSV de champs | current |  | Filtered field recording 0432a | ajout 0432a |
| `MPCD_FILTERED_FIELD_RECORDING_0432` | booléen/env truthy | false/off |  | Filtered field recording 0432a | ajout 0432a |
| `MPCD_FILTERED_FIELD_SAMPLE_EVERY` | entier >= 1 | 1 |  | Filtered field recording 0432a | ajout 0432a |
| `MPCD_FILTERED_FIELD_TAU` | double >= 0 | 0.0 |  | Filtered field recording 0432a | ajout 0432a |
| `MPCD_INTERNAL_PROFILES` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage \| propagé scripts Darcy 0426 |
| `MPCD_LIVE_VIS_ALPHA` | double [0,1] | 0.08 scripts 0337 |  | Live visualization runtime | ajout 0335c \| alias/fallback MPCD_* recensé 0432a \| précisé 0436b |
| `MPCD_LIVE_VIS_CLIP` | double; <=0 auto | -1 auto |  | Live visualization runtime | ajout 0335c \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_COLORMAP` | enum: blue_red \| gray \| thermal | blue_red |  | Live visualization colormap | ajout 0342a \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_CONTROL_EVERY` | entier >= 1 | 1 |  | Live visualization runtime control | ajout 0341a \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_CONTROL_FILE` | chemin fichier .kv | vide/off si non fourni |  | Live visualization runtime control | ajout 0341a; propagé scripts 0341b/0341d \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_CONTROL_LOG` | booléen/env truthy | 1 dans scripts 0341b/0341d |  | Live visualization runtime control | ajout 0341a \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_ENABLE` | booléen/env truthy | copie de LIVE_VIS_ENABLE/SRC_LIVE_VIS_ENABLE |  | Live visualization runtime | mis à jour 0426 |
| `MPCD_LIVE_VIS_EVERY` | entier > 0 | 10 code; 20 scripts 0337 |  | Live visualization runtime | ajout 0335 \| mis à jour 0339a \| alias/fallback MPCD_* recensé 0432a \| mis à jour 0433a |
| `MPCD_LIVE_VIS_FIELD` | string: mêmes valeurs que SRC_LIVE_VIS_FIELD | fallback si SRC_LIVE_VIS_FIELD absent |  | Live visualization runtime | mis à jour 0361 |
| `MPCD_LIVE_VIS_GAIN` | double > 0 | 1.0 |  | Live visualization runtime | ajout 0335c/0337 \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_HOLD_ON_EXIT` | booléen/env truthy | 1 dans scripts interactifs; 0 recommandé en batch |  | Live visualization runtime | ajout 0421; propagé Darcy 0425/0426 \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_NO_SOLID_OVERLAY` | voir alias SRC_* correspondant | voir alias SRC_* correspondant |  | Live visualization runtime | alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_NX` | entier >= 16 | 300 scripts 0337 |  | Live visualization runtime | ajout 0335/0337 \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_NY` | entier >= 16 | 80 scripts 0337 |  | Live visualization runtime | ajout 0335/0337 \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_PARTICLE_TYPE_FILTER` | entier | -1 |  | Live visualization runtime / particle type filter 0436 | ajout 0436 alias/fallback MPCD_* |
| `MPCD_LIVE_VIS_QUANTILE` | double dans (0,1] | 0.995 |  | Live visualization runtime | ajout 0335c \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_QUIVER_MIN_SPEED` | double >= 0 | 0 |  | Live visualization runtime | ajout 0364 |
| `MPCD_LIVE_VIS_QUIVER_NX` | entier >= 1 | 60 |  | Live visualization runtime | ajout 0364 |
| `MPCD_LIVE_VIS_QUIVER_NY` | entier >= 1 | 32 |  | Live visualization runtime | ajout 0364 |
| `MPCD_LIVE_VIS_QUIVER_SCALE` | double | -1 |  | Live visualization runtime | ajout 0364 |
| `MPCD_LIVE_VIS_QUIVER_SMOOTH_PASSES` | entier; -1 ou >=0 | -1 |  | Live visualization runtime | ajout 0365 |
| `MPCD_LIVE_VIS_SMOOTH_PASSES` | entier >= 0 | 1 scripts 0337 |  | Live visualization runtime | ajout 0335c/0337 \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_VSYNC` | booléen/int | 0 scripts 0337 |  | Live visualization runtime | ajout 0335 \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_LIVE_VIS_WINDOW_SCALE` | entier >= 1 | 1 |  | Live visualization runtime | ajout 0335 \| alias/fallback MPCD_* recensé 0432a |
| `MPCD_MASS_GUARD_PROFILE` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_POP_GUARD_PROFILE` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_PROFILE_PHASE` | booléen/env truthy sauf mention contraire | false/off |  | Profilage / instrumentation | diagnostic/profilage |
| `MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I` | booléen/env truthy | false/off |  | Q6-G-F — mouillage expérimental | ajout 0493x9i; legacy/ablation |
| `MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M` | booléen/env truthy | false/off; runners x9m/x9p peuvent mettre 1 |  | Q6-G-F — mouillage | ajout 0493x9m; fermeture statique préférée actuelle |
| `MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L` | booléen/env truthy | false/off |  | Q6-G-F — mouillage expérimental | ajout 0493x9l; ablation |
| `MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F` | booléen/env truthy | false/off |  | Q6-G-F — diagnostics capillaires | ajout 0493x9f; diagnostic seulement |
| `MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y` | booléen/env truthy | ON si variable absente/vide; OFF seulement si valeur non-truthy explicite |  | Q6 — ablation fermeture B1 périodique | présent source courant; défaut production ON; absent inventaire précédent |
| `MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1` | booléen/env truthy | false/off backend; 1 dans les runners Q6-g-f |  | Q6-g-f / application face-particule | ajout 0493x6h-B1; production Q6-g-f; fermeture k=0 exacte x7q |
| `MPCD_Q6_G_F_RESIDENT_CG_0493X7J` | booléen/env truthy | true/on si variable absente ou vide |  | Q6-g-f / CG CUDA résident | ajout 0493x7j; production qualifiée x7q |
| `MPCD_Q6_PHASE_CURVATURE_AUDIT_WALL_MARGIN_CELLS_0493X9B` | entier >=0 | 8 |  | Q6 — diagnostic courbure | présent source courant; diagnostic; absent inventaire précédent |
| `MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A` | booléen/env truthy | false/off |  | Q6-G-F — diagnostics de courbure | ajout 0493x9a; diagnostic seulement |
| `MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B` | booléen/env truthy | false/off |  | Q6-G-F — diagnostics de courbure | ajout 0493x9b; diagnostic seulement |
| `MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C` | booléen/env truthy | false/off |  | Q6-G-F — diagnostics de courbure | ajout 0493x9c; diagnostic seulement |
| `MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G` | booléen/env truthy | false/off |  | Q6 phase/interface 0493x6 | ajout 0493x6g |
| `MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G` | double fini | 0.0 backend; runner=reference |  | Q6 phase/interface 0493x6 | ajout 0493x6g |
| `MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G` | enum string | eos |  | Q6 phase/interface 0493x6 | 0493x6g; étendu x14s avec eos_accessible_volume |
| `MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G` | double fini | 0.0 backend; runner EOS=pression uniforme initiale |  | Q6 phase/interface 0493x6 | ajout 0493x6g |
| `MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G` | double >= 0 | 1.0 |  | Q6 phase/interface 0493x6 | ajout 0493x6g |
| `MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D` | booléen/env truthy | false/off |  | Q6 phase/interface 0493x6 | ajout 0493x6d; expérimental/non retenu comme chemin final |
| `MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B` | booléen/env truthy | false/off |  | Q6 phase/interface 0493x6 | ajout 0493x6b |
| `MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C` | booléen/env truthy | false/off |  | Q6 phase/interface 0493x6 | ajout 0493x6c |
| `MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F` | booléen/env truthy | false/off |  | Q6 phase/interface 0493x6 | ajout 0493x6f; correctif partition near-half conservé dans Q6-g-f |
| `MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E` | booléen/env truthy | false/off |  | Q6 phase/interface 0493x6 | ajout 0493x6e |
| `MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A` | booléen/env truthy | false/off |  | Q6 phase/interface 0493x6 | ajout 0493x6a |
| `MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0` | booléen/env truthy | false/off |  | Q6-g-f / diagnostic post-application | ajout 0493x6h-B0; diagnostic seulement |
| `MPCD_Q6_PROFILE` | booléen/env truthy sauf mention contraire | false/off |  | CUDA Q6 — prototype/chantiers futurs | diagnostic/profilage |
| `MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E` | booléen/env truthy | false/off |  | Q6-G-F — diagnostics capillaires | ajout 0493x9e; diagnostic seulement; sigma=0 restauré x11c-fix6 |
| `MPCD_RESAMPLING_DISABLED_DIAGNOSTICS_LEGACY_0315G` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315g) |
| `MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0437) |
| `MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437_SHADOW` | booléen/env truthy | false/off |  | CUDA resampling résident — pipeline 0437–0484 | présent état 36abd23; inventorié 0490p (0437) |
| `MPCD_RUNTIME_BACKEND` | string | utilisé si MPCD_BACKEND absent; cuda par défaut dans runner primaire |  | Backend principal | principal utilisateur |
| `MPCD_VALIDATE_PARTICLE_ROLES_FULLSCAN_0315L` | booléen/env truthy | false/off |  | CUDA état résident / active-prefix — audit et compatibilité | présent état 36abd23; inventorié 0490p (0315l) |
| `MPCD_X10_KINETIC_INTERFACE_CIC` | booléen/env int | 0/off source; 1 dans x12 production |  | Surface libre cinétique — géométrie CIC x10cic | actif dans chaîne x12 courante; ON |
| `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE` | booléen/env int | 0/off source; 1 dans x12 production |  | Surface libre cinétique — relocalisation x10u | actif dans chaîne x12 courante; ON \| qualifié/tag 7655b81 au 31/08/2026 |
| `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY` | booléen/env int | 0/off |  | Surface libre cinétique — ablation x13o normal-only | implémenté au commit 7655b81; OFF dans chaîne qualifiée/tag surf-tension-qualified-x13h-20260831 |
| `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP` | booléen/env int | 0/off source; 1 dans x12 production |  | Surface libre cinétique — échange conservatif x10v | actif dans chaîne x12 courante; ON \| qualifié/tag 7655b81 au 31/08/2026 |
| `MPCD_X10_KINETIC_INTERFACE_QUADRATIC` | booléen/env int | 0/off source; 1 dans x12 production |  | Surface libre cinétique — reconstruction vrai Q2 x10biq | actif dans chaîne x12 courante; ON |
| `MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER` | booléen/env int | 0/off |  | Surface libre cinétique — branche x10w pairwise | implémenté; OFF chaîne x12 courante |
| `MPCD_X10_MICRO_REFLECTION_TRACE` | booléen/env int | 0/off |  | Surface libre cinétique — diagnostic microscopique | diagnostic source courant; OFF production |
| `MPCD_X10I_REACTION_BLOCK_CELLS` | entier | 5; clamp [2,32] |  | Surface libre cinétique — réaction mésoscopique héritée x10i | implémentation active uniquement dans le fallback cinétique hard-r1; hors chaîne x12 production |
| `MPCD_X10J_SIMPLE_SPECULAR_ABLATION` | booléen/env int | 0/off |  | Surface libre cinétique — ablations x10 | implémentation historique retenue dans le source; OFF chaîne x12 courante |
| `MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION` | booléen/env int | 0/off |  | Surface libre cinétique — ablations x10 | implémentation historique retenue dans le source; OFF chaîne x12 courante |
| `MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS` | booléen/env int | 0/off source; x12d JFM=1; x12cal/x12yl=0 | summaryEvery | Surface libre cinétique — diagnostic | diagnostic passif courant; ON JFM x12d, OFF calibrateurs x12cal/x12yl |
| `MPCD_X10M_MOVING_INTERFACE_WALL` | booléen/env int | 0/off |  | Surface libre cinétique — ablations x10 | implémentation historique selectable; OFF chaîne x12 courante |
| `MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL` | booléen/env int | 0/off |  | Surface libre cinétique — ablations x10 | implémentation historique selectable; OFF chaîne x12 courante |
| `MPCD_X10O_Q6_THERMAL_INTERFACE_WALL` | booléen/env int | 0/off source; 1 dans x12 production |  | Surface libre cinétique — chaîne retenue | socle cinétique de la chaîne x12 courante; ON |
| `MPCD_X10O_THERMAL_MAX_CELLS` | double >=0 | 0.75 |  | Surface libre cinétique — enveloppe thermique | paramètre env actif dans chaîne x10o/x12 |
| `MPCD_X10O_THERMAL_PARTICLE_MASS` | double >0 | 1.0 source; runners x12: LIQUID_MASS |  | Surface libre cinétique — enveloppe thermique | paramètre env actif dans chaîne x10o/x12 |
| `MPCD_X10O_THERMAL_SIGMAS` | double >=0 | 3.0 |  | Surface libre cinétique — enveloppe thermique | paramètre env actif dans chaîne x10o/x12 |
| `MPCD_X10P_INITIAL_OVERLAP_RESOLUTION` | booléen/env int | 1/on si x10o est actif |  | Surface libre cinétique — robustesse topologique | robustesse active dans chaîne x12; ON |
| `MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY` | booléen/env int | 0/off |  | Surface libre cinétique — ablation cinématique x10r | implémentation retenue pour ablation; OFF chaîne x12 courante |
| `MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS` | booléen/env int | 0/off |  | Surface libre cinétique — ablation cinématique x10s | implémentation retenue pour ablation; OFF chaîne x12 courante |
| `MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS` | booléen/env int | 0/off |  | Surface libre cinétique — ablation cinématique x10t | implémentation retenue pour ablation; OFF chaîne x12 courante |
| `MPCD_X10W_THERMAL_PHASE_CHI_FULL` | double > chiOn | 0.028 |  | Surface libre cinétique — seuil x10w | paramètre de branche x10w; branche OFF production |
| `MPCD_X10W_THERMAL_PHASE_CHI_ON` | double >0 | 0.022 |  | Surface libre cinétique — seuil x10w | paramètre de branche x10w; branche OFF production |
| `MPCD_X10W_THERMAL_PHASE_ETA_CAP` | double >0 | 0.05724334 |  | Surface libre cinétique — seuil x10w | paramètre de branche x10w; branche OFF production |
| `MPCD_X11C_FORCE_X9E_SIGMA0` | booléen/env truthy | 0/off |  | Validation capillaire x11 — diagnostics | flag de runner x11c/x12yl; diagnostic uniquement; non lu directement par C++ |
| `MPCD_X12A_LOCAL_THERMAL_COOLING` | booléen/env int | 0/off source; 1 dans x12 production |  | Surface libre cinétique — refroidissement local x12a | actif dans chaîne x12 courante; ON \| qualifié/tag 7655b81 au 31/08/2026 |
| `MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS` | double >0 lorsque x12a ON | 25.298221281347036 (=8*sqrt(10)) |  | Surface libre cinétique — échelle x12a | paramètre actif dans chaîne x12 courante \| qualifié/tag 7655b81 au 31/08/2026 |
| `MPCD_X14L_GAS_SPECULAR_REFLECTION` | booléen entier 0/1 | 0 | phaseInterfaceKineticBilateralRelocation | Interface liquide/gaz x14 | ajout 0493x14l; actif dans la chaîne x14m+ |
| `MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14ai-fix1 — fermeture conservative | candidat production x14ai-fix1 pour composante liquide fermée/isolée; OFF par défaut |
| `MPCD_X14V_GAS_KINETIC_EXCESS_KICK` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14 | ajout 0493x14v; qualifié sur impact normal et actif dans x14w |
| `MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14af — diagnostic | diagnostic x14af uniquement; OFF production |
| `MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14z — prototype de résultante | prototype x14z rejeté; OFF production |
| `MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14ae — diagnostic | diagnostic x14ae uniquement; OFF production |
| `MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION` | booléen entier 0/1 | 1 |  | Interface liquide/gaz x14v — séparation thermo/cinétique | ajout 0493x14y; production x14v/x14ai-fix1 = 1 |
| `MPCD_X14V_X6G_FACE_THERMO_TRACTION` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14aa — prototype de traction | prototype x14aa non retenu; OFF production |
| `MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14ab — prototype hybride | prototype x14ab non retenu; OFF production |
| `MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14ac — projection de résultante | prototype x14ac supplanté par x14ad; OFF production |
| `MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION` | booléen entier 0/1 | 0 |  | Interface liquide/gaz x14ad — traction locale retenue | retenu x14ad; prérequis x14ai-fix1 pour composante liquide fermée |
| `NX` | entier >0 | 64 | Nx | Validateurs CUDA resampling — géométrie | lecture C++ directe dans validateurs shadow; également variable shell courante des runners |
| `NY` | entier >0 | 32 | Ny | Validateurs CUDA resampling — géométrie | lecture C++ directe dans validateurs shadow; également variable shell courante des runners |
| `OMP_DYNAMIC` | booléen OpenMP | false |  | OpenMP runtime | documenté 0426 |
| `OMP_NUM_THREADS` | entier positif | THREADS du script |  | OpenMP runtime | documenté 0426 |
| `OMP_PLACES` | chaîne OpenMP | cores |  | OpenMP runtime | documenté 0426 |
| `OMP_PROC_BIND` | chaîne OpenMP | close |  | OpenMP runtime | documenté 0426 |
| `OUT_CSV` | chemin de fichier CSV | nom propre au validateur |  | Validateurs CUDA resampling — sortie | présent code; ajouté consolidation 0493w8 |
| `OUTLET_FACE` | double/chaîne selon variable | right |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `OUTLET_FORCED_LAYER_CELLS` | entier | 3 dans la démo boîte; défaut noyau 1 | openBoundaryOutletForcedLayerCells | Scripts démo 0283/0291 — inlet/outlet | contrôle utilisateur script |
| `OUTLET_FORCED_MASS_FLUX` | double | 0.0 | openBoundaryOutletForcedMassFlux | Scripts démo 0283/0291 — inlet/outlet | contrôle utilisateur script |
| `OUTLET_FORCED_MASS_PER_STEP` | double | 0.0 | openBoundaryOutletForcedMassPerStep | Scripts démo 0283/0291 — inlet/outlet | contrôle utilisateur script |
| `OUTLET_FORCED_PARTICLE_FLUX` | double | 0.0 | openBoundaryOutletForcedParticleFlux | Scripts démo 0283/0291 — inlet/outlet | contrôle utilisateur script |
| `OUTLET_FORCED_PARTICLES_PER_STEP` | entier | 0 | openBoundaryOutletForcedParticlesPerStep | Scripts démo 0283/0291 — inlet/outlet | contrôle utilisateur script |
| `OUTLET_MODE` | double/chaîne selon variable \| string | hybrid/neumann selon script \| neumann dans scripts mis à jour | openBoundaryOutletMode | Alias script géométrie/segments Darcy \| Scripts démo 0283/0291 — inlet/outlet | ajout/documenté 0426 \| contrôle utilisateur script |
| `OUTLET_SMAX` | double/chaîne selon variable | 1.0 ou 0.25 selon script |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `OUTLET_SMIN` | double/chaîne selon variable | 0.0 |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `PARTICLE_TYPE_FILTER` | entier | -1 |  | Alias script livevis / filtrage type 0436 \| Alias script livevis / particle type filter 0436 | ajout runner 0436 |
| `PHASE_INTERFACE_KINETIC_BILATERAL_RELOCATION` | booléen | true dans les runners liquide/gaz x14k+ | phaseInterfaceKineticBilateralRelocation | Runner x14 — interface | alias conceptuel / écriture params x14k |
| `POSTCHECK_SPECIES_ENABLE` | booléen | true | speciesDiagnosticsEnable | Alias runner / validation injection | ajout/normalisé 0493w4–0493w8 |
| `PREFLIGHT_ONLY` | booléen/int \| booléen | 0 |  | Alias runner / validation \| Runner qualification 0493x7i / préflight | ajout/normalisé 0493w4–0493w8 \| profil final x7q/x7i |
| `PROJECTION_MOMENTUM_CORRECTION_ENABLE` | booléen | false dans 0493w8 | projectionMomentumCorrectionEnable | Alias runner / projection Q6 | documenté 0493w8 |
| `PROJECTION_TOLERANCE` | double >0 | 1.0e-5 dans la qualification finale | projectionTolerance | Alias script projection Q6 | documenté x5b–x6g; profil de qualification final x7q/x7i |
| `PUDDLE_DEPTH_CELLS` | double >=0 | 40 |  | Alias runner — splash x9s | ajout 0493x9s |
| `Q6_DENSITY_RELAXATION_BETA` | double [0,1] | 0.0 | q6DensityRelaxationBeta | Alias runner Q6-g-f / restauration de densité | ajout runner 0493x7c; conservé 0493x7d/x7e |
| `Q6_DENSITY_RELAXATION_TIME` | double >=0 | 0.0 runner historique; tau=0.25 dans la chaîne qualifiée | q6DensityRelaxationTime | Alias runner historique Q6-g-f / restauration de densité | ajout 0493x7d; remplacé dans le helper commun par profil Q6_GF; valeur physique toujours qualifiée x7q |
| `Q6_FORCE_PROJECTION_MODE` | enum string | selon runner; prestream_single_fused dans les runners surface libre | q6ForceProjectionMode | Alias script 0493x force-aware | ajout runners 0493x3–0493x5; réutilisé Q6-g-f jusqu’à x7e |
| `Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE` | booléen | 0 helper générique; 1 profil x7i |  | Alias run_ok Q6-g-f / densité signée | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES` | double >=0 | 3.0 |  | Alias run_ok Q6-g-f / densité signée | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_DENSITY_RELAXATION_TIME` | double >=0 | 0.25 | q6DensityRelaxationTime | Alias run_ok Q6-g-f / densité | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_DENSITY_TRACTION_GAIN` | double >=0 | 0.0 helper générique; 1.0 profil x7i | q6DensityRelaxationTractionGain | Alias run_ok Q6-g-f / densité signée | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES` | double >=0 | 6.0 |  | Alias run_ok Q6-g-f / densité signée | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_EXTERNAL_SPECIES` | booléen | 0 |  | Alias run_ok Q6-g-f / registre espèces | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_GAS_PRESSURE_REFERENCE` | double >=0 | gamma*kBT/cellArea si non fourni |  | Alias run_ok Q6-g-f / pression gazeuse | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_HAS_GAS_PHASE` | booléen | 0 |  | Alias run_ok Q6-g-f / registre phases | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_MIN_FILL_FRACTION` | double [0,1] | 0.10 | speciesQ6MinOccupancyFraction | Alias run_ok Q6-g-f / support | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_SINGLE_PHASE_PARTICLE_MASS` | double >0 | PARTICLE_MASS |  | Alias run_ok Q6-g-f / espèce monophase | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_SINGLE_PHASE_TYPE` | entier type | BACKGROUND_TYPE ou 0 |  | Alias run_ok Q6-g-f / espèce monophase | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_GF_SPECIES_DIAGNOSTICS_ENABLE` | booléen texte | false | speciesDiagnosticsEnable | Alias run_ok Q6-g-f / diagnostics espèces | documenté helper commun 0493x7h; profil final x7q/x7i |
| `Q6_PRESSURE_OUTLET_DEFLATION_ENABLE` | booléen | true | q6PressureOutletDeflationEnable | Runner 0414 / x8s ablation | ajout 0414d |
| `QUAL_MODES` | liste/chaîne | src src-q6 src-q6-g-f |  | Runner qualification 0493x7i / sélection de modes | profil final x7q/x7i |
| `RECORD_FIELDS` | liste CSV de champs | rho,ux,uy dans les profils 0434 récents \| rho,ux,uy dans les profils récents |  | Alias script filtered recording 0434/0436 | documenté 0436 |
| `REQUIRE_MIXED_CELL_AT_END` | booléen | false | speciesCellDiagnosticsEnable | Alias runner / validation injection | ajout/normalisé 0493w4–0493w8 |
| `REQUIRE_VALIDATED_SEGMENTED_RESIDENT` | booléen | 1 |  | Alias script sécurité CUDA | ajout/documenté 0426 |
| `RUN_MODES` | liste de modes: src; src-q6; src-resampling; src-q6-resampling | dépend du runner; src src-q6 pour les comparaisons injection/TG |  | Alias script / cas de run | existant; utilisé scripts portables |
| `RUN_OK_DARCY_COMMON_FILLED_STATE` | booléen | 0 |  | Alias run_ok Darcy / qualification | documenté helper commun 0493x7h; profil final x7q/x7i |
| `RUN_ROOT` | chaîne chemin | runs/0493x7q_q6_g_f_physical_qualification |  | Runner qualification 0493x7i / racine de sortie | profil final x7q/x7i |
| `RUN_ZERO_REFERENCE` | booléen/int 0\|1 | 1 |  | Alias script 0493x6g final | ajout runner 0493x6g |
| `SCENARIO_EXPECTATION` | empty\|two_species | cohérent avec INITIAL_DOMAIN_MODE |  | Alias runner / validation injection | ajout/normalisé 0493w4–0493w8 |
| `SCENARIOS` | liste de noms | mono_legacy mono_independent dual_identical |  | Alias runner / matrice TG | ajout/normalisé 0493w4–0493w8 |
| `SEED` | uint64 | 1628638 |  | Validateurs CUDA resampling — reproductibilité | lecture C++ directe dans validateurs shadow; également variable shell courante des runners |
| `SEEDS` | liste d’entiers | 493801 |  | Alias runner / ensemble statistique | ajout/normalisé 0493w4–0493w8 |
| `SIGMA_ACTIVE` | double >=0 | dépend du runner; x12b/x12c/x12d JFM: 392.149185; x12a splash: campagne-dépendant | surfaceTensionSigma | Alias runner — tension superficielle | runner alias courant; x12 splash/JFM |
| `SPECIES_Q6_COMPARISON_TOLERANCE` | double >0 | 1.0e-11 | speciesQ6ComparisonTolerance | Alias runner / Q6 multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `SPECIES_Q6_ENABLE` | booléen | true dans le runner injection; selon scénario TG | projectionEnable, speciesQ6Enable | Alias runner / Q6 multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `SPECIES_Q6_FALLBACK_MODE` | common\|fatal | common | speciesQ6FallbackMode | Alias runner / Q6 multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `SPECIES_Q6_MIN_FILL_FRACTION` | double [0,1] | 0.25 dans les premiers runners x5/x6; 0.10 dans les qualifications Q6-g-f x7d/x7e | speciesQ6MinOccupancyFraction | Alias script 0493x surface libre | ajout runner 0493x5a; réutilisé x5b–x7e |
| `SPECIES_Q6_MIN_OCCUPANCY_FRACTION` | double dans [0,1] | 0.5 injection/smokes; 0.0 dual_identical | speciesQ6MinOccupancyFraction | Alias runner / Q6 multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `SPECIES_Q6_MODE` | common\|weighted\|independent_masked | weighted dans le runner partagé historique; independent_masked par override/qualification | speciesQ6Mode | Alias runner / Q6 multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `SPECIES_Q6_SENSITIVITY` | double dans [0,1] | 1.0 dans le runner injection | speciesQ6Sensitivity | Alias runner / Q6 multi-espèces | ajout/normalisé 0493w4–0493w8 |
| `SPECIES_THERMOSTAT_ENABLE` | booléen 0/1 ou true/false | 1 dans les runners biphasés x14 | speciesThermostatEnable | Runner x14 — thermostat | alias de runner x14 |
| `SRC_FILTERED_FIELD_RECORD_EVERY` | entier > 0 si présent | absent par défaut; sinon override explicite |  | Filtered field recording 0432a | ajout 0432a \| mis à jour 0433a |
| `SRC_FILTERED_FIELD_RECORD_FIELDS` | liste CSV de champs | current |  | Filtered field recording 0432a | ajout 0432a |
| `SRC_FILTERED_FIELD_RECORDING_0432` | booléen/env truthy | false/off |  | Filtered field recording 0432a | ajout 0432a |
| `SRC_FILTERED_FIELD_SAMPLE_EVERY` | entier >= 1 | 1 |  | Filtered field recording 0432a | ajout 0432a |
| `SRC_FILTERED_FIELD_TAU` | double >= 0 | 0.0 |  | Filtered field recording 0432a | ajout 0432a |
| `SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330` | booléen/env truthy | 0 dans validations sûres |  | Diagnostics rapides immersed circle CUDA | utilisé validations 0331+ |
| `SRC_GPU_WALL_CIRCLE_RESIDENT_0318` | booléen/env truthy | false/off |  | Alias script / sécurité VK | ajout scripts 0331 |
| `SRC_GPU_WALL_FAST_DIAG_0320` | booléen/env truthy | 0 dans validations sûres |  | Diagnostics rapides wall CUDA | utilisé validations 0331+ |
| `SRC_LIVE_VIS_ALPHA` | double [0,1] | 0.08 scripts 0337 |  | Live visualization runtime | ajout 0335c \| précisé 0436b |
| `SRC_LIVE_VIS_CLIP` | double; <=0 auto | -1 auto |  | Live visualization runtime | ajout 0335c |
| `SRC_LIVE_VIS_COLORMAP` | enum: blue_red \| gray \| thermal | blue_red |  | Live visualization colormap | ajout 0342a |
| `SRC_LIVE_VIS_CONTROL_EVERY` | entier >= 1 | 1 |  | Live visualization runtime control | ajout 0341a |
| `SRC_LIVE_VIS_CONTROL_FILE` | chemin fichier .kv | vide/off si non fourni |  | Live visualization runtime control | ajout 0341a; propagé scripts 0341b/0341d |
| `SRC_LIVE_VIS_CONTROL_LOG` | booléen/env truthy | 1 dans scripts 0341b/0341d |  | Live visualization runtime control | ajout 0341a |
| `SRC_LIVE_VIS_CUDA_FIELD` | booléen/env truthy | 0 code; 1 scripts 0337 |  | Live visualization CUDA field renderer | ajout 0337a |
| `SRC_LIVE_VIS_CUDA_SNAPSHOT` | booléen/env truthy | 0 |  | Live visualization snapshot expérimental | ajout 0336a; gardé expérimental |
| `SRC_LIVE_VIS_ENABLE` | booléen/env truthy | false/off; 1 dans scripts livevis 0337 |  | Live visualization runtime | ajout 0335 |
| `SRC_LIVE_VIS_EVERY` | entier > 0 | 10 code; 20 scripts 0337 |  | Live visualization runtime | ajout 0335 \| mis à jour 0339a \| mis à jour 0433a |
| `SRC_LIVE_VIS_FIELD` | string: ux\|uy\|speed\|vorticity\|omega\|curl\|mass\|density\|N\|n\|count\|population\|particle_count\|cell_count\|chi\|topo_chi\|alpha\|darcy_alpha\|darcy_power\|darcy\|brinkman_power | ux dans code; dépend des scripts |  | Live visualization runtime | ajout 0335/0337 \| mis à jour 0361 |
| `SRC_LIVE_VIS_FORCE_HOST_MIRROR` | booléen/env truthy | 0 |  | Live visualization fallback/debug | ajout 0335c |
| `SRC_LIVE_VIS_GAIN` | double > 0 | 1.0 |  | Live visualization runtime | ajout 0335c/0337 |
| `SRC_LIVE_VIS_HOLD_ON_EXIT` | booléen/env truthy | 1 dans scripts interactifs; 0 recommandé en batch |  | Live visualization runtime | ajout 0421; propagé Darcy 0425/0426 |
| `SRC_LIVE_VIS_LOG_SOURCE` | booléen/env truthy | 0 |  | Live visualization runtime | ajout 0335c; amélioré 0337d \| mis à jour 0339a \| mis à jour 0363/0364/0365 |
| `SRC_LIVE_VIS_NO_SOLID_OVERLAY` | booléen/env truthy | false/off |  | Live visualization runtime | présent état 36abd23; inventorié 0490p (0490p) |
| `SRC_LIVE_VIS_NX` | entier >= 16 | 300 scripts 0337 |  | Live visualization runtime | ajout 0335/0337 |
| `SRC_LIVE_VIS_NY` | entier >= 16 | 80 scripts 0337 |  | Live visualization runtime | ajout 0335/0337 |
| `SRC_LIVE_VIS_PARTICLE_TYPE_FILTER` | entier | -1 |  | Live visualization runtime / particle type filter 0436 | ajout 0436 |
| `SRC_LIVE_VIS_QUANTILE` | double dans (0,1] | 0.995 |  | Live visualization runtime | ajout 0335c |
| `SRC_LIVE_VIS_QUIVER_MIN_SPEED` | double >= 0 | 0 |  | Live visualization runtime | ajout 0364 |
| `SRC_LIVE_VIS_QUIVER_NX` | entier >= 1 | 60 |  | Live visualization runtime | ajout 0364 |
| `SRC_LIVE_VIS_QUIVER_NY` | entier >= 1 | 32 |  | Live visualization runtime | ajout 0364 |
| `SRC_LIVE_VIS_QUIVER_SCALE` | double | -1 |  | Live visualization runtime | ajout 0364 |
| `SRC_LIVE_VIS_QUIVER_SMOOTH_PASSES` | entier; -1 ou >=0 | -1 |  | Live visualization runtime | ajout 0365 |
| `SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR` | booléen/env truthy | 0 scripts 0337; 1 fallback manuel |  | Live visualization fallback resampling | ajout 0335d |
| `SRC_LIVE_VIS_SMOOTH_PASSES` | entier >= 0 | 1 scripts 0337 |  | Live visualization runtime | ajout 0335c/0337 |
| `SRC_LIVE_VIS_VSYNC` | booléen/int | 0 scripts 0337 |  | Live visualization runtime | ajout 0335 |
| `SRC_LIVE_VIS_WINDOW_SCALE` | entier >= 1 | 1 |  | Live visualization runtime | ajout 0335 |
| `STATE_SOURCE` | chemin fichier | selon cas |  | Alias script état initial | ajout/documenté 0426 |
| `STEP_XMAX` | double/chaîne selon variable | 1.0 |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `STEP_XMIN` | double/chaîne selon variable | 0.0 |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `STEP_YMAX` | double/chaîne selon variable | 0.52 |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `STEP_YMIN` | double/chaîne selon variable | 0.0 |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `SUMMARY_ROLE_FILTER` | all\|fluid \| alias script utilisateur | fluid dans scripts visual 0309+ \| fluid dans scripts visuels 0309+ | summaryRoleFilter | Alias script \| CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive | ajout 0314 \| script 0314 |
| `SURFACE_TENSION_MIN_RADIUS_CELLS` | double >=0 | source Params=0.0; x12b/x12c/x12d JFM et x12yl: 4; x12cal dynamique et anciens splash x12a obstacle: 3 | surfaceTensionMinRadiusCells | Alias runner — tension superficielle | runner alias courant; valeur dépend de la campagne x12 |
| `TARGET` | wall \| puddle | wall dans runner principal; wrappers dédiés disponibles |  | Alias runner — splash x9s | ajout 0493x9s |
| `THERMOSTAT_ENABLE` | booléen/env truthy | 1 dans les démos CUDA isothermes; 0 désactive | thermostatEnable | Scripts démo 0283/0291b — thermostat | contrôle utilisateur script |
| `TOL_ABS` | double >=0 | 2e-10 |  | Validateurs CUDA resampling — tolérance | lecture C++ directe dans validateurs shadow uniquement |
| `TOL_REL` | double >=0 | 2e-12 |  | Validateurs CUDA resampling — tolérance | lecture C++ directe dans validateurs shadow uniquement |
| `TOPO_BENCHMARK_DRAG_LIFT_ENABLE` | booléen | true |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_ENABLE` | booléen | true |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_EVERY` | entier | DARCY_COST_EVERY |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_FILENAME` | nom fichier | topo_benchmark_0348.csv |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_FLOW_DIR_X` | double | 1.0 |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_FLOW_DIR_Y` | double | 0.0 |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_FORCE_ENABLE` | booléen | true |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_LIFT_DIR_X` | double | 0.0 |  | Alias script topo benchmark | ajout/documenté 0426 |
| `TOPO_BENCHMARK_LIFT_DIR_Y` | double | 1.0 |  | Alias script topo benchmark | ajout/documenté 0426 |
| `UIN` | double/chaîne selon variable | 0.25 |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `UINIT` | double/chaîne selon variable | cas dépendant |  | Alias script géométrie/segments Darcy | ajout/documenté 0426 |
| `VACUUM_BACKGROUND` | booléen shell | 1 dans les variantes liquide-vide récentes |  | Alias runner — phase extérieure | ajout 0493x9q/x9r |
| `WALL_KBT` | double | -1.0 | wallKBT | Alias script paroi/VP | ajout/documenté 0426 |
| `WALL_SPEED` | double fini non nul | 0.02 dans le runner; campagne de qualification renforcée: 0.075 |  | Runner x14w — Couette | paramètre physique visible du benchmark x14w |
| `X6G_MODE` | enum string | selon benchmark |  | Runner x14 — pression gaz | alias d’ablation/qualification x14u |
| `X7I_BEND_COMMON_FILLED_STATE` | booléen | 1 |  | Runner qualification 0493x7i / bend-pipe | profil final x7q/x7i |
| `X7I_BEND_DUMP_EVERY` | entier >=0 | 25 |  | Runner qualification 0493x7i / bend-pipe | profil final x7q/x7i |
| `X7I_BEND_START_FROM_REST` | booléen | 1 |  | Runner qualification 0493x7i / bend-pipe | profil final x7q/x7i |
| `X7I_BEND_STEPS` | entier >0 | 1000 |  | Runner qualification 0493x7i / bend-pipe | profil final x7q/x7i |
| `X7I_BEND_SUMMARY_EVERY` | entier >0 | 25 |  | Runner qualification 0493x7i / bend-pipe | profil final x7q/x7i |
| `X7I_IO_BOX_DUMP_EVERY` | entier >=0 | 50 |  | Runner qualification 0493x7i / same-face IO | profil final x7q/x7i |
| `X7I_IO_BOX_STEPS` | entier >0 | 500 |  | Runner qualification 0493x7i / same-face IO | profil final x7q/x7i |
| `X7I_IO_BOX_SUMMARY_EVERY` | entier >0 | 25 |  | Runner qualification 0493x7i / same-face IO | profil final x7q/x7i |
| `X7I_LIVE_VIS_ENABLE` | booléen | 0 |  | Runner qualification 0493x7i / LiveVis campagne | profil final x7q/x7i |
| `X7I_LIVE_VIS_HOLD_ON_EXIT` | booléen | 0 |  | Runner qualification 0493x7i / LiveVis campagne | profil final x7q/x7i |
| `X7I_POISEUILLE_BODY_AX` | double | 0.0004 |  | Runner qualification 0493x7i / Poiseuille | profil final x7q/x7i |
| `X7I_POISEUILLE_DUMP_EVERY` | entier >=0 | 500 |  | Runner qualification 0493x7i / Poiseuille | profil final x7q/x7i |
| `X7I_POISEUILLE_STEPS` | entier >0 | 30000 |  | Runner qualification 0493x7i / Poiseuille | profil final x7q/x7i |
| `X7I_POISEUILLE_SUMMARY_EVERY` | entier >0 | 100 |  | Runner qualification 0493x7i / Poiseuille | profil final x7q/x7i |
| `X7I_POISEUILLE_U0` | double | 0.0 |  | Runner qualification 0493x7i / Poiseuille | profil final x7q/x7i |
| `X7I_POISEUILLE_VELOCITY_MODE` | enum string | zero |  | Runner qualification 0493x7i / Poiseuille | profil final x7q/x7i |
| `X7I_PROJECTION_MAX_ITERATIONS` | entier >0 | 800 |  | Runner qualification 0493x7i / projection | profil final x7q/x7i |
| `X7I_PROJECTION_TOLERANCE` | double >0 | 1.0e-5 |  | Runner qualification 0493x7i / projection | profil final x7q/x7i |
| `X7I_Q6_G_F_RESIDENT_CG_0493X7J` | booléen | 1 |  | Runner qualification 0493x7i / Q6-g-f CG resident | profil final x7q/x7i |
| `X7I_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE` | booléen | 1 |  | Runner qualification 0493x7i / Q6-g-f densité | profil final x7q/x7i |
| `X7I_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES` | double >=0 | 3 |  | Runner qualification 0493x7i / Q6-g-f densité | profil final x7q/x7i |
| `X7I_Q6_GF_DENSITY_RELAXATION_TIME` | double >=0 | 0.25 |  | Runner qualification 0493x7i / Q6-g-f densité | profil final x7q/x7i |
| `X7I_Q6_GF_DENSITY_TRACTION_GAIN` | double >=0 | 1.0 |  | Runner qualification 0493x7i / Q6-g-f densité | profil final x7q/x7i |
| `X7I_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES` | double >=0 | 6 |  | Runner qualification 0493x7i / Q6-g-f densité | profil final x7q/x7i |
| `X7I_Q6_GF_MIN_FILL_FRACTION` | double [0,1] | 0.10 |  | Runner qualification 0493x7i / Q6-g-f support | profil final x7q/x7i |
| `X7I_Q6_GF_SINGLE_BLOCK_CG_0407` | booléen | 0 |  | Runner qualification 0493x7i / Q6-g-f politique CG | profil final x7q/x7i |
| `X7I_Q6_LEGACY_SINGLE_BLOCK_CG_LARGE` | booléen | 0 |  | Runner qualification 0493x7i / Q6 legacy politique CG | profil final x7q/x7i |
| `X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL` | booléen | 1 |  | Runner qualification 0493x7i / Q6 legacy politique CG | profil final x7q/x7i |
| `X7I_Q6_STRICT` | booléen | 1 |  | Runner qualification 0493x7i / Q6 strict | profil final x7q/x7i |
| `X7I_TG_DUMP_EVERY` | entier >=0 | 500 |  | Runner qualification 0493x7i / TG | profil final x7q/x7i |
| `X7I_TG_STEPS` | entier >0 | 10000 |  | Runner qualification 0493x7i / TG | profil final x7q/x7i |
| `X7I_TG_SUMMARY_EVERY` | entier >0 | 100 |  | Runner qualification 0493x7i / TG | profil final x7q/x7i |

## Fiches détaillées

### `ALPHA`

- **Type :** double
- **Défaut :** `DARCY_ALPHA_MAX ou valeur script`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Alias de darcyAlphaMax dans les scripts de démonstration.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `ALPHA_MIN`

- **Type :** double
- **Défaut :** `DARCY_ALPHA_MIN ou 0.0`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Alias de darcyAlphaMin.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `ANALYZE_ONLY`

- **Type :** booléen/int
- **Défaut :** `0`
- **Catégorie :** Alias runner / analyse
- **Statut :** ajout/normalisé 0493w4–0493w8

Réutilise les résultats existants et lance uniquement l’analyseur.

**Remarques.** Évite de recalculer les six branches après une correction du checker.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`

### `AUTO_BUILD`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Alias script / build
- **Statut :** mis à jour 0337 livevis

Autorise le script à compiler automatiquement le binaire manquant.

**Remarques.** Dans les scripts livevis, le build automatique passe MPCD_ENABLE_LIVE_VIS=1.

### `BACKGROUND_MASS_CLOSURE_STRENGTH`

- **Type :** double
- **Défaut :** `0.0 pour gas; 1.0 pour liquid`
- **Catégorie :** Alias runner / injection multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8

Définit massClosureStrengthDeclared de l’espèce de fond.

**Remarques.** Concerne le resampling; sans effet si resampling désactivé.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `BACKGROUND_PHASE`

- **Type :** liquid|gas
- **Défaut :** `gas`
- **Catégorie :** Alias runner / injection multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8

Sélectionne la famille physique de l’espèce de fond.

**Remarques.** Indépendant de BACKGROUND_TYPE.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `BACKGROUND_Q6_STRENGTH`

- **Type :** double
- **Défaut :** `0.0 pour gas; 1.0 pour liquid`
- **Catégorie :** Alias runner / injection multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8

Définit q6StrengthDeclared de l’espèce de fond.

**Remarques.** Le cas liquide->gaz qualifié utilise 1/0.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `BIN`

- **Type :** chemin exécutable
- **Défaut :** `build/src_mpcd_base_cuda_q6_resident_livevis_0486 dans les runners 0493w4–0493w8`
- **Catégorie :** Alias script / binaire
- **Statut :** mis à jour 0337 livevis

Binaire exécuté par les scripts portables livevis.

**Remarques.** Peut être surchargé; independent_masked requiert le binaire CUDA Q6 résident 0486 ou un build équivalent.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `CASES`

- **Type :** liste/chaîne
- **Défaut :** `tg poiseuille bend_pipe io_box`
- **Catégorie :** Runner qualification 0493x7i / sélection de cas
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `CHI_FILE`

- **Type :** chemin fichier
- **Défaut :** `DARCY_CHI_FILE ou chemin par défaut`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Chemin du champ chi externe côté script.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `CHI_FILE_FORMAT`

- **Type :** chaîne
- **Défaut :** `DARCY_CHI_FILE_FORMAT ou float32`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Format du champ chi externe côté script.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `CLEAN_RUN_ROOT`

- **Type :** booléen/int | booléen
- **Défaut :** `1`
- **Catégorie :** Alias runner / gestion des résultats | Runner qualification 0493x7i / nettoyage campagne
- **Statut :** ajout/normalisé 0493w4–0493w8 | profil final x7q/x7i

Supprime le run root avant une nouvelle campagne. | Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Mettre 0 pour ajouter des graines sans effacer les résultats existants. | Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w5_independent_masked_periodic_smoke.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `DARCY_ALPHA_MAX`

- **Type :** double
- **Défaut :** `selon script`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Valeur de repli utilisée par ALPHA pour écrire darcyAlphaMax.

**Remarques.** Backward step validé avec ALPHA=800000.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_ALPHA_MIN`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Valeur de repli utilisée par ALPHA_MIN pour écrire darcyAlphaMin.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_BRINKMAN_FORCING_MODE`

- **Type :** chaîne
- **Défaut :** `mean ou mean_outward_bath`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyBrinkmanForcingMode`

Alias script de darcyBrinkmanForcingMode.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_COLLISION_VP_ENABLE`

- **Type :** booléen
- **Défaut :** `false ou true`
- **Catégorie :** Alias script Darcy chiVP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyChiCollisionVpEnable`

Alias script de darcyChiCollisionVpEnable.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_COLLISION_VP_GAMMA`

- **Type :** entier/double
- **Défaut :** `-1`
- **Catégorie :** Alias script Darcy chiVP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyChiCollisionVpGamma`

Alias script de darcyChiCollisionVpGamma.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_COLLISION_VP_LAYERS`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** Alias script Darcy chiVP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyChiCollisionVpLayers`

Alias script de darcyChiCollisionVpLayers.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_COLLISION_VP_MASS`

- **Type :** double
- **Défaut :** `1.0`
- **Catégorie :** Alias script Darcy chiVP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyChiCollisionVpMass`

Alias script de darcyChiCollisionVpMass.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_COLLISION_VP_MODE`

- **Type :** chaîne
- **Défaut :** `interface_band`
- **Catégorie :** Alias script Darcy chiVP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyChiCollisionVpMode`

Alias script de darcyChiCollisionVpMode.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_COLLISION_VP_STRENGTH`

- **Type :** double
- **Défaut :** `0.25 ou 1.0`
- **Catégorie :** Alias script Darcy chiVP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyChiCollisionVpStrength`

Alias script de darcyChiCollisionVpStrength.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_COLLISION_VP_THRESHOLD`

- **Type :** double
- **Défaut :** `0.5`
- **Catégorie :** Alias script Darcy chiVP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyChiCollisionVpThreshold`

Alias script de darcyChiCollisionVpThreshold.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_FILE`

- **Type :** chemin fichier
- **Défaut :** `selon cas`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Alias externe de CHI_FILE pour fournir un champ chi sans modifier le script.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_CHI_FILE_FORMAT`

- **Type :** chaîne
- **Défaut :** `float32`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Alias externe de CHI_FILE_FORMAT.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_COST_EVERY`

- **Type :** entier
- **Défaut :** `SUMMARY_EVERY`
- **Catégorie :** Alias script Darcy diagnostics
- **Statut :** ajout/documenté 0426

Alias script de darcyCostEvery.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_INITIAL_DEACTIVATE_BELOW_CHI`

- **Type :** double
- **Défaut :** `-1 ou 0.05`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `darcyInitialDeactivateBelowChi`

Alias script de darcyInitialDeactivateBelowChi.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_Q`

- **Type :** double
- **Défaut :** `0.1`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Alias script de darcyQ.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_THREADS_PER_BLOCK`

- **Type :** entier
- **Défaut :** `256`
- **Catégorie :** Alias script Darcy CUDA
- **Statut :** ajout/documenté 0426

Alias script de darcyThreadsPerBlock.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_USOLID_X`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Alias script de darcyUSolidX.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DARCY_USOLID_Y`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Alias script Darcy
- **Statut :** ajout/documenté 0426

Alias script de darcyUSolidY.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DENSITY_RELAXATION_TIME`

- **Type :** double >0
- **Défaut :** `0.25`
- **Catégorie :** Alias runner de qualification 0493x7d/x7e
- **Statut :** historique x7d/x7e; valeur reprise dans profil x7q

Contrôle tau_rho des anciens runners de raffinement.

**Remarques.** Variable de script historique; la qualification x7i utilise X7I_Q6_GF_DENSITY_RELAXATION_TIME et le helper Q6_GF_DENSITY_RELAXATION_TIME.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7d_density_rhs_grid_refinement.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7e_x6g_x7d_validation.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d` — Constante de temps physique de restauration de densité
- `ASSOCIATED_WITH` → `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `DROP_CENTER_X`

- **Type :** double dans domaine
- **Défaut :** `centre du domaine en x`
- **Catégorie :** Alias runner — splash x9s
- **Statut :** ajout 0493x9s

Position initiale x du centre de goutte.

**Remarques.** Doit laisser une marge compatible avec le rayon et l’étalement attendu.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/generate_0493x9s_splash_state.py`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `DROP_CENTER_Y`

- **Type :** double dans domaine
- **Défaut :** `1.25 pour le domaine x9s par défaut`
- **Catégorie :** Alias runner — splash x9s
- **Statut :** ajout 0493x9s

Position initiale y du centre de goutte.

**Remarques.** Doit placer la goutte au-dessus de la cible sans intersection initiale non désirée.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/generate_0493x9s_splash_state.py`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `DROP_RADIUS_CELLS`

- **Type :** double >0
- **Défaut :** `40`
- **Catégorie :** Alias runner — splash x9s
- **Statut :** ajout 0493x9s

Rayon initial de la goutte en nombre de cellules.

**Remarques.** Avec h=1/256, le default donne R=40h.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/generate_0493x9s_splash_state.py`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `DROP_VX`

- **Type :** double
- **Défaut :** `0`
- **Catégorie :** Alias runner — splash x9s
- **Statut :** ajout 0493x9s

Vitesse initiale horizontale de la goutte.

**Remarques.** Paramètre cinématique du cas initial.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/generate_0493x9s_splash_state.py`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `DROP_VY`

- **Type :** double
- **Défaut :** `-0.35`
- **Catégorie :** Alias runner — splash x9s
- **Statut :** ajout 0493x9s

Vitesse initiale verticale de la goutte.

**Remarques.** Contrôle principalement l’inertie d’impact et le nombre de Weber du cas x9s.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/generate_0493x9s_splash_state.py`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `DUMP_ROLE_FILTER`

- **Type :** all|fluid | alias script utilisateur
- **Défaut :** `fluid dans scripts visual 0309+ | fluid dans scripts visuels 0309+`
- **Catégorie :** Alias script | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0314 | script 0314
- **Écrit / contrôle :** `dumpRoleFilter`

Alias exporté par les scripts vers dumpRoleFilter. | Alias script vers dumpRoleFilter.

**Remarques.** Paramètre de script, pas toujours une clé directe. | fluid produit des dumps compacts de visualisation; all reste restart-compatible.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `EMPTY_INITIAL_MASS`

- **Type :** double >0
- **Défaut :** `PARTICLE_MASS`
- **Catégorie :** Alias script état initial / injection empty refill 0434
- **Statut :** option locale/proposée 0434; documenté 0436

Paramètre de génération d’état initial pour tests empty/fill. | Masse utilisée par le générateur d’état initial empty selon convention de script.

**Remarques.** Option script uniquement; pas d’effet si INITIAL_DOMAIN_MODE=full. | Sans effet si INITIAL_DOMAIN_MODE=full.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0434_injection_type1_into_type2.sh`

### `EMPTY_INITIAL_SLOTS`

- **Type :** entier >=0
- **Défaut :** `gamma*Nx*Ny si vide`
- **Catégorie :** Alias script état initial / injection empty refill 0434
- **Statut :** option locale/proposée 0434; documenté 0436

Dimensionne le pool initial inactif pour un domaine initialement vide. | Dimensionne le pool de slots inactifs pour INITIAL_DOMAIN_MODE=empty.

**Remarques.** À combiner avec MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1 pour éviter de dépendre d’un realloc/scan hôte. | Utile pour ne pas dépendre de la fin du run pour diagnostiquer refill/injection.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0434_injection_type1_into_type2.sh`

### `EMPTY_INITIAL_TYPE`

- **Type :** entier type particulaire
- **Défaut :** `BACKGROUND_TYPE`
- **Catégorie :** Alias script état initial / injection empty refill 0434
- **Statut :** option locale/proposée 0434; documenté 0436

Fixe le type associé au profil initial empty quand le générateur doit matérialiser une convention de type. | Type utilisé par le générateur d’état initial empty selon convention de script.

**Remarques.** Ne doit pas être confondu avec particleTypeFilter, qui est un filtre de visualisation. | Ne filtre pas l’affichage; pour cela utiliser PARTICLE_TYPE_FILTER.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0434_injection_type1_into_type2.sh`

### `EVAPORATION_TARGET_TYPE`

- **Type :** entier
- **Défaut :** `-1 (runners x12 et SimulationParams)`
- **Catégorie :** Alias runner — interface cinétique / évaporation
- **Statut :** runner alias courant; production x12 = -1
- **Écrit / contrôle :** `phaseInterfaceEvaporationTargetType`

Surcharge phaseInterfaceEvaporationTargetType.

**Remarques.** Avec r=1 dans la chaîne x12 actuelle, aucun passage d'évaporation n'est utilisé. Si >=0 avec r>0, le type doit être enregistré, non projeté et distinct de A.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `FILTERED_RECORDING_ENABLE`

- **Type :** booléen shell | booléen/env truthy
- **Défaut :** `0 ou valeur script | 0 sauf script/profil`
- **Catégorie :** Alias script filtered recording 0434/0436
- **Statut :** documenté 0436

Active les dumps filtrés .f32 dans les scripts homogènes 0434/0436. | Alias de script pour activer les dumps filtrés 0432.

**Remarques.** Quand recordEvery<=0, la cadence suit liveEvery avec le comportement WYSIWYR 0433a. | Peut être propagé vers MPCD_FILTERED_FIELD_RECORDING_0432/SRC_FILTERED_FIELD_RECORDING_0432 selon runner.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0434_injection_type1_into_type2.sh`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`

### `GAMMA`

- **Type :** entier >0
- **Défaut :** `20`
- **Catégorie :** Validateurs CUDA resampling — population
- **Statut :** lecture C++ directe dans validateurs shadow; également variable shell courante des runners

Occupation moyenne gamma utilisée par les exécutables de validation CUDA resampling shadow.

**Remarques.** La lecture getenv directe identifiée dans le C++ est limitée aux exécutables de validation CUDA resampling shadow. Le même nom est aussi utilisé comme variable shell par de nombreux runners qui l'écrivent ensuite dans les paramètres; ne pas le confondre avec un getenv du binaire de production.

### `GAS_KBT`

- **Type :** double >0
- **Défaut :** `dépend du benchmark; Couette x14w: 0.08`
- **Catégorie :** Runner x14 — propriétés de phase
- **Statut :** paramètre visible des runners x14

Cible thermique du gaz et température de référence du mécanisme de paroi gaz; écrite dans la déclaration thermostat de l’espèce gaz.

**Remarques.** Les runners x14 utilisant l’EOS x6g alignent aussi la température globale utilisée par cette fermeture sur la cible gaz.

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `GAS_PRESSURE_CONSTANT`

- **Type :** double fini
- **Défaut :** `GAS_PRESSURE_REFERENCE`
- **Catégorie :** Alias script 0493x6g
- **Statut :** ajout runner 0493x6g

Alias du runner vers MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G.

**Remarques.** Utilisé principalement dans le test de jauge à pression uniforme.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_phase_gas_pressure.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_validation.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `GAS_PRESSURE_MODE`

- **Type :** enum string
- **Défaut :** `eos`
- **Catégorie :** Alias script 0493x6g
- **Statut :** ajout runner 0493x6g

Alias du runner vers MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G.

**Remarques.** eos pour le cas physique; constant pour validation de jauge.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_phase_gas_pressure.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `GAS_PRESSURE_REFERENCE`

- **Type :** double fini
- **Défaut :** `pression EOS uniforme initiale`
- **Catégorie :** Alias script 0493x6g
- **Statut :** ajout runner 0493x6g

Alias du runner vers MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G.

**Remarques.** Le runner calcule par défaut gamma*kBT/Acell.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_final_dam_break.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_phase_gas_pressure.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `GAS_PRESSURE_SCALE`

- **Type :** double >= 0
- **Défaut :** `1.0`
- **Catégorie :** Alias script 0493x6g
- **Statut :** ajout runner 0493x6g

Alias du runner vers MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G.

**Remarques.** 0 active le null-path de validation; 1 mode nominal.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_phase_gas_pressure.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_validation.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `GRID_CASES`

- **Type :** liste/chaîne de cas
- **Défaut :** `défini par le validateur`
- **Catégorie :** Validateurs CUDA resampling — entrée de test
- **Statut :** présent code; ajouté consolidation 0493w8

Sélectionne les cas de grille exécutés par plusieurs binaires de validation du resampling CUDA.

**Remarques.** Variable de validateur, pas une option du solveur de production et ne se place pas dans params.kv.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_guard_0227.cpp`
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_particle_select_0232.cpp`
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_plan_0228.cpp`
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_shadow_transfer_0233.cpp`

### `INACTIVE_SLOTS`

- **Type :** entier | alias script utilisateur
- **Défaut :** `50k-120k selon cas; pas de défaut universel | selon script; éviter les millions`
- **Catégorie :** Capacité particulaire | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** consolidé 0311-0312 | script/demo/audit
- **Écrit / contrôle :** `dumpRoleFilter`

Nombre de slots Inactive préalloués par les générateurs/scripts. | Nombre de slots Inactive préalloués dans les scripts et audits.

**Remarques.** La réserve peut être grande sans être écrite dans les dumps si dumpRoleFilter=fluid. | N’est pas une clé params.kv directe universelle; transmis par les générateurs d’état/scripts.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `INACTIVE_SLOTS_RESAMPLING`

- **Type :** entier
- **Défaut :** `750000 pour certains scripts`
- **Catégorie :** Alias script livevis/benchmark
- **Statut :** confirmé 0337

Nombre de slots inactifs pour les cas resampling.

**Remarques.** N’affecte pas le SRC classic si RUN_MODES=classic; utile pour réservoir resampling.

### `INITIAL_DOMAIN_MODE`

- **Type :** full | empty | empty|full
- **Défaut :** `full | empty dans le runner partagé; full dans le wrapper biphasique`
- **Catégorie :** Alias script état initial / injection empty refill 0434 | Alias runner / injection multi-espèces
- **Statut :** option locale/proposée 0434; documenté 0436 | ajout/normalisé 0493w4–0493w8

Permet de démarrer un cas injection/fill avec domaine initialement vide pour tester le remplissage par réservoir/inlet. | Choisit un domaine initialement vide avec pool ou rempli par l’espèce de fond. | Choisit entre domaine initial rempli et domaine initial vide pour tests injection/fill.

**Remarques.** Option de script, non paramètre solveur. À garder séparée des validations strictes si le script n’est pas intégré/commité. | Variable de script uniquement; ne pas interpréter comme paramètre solveur générique tant que le script n’est pas stabilisé/commité.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0434_injection_type1_into_type2.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `INJECT_MASS_CLOSURE_STRENGTH`

- **Type :** double
- **Défaut :** `1.0 pour liquid; 0.0 pour gas`
- **Catégorie :** Alias runner / injection multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8

Définit massClosureStrengthDeclared de l’espèce injectée.

**Remarques.** Concerne le resampling; sans effet si resampling désactivé.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `INJECT_PHASE`

- **Type :** liquid|gas
- **Défaut :** `liquid pour le wrapper type1_into_type2`
- **Catégorie :** Alias runner / injection multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8

Sélectionne la famille physique et les défauts Q6/fermeture de l’espèce injectée.

**Remarques.** Indépendant de l’identifiant numérique INJECT_TYPE.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `INJECT_Q6_STRENGTH`

- **Type :** double
- **Défaut :** `1.0 pour liquid; 0.0 pour gas`
- **Catégorie :** Alias runner / injection multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8

Définit q6StrengthDeclared de l’espèce injectée.

**Remarques.** En independent_masked, zéro garantit aucune correction directe.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `INJECT_TO_BACKGROUND_MASS_RATIO`

- **Type :** double >0
- **Défaut :** `100 liquid->gas; 0.01 gas->liquid; 10 sinon`
- **Catégorie :** Alias runner / injection multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8

Fixe le rapport de masses particulaires injectée/fond et les masses cellulaires de référence dérivées.

**Remarques.** Ne pas confondre avec la fraction volumique; le masque Q6 utilise mass/referenceCellMass.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `INLET_FACE`

- **Type :** double/chaîne selon variable
- **Défaut :** `left`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Face portant le segment inlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `INLET_SMAX`

- **Type :** double/chaîne selon variable
- **Défaut :** `1.0`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Coordonnée relative maximale du segment inlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `INLET_SMIN`

- **Type :** double/chaîne selon variable
- **Défaut :** `STEP_YMAX/Ly`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Coordonnée relative minimale du segment inlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `INPUT_STATE`

- **Type :** chemin fichier
- **Défaut :** `selon cas`
- **Catégorie :** Alias script état initial
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `inputState`

Alias de STATE_SOURCE pour fournir l’état initial .smpcd.

**Remarques.** Utilisé dans les scripts 0411/0414/0416.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `KINETIC_REFLECTION_FRACTION`

- **Type :** double [0,1]
- **Défaut :** `1.0 dans runners x12 de production; défaut SimulationParams=0.0`
- **Catégorie :** Alias runner — interface cinétique / évaporation
- **Statut :** runner alias courant; production x12 = 1.0
- **Écrit / contrôle :** `phaseInterfaceKineticReflectionFraction`, `q6ForceProjectionMode`, `speciesQ6Mode`

Surcharge phaseInterfaceKineticReflectionFraction.

**Remarques.** Avec r>0, la validation Params impose speciesQ6Mode=free_surface_masked, q6ForceProjectionMode=prestream_single_fused, B=vacuum et exactement une espèce A projetée. x10o n'est actif que pour r>=1; r<1 bascule sur le chemin cinétique historique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `LIQUID_KBT`

- **Type :** double >0
- **Défaut :** `dépend du benchmark; Couette x14w: 0.02`
- **Catégorie :** Runner x14 — propriétés de phase
- **Statut :** paramètre visible des runners x14

Cible thermique de la phase liquide; écrite dans species0ThermostatTargetKBT selon le mapping de types.

**Remarques.** Alias runner, non lu directement par le C++.

### `LIVE_PROGRESS`

- **Type :** booléen/int | booléen
- **Défaut :** `1`
- **Catégorie :** Alias runner / ergonomie | Runner qualification 0493x7i / progression
- **Statut :** ajout/normalisé 0493w4–0493w8 | profil final x7q/x7i

Active l’affichage d’avancement des runs lorsque le runner commun le permet. | Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Modalité de travail recommandée pour les campagnes longues. | Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `LIVE_VIS_ALPHA`

- **Type :** double
- **Défaut :** `0.08`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337 | précisé 0436b

Lissage temporel visuel.

**Remarques.** Principalement utile au fallback CPU. | 0436b: alpha est une persistance temporelle de displayScalar indépendante de smoothPasses; un changement de field ou particleTypeFilter force un reset d’une frame si le correctif 0436b est appliqué.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `LIVE_VIS_CLIP`

- **Type :** double; <=0 auto
- **Défaut :** `-1`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Échelle de saturation couleur.

**Remarques.** Exemples: ux clip 0.2–0.5; vorticity clip 5–20 selon cas. | 0341b/0341d: sert aussi à initialiser le fichier livevis_control.kv généré par les scripts.

### `LIVE_VIS_COLORMAP`

- **Type :** enum: blue_red | gray | thermal
- **Défaut :** `blue_red`
- **Catégorie :** Alias script livevis colormap
- **Statut :** ajout 0342a

Colormap initial exporté en SRC_LIVE_VIS_COLORMAP et écrit dans le fichier livevis_control.kv créé par les scripts.

**Remarques.** Peut ensuite être changé à chaud via la clé colormap du fichier de contrôle.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_colormap_control_0342a.md`

### `LIVE_VIS_CONTROL_BASENAME`

- **Type :** nom de fichier
- **Défaut :** `livevis_control.kv`
- **Catégorie :** Alias script livevis runtime control
- **Statut :** ajout 0341d

Nom du fichier utilisé avec LIVE_VIS_CONTROL_DIR ou, par défaut, dans le run_root.

**Remarques.** Permet de distinguer plusieurs contrôles, par exemple vk_io.kv, tg_hole.kv, poiseuille.kv.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341b_scripts.md`

### `LIVE_VIS_CONTROL_DIR`

- **Type :** chemin répertoire
- **Défaut :** `vide`
- **Catégorie :** Alias script livevis runtime control
- **Statut :** ajout 0341d

Répertoire dans lequel créer le fichier de contrôle lorsque LIVE_VIS_CONTROL_FILE est vide.

**Remarques.** Combiné avec LIVE_VIS_CONTROL_BASENAME. Exemple: LIVE_VIS_CONTROL_DIR=. LIVE_VIS_CONTROL_BASENAME=livevis_control.kv.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341b_scripts.md`

### `LIVE_VIS_CONTROL_ENABLE`

- **Type :** booléen shell
- **Défaut :** `1`
- **Catégorie :** Alias script livevis runtime control
- **Statut :** ajout 0341b; export explicite 0341c

Active la création/export du fichier de contrôle livevis dans les scripts portables.

**Remarques.** À 0, aucun fichier de contrôle n’est préparé et SRC_LIVE_VIS_CONTROL_FILE peut rester vide.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341b_scripts.md`

### `LIVE_VIS_CONTROL_EVERY`

- **Type :** entier >= 1
- **Défaut :** `1`
- **Catégorie :** Alias script livevis runtime control
- **Statut :** ajout 0341b; export explicite 0341c

Valeur script exportée en SRC_LIVE_VIS_CONTROL_EVERY.

**Remarques.** Contrôle la fréquence de relecture côté binaire.

### `LIVE_VIS_CONTROL_FILE`

- **Type :** chemin fichier .kv
- **Défaut :** `vide`
- **Catégorie :** Alias script livevis runtime control
- **Statut :** ajout 0341b; clarifié 0341d

Chemin explicite du fichier de contrôle livevis. Prioritaire sur LIVE_VIS_CONTROL_DIR et le chemin par défaut run_root.

**Remarques.** Utiliser ce paramètre, et non LIVE_VIS_CONTROL_FILE_EFFECTIVE, pour imposer un fichier tel que ./livevis_control.kv. Recommandé si CLEAN_RUN_ROOT=1 et que l’on veut un fichier persistant hors run_root.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341b_scripts.md`

### `LIVE_VIS_CONTROL_FILE_EFFECTIVE`

- **Type :** chemin fichier .kv résolu
- **Défaut :** `résolu automatiquement`
- **Catégorie :** Alias script livevis runtime control interne
- **Statut :** ajout 0341b; export explicite 0341c; clarifié 0341d

Chemin effectivement transmis au binaire via SRC_LIVE_VIS_CONTROL_FILE.

**Remarques.** Variable interne/résolue: ne pas la fixer manuellement. Ordre de résolution 0341d: LIVE_VIS_CONTROL_FILE, sinon LIVE_VIS_CONTROL_DIR+LIVE_VIS_CONTROL_BASENAME, sinon run_root/LIVE_VIS_CONTROL_BASENAME.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341b_scripts.md`

### `LIVE_VIS_CONTROL_LOG`

- **Type :** booléen shell
- **Défaut :** `1`
- **Catégorie :** Alias script livevis runtime control
- **Statut :** ajout 0341b; export explicite 0341c

Valeur script exportée en SRC_LIVE_VIS_CONTROL_LOG.

**Remarques.** Les logs livevis sont dans le .time car le stderr du binaire y est redirigé par le script.

### `LIVE_VIS_CUDA_FIELD`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337a

Active le renderer CUDA de champ.

**Remarques.** Mode recommandé par défaut pour classic et resampling livevis. | 0339a: Défaut conservé : renderer CUDA field actif.

### `LIVE_VIS_CUDA_SNAPSHOT`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0336/0337

Active le snapshot compact expérimental.

**Remarques.** Non fiable après resampling; garder à 0 sauf diagnostic.

### `LIVE_VIS_ENABLE`

- **Type :** booléen | booléen/int 0|1
- **Défaut :** `1 | 0 dans le runner final x6g`
- **Catégorie :** Alias script livevis 0337 | Alias script LiveVis / runners 0493x
- **Statut :** ajout 0337 | documenté/fix runner 0493x6g-fix3

Active la visualisation dans les scripts portables livevis. | Contrôle l’activation de la fenêtre LiveVis au niveau des runners 0493x.

**Remarques.** Exporté vers SRC_LIVE_VIS_ENABLE. Mettre 0 pour exécuter sans fenêtre. | 0493x6g-fix3 corrige le runner final pour respecter la valeur fournie par l’appelant au lieu de forcer 0.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_final_dam_break.sh`

### `LIVE_VIS_EVERY`

- **Type :** entier >0
- **Défaut :** `25 | 20`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337 | mis à jour 0339a | mis à jour 0433a

Cadence de visualisation live : une frame toutes les N étapes. | Depuis 0433a, cette cadence est aussi la valeur suivie par recordEvery quand recordEvery est absent ou <=0. | Cadence de rendu livevis.

**Remarques.** Exporté vers SRC_LIVE_VIS_EVERY. | 0339a: défaut réduit à 25 pour limiter le coût livevis; mesures indicatives 500 steps: every1≈45.4s, every25≈32.8–38.7s selon bruit. Override possible par environnement. | 0433a: initialise SRC_LIVE_VIS_EVERY au démarrage; peut ensuite être remplacé à chaud par livevis_control.kv:liveEvery/every/visualEvery.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `LIVE_VIS_FIELD`

- **Type :** ux|uy|speed|vorticity|mass|density
- **Défaut :** `dépend du script`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Champ affiché par défaut dans la fenêtre live.

**Remarques.** Par défaut: VK/TG=vorticity, Poiseuille=ux, backward-step/box=speed. | 0341b/0341d: sert aussi à initialiser le fichier livevis_control.kv généré par les scripts.

### `LIVE_VIS_FORCE_HOST_MIRROR`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0335c

Force le miroir hôte pour visualisation.

**Remarques.** Debug seulement. | 0339a: Défaut conservé : éviter le host mirror forcé livevis.

### `LIVE_VIS_GAIN`

- **Type :** double >0
- **Défaut :** `1.0`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Gain couleur.

**Remarques.** Réduire si la colormap est saturée; augmenter si le contraste est faible. | 0341b/0341d: sert aussi à initialiser le fichier livevis_control.kv généré par les scripts.

### `LIVE_VIS_HOLD_ON_EXIT`

- **Type :** booléen | booléen/int 0|1
- **Défaut :** `1 | 0 dans le runner final x6g`
- **Catégorie :** Alias script livevis | Alias script LiveVis / runners 0493x
- **Statut :** ajout/documenté 0426 | documenté/fix runner 0493x6g-fix3

Alias script exporté vers SRC_LIVE_VIS_HOLD_ON_EXIT. | Demande de conserver la fenêtre LiveVis ouverte à la fin du run.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement. | À utiliser avec LIVE_VIS_ENABLE=1. En runner apparié, RUN_ZERO_REFERENCE=0 évite de bloquer après la référence. 0493x6g-fix3 respecte désormais cette valeur.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_final_dam_break.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `LIVE_VIS_LOG_SOURCE`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337d | mis à jour 0339a

Contrôle le log de source/fallback livevis. | Affiche le statut source livevis sur une ligne.

**Remarques.** Exporté vers SRC_LIVE_VIS_LOG_SOURCE; depuis 0337d ne spamme plus le terminal. | 0339a: défaut réduit à 0 pour éviter le bruit de logs; remettre à 1 pour debug.

### `LIVE_VIS_NX`

- **Type :** entier
- **Défaut :** `300`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Résolution x du champ livevis.

**Remarques.** Exporté vers SRC_LIVE_VIS_NX.

### `LIVE_VIS_NY`

- **Type :** entier
- **Défaut :** `80`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Résolution y du champ livevis.

**Remarques.** Exporté vers SRC_LIVE_VIS_NY.

### `LIVE_VIS_QUANTILE`

- **Type :** double dans (0,1]
- **Défaut :** `0.995`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Quantile auto de mise à l’échelle.

**Remarques.** Limiter les outliers dans le fallback CPU.

### `LIVE_VIS_QUIVER_MIN_SPEED`

- **Type :** double >= 0
- **Défaut :** `0`
- **Catégorie :** Alias script livevis quiver
- **Statut :** ajout 0364

Alias script exportable vers SRC_LIVE_VIS_QUIVER_MIN_SPEED.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `LIVE_VIS_QUIVER_NX`

- **Type :** entier >= 1
- **Défaut :** `60`
- **Catégorie :** Alias script livevis quiver
- **Statut :** ajout 0364

Alias script exportable vers SRC_LIVE_VIS_QUIVER_NX.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `LIVE_VIS_QUIVER_NY`

- **Type :** entier >= 1
- **Défaut :** `32`
- **Catégorie :** Alias script livevis quiver
- **Statut :** ajout 0364

Alias script exportable vers SRC_LIVE_VIS_QUIVER_NY.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `LIVE_VIS_QUIVER_SCALE`

- **Type :** double
- **Défaut :** `-1`
- **Catégorie :** Alias script livevis quiver
- **Statut :** ajout 0364

Alias script exportable vers SRC_LIVE_VIS_QUIVER_SCALE.

**Remarques.** <0 désactive l’overlay.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `LIVE_VIS_QUIVER_SMOOTH_PASSES`

- **Type :** entier; -1 ou >=0
- **Défaut :** `-1`
- **Catégorie :** Alias script livevis quiver
- **Statut :** ajout 0365

Alias script exportable vers SRC_LIVE_VIS_QUIVER_SMOOTH_PASSES.

**Remarques.** <0 réutilise smoothPasses.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `LIVE_VIS_RESAMPLING_HOST_MIRROR`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0335d/0337

Force le fallback hôte en resampling.

**Remarques.** Fiable mais lent; garder à 0 avec CUDA_FIELD=1. | 0339a: Défaut conservé : éviter le host mirror resampling livevis.

### `LIVE_VIS_SMOOTH_PASSES`

- **Type :** entier >=0
- **Défaut :** `1`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Lissage spatial du rendu.

**Remarques.** Vorticity utilise souvent 1–2 passes. | 0341b/0341d: sert aussi à initialiser le fichier livevis_control.kv généré par les scripts.

### `LIVE_VIS_VSYNC`

- **Type :** booléen/int
- **Défaut :** `0`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Vsync GLFW.

**Remarques.** 0 recommandé pour ne pas brider le calcul.

### `LIVE_VIS_WINDOW_SCALE`

- **Type :** entier >=1
- **Défaut :** `1`
- **Catégorie :** Alias script livevis 0337
- **Statut :** ajout 0337

Facteur d’échelle de la fenêtre.

**Remarques.** N’affecte pas la simulation.

### `MPCD_BACKEND`

- **Type :** string
- **Défaut :** `cuda dans scripts/run_src_mpcd_cuda_primary_0275.sh; openmp si demandé explicitement`
- **Catégorie :** Backend principal
- **Statut :** principal utilisateur

Choisit le lanceur primaire cuda/openmp.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0275_CUDA_PRIMARY_BACKEND.md`

### `MPCD_CUDA_ACTIVE_PREFIX_ASSUME_NO_HOST_CONSUMERS_0315D`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315d)

Déclare qu’aucun consommateur hôte n’exige l’état complet; option experte potentiellement unsafe.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_ACTIVE_PREFIX_COMPACT_FULLSCAN_0315C`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315c)

Force une validation exhaustive ou un scan complet de l’active-prefix/roles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_COMPACT_FULLSCAN_0315K`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315k)

Force une validation exhaustive ou un scan complet de l’active-prefix/roles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_COMPACT_THREADS_0315C`

- **Type :** entier
- **Défaut :** `256`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315c)

Règle le nombre de threads CUDA par bloc du noyau associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_EAGER_HOST_MIRROR_0315D`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315d)

Force une synchronisation ou un miroir hôte complet, principalement pour compatibilité et audit.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_HOST_FULL_VALIDATE_0315H`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315h)

Force une validation exhaustive ou un scan complet de l’active-prefix/roles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_particle_state.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_HOST_TAIL_FULL_REPAIR_0315H`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315h)

Variable runtime interne contrôlant le chemin nommé dans le backend CUDA.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_particle_state.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_STRICT_EXPECTED_0315C`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315c)

Force une validation exhaustive ou un scan complet de l’active-prefix/roles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_ALL_FULL_VALIDATE_0315J`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315j)

Force une validation exhaustive ou un scan complet de l’active-prefix/roles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_particle_state.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_ALL_LEGACY_0315J`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315j)

Réactive le comportement historique complet pour non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_particle_state.cu`

### `MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315k)

Force une synchronisation ou un miroir hôte complet, principalement pour compatibilité et audit.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_particle_state.cu`

### `MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_CELL_MOMENTS_PERSISTENT_STATE_0251`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0251.md`

### `MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_CELL_MOMENTS_SHADOW`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_CELL_MOMENTS_SHADOW_EVERY`

- **Type :** entier
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_CELL_MOMENTS_SHADOW_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_CELL_MOMENTS_SHADOW_TOL`

- **Type :** double
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_CELL_MOMENTS_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0250.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0251.md`

### `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** validé 0286

Active le chemin résident inlet/outlet full-face SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0263D_INACTIVE_RESERVOIR_FIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0263_IO_FULLFACE_RESIDENT.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0268_IO_FULLFACE_RESERVOIR_POOL.md`

### `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** validé 0286

Active le chemin résident inlet/outlet full-face SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** validé 0286

Active le chemin résident inlet/outlet full-face SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_BOUNDARY_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** Autres variables internes
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0267_IO_RESIDENT_BOUNDARY_PARALLEL.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** Autres variables internes
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0267_IO_RESIDENT_BOUNDARY_PARALLEL.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0268_IO_FULLFACE_RESERVOIR_POOL.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0269A_IO_SEGMENTED_RESERVOIR_POOL.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_DISABLE_POOL`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0268_IO_FULLFACE_RESERVOIR_POOL.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0269A_IO_SEGMENTED_RESERVOIR_POOL.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_INSERT_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0268_IO_FULLFACE_RESERVOIR_POOL.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_POOL_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0268_IO_FULLFACE_RESERVOIR_POOL.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_DISABLE_SEGMENTED_POOL`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0269A_IO_SEGMENTED_RESERVOIR_POOL.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_POOL_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_SEGMENTED_INSERT_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0291_FORCED_OUTLET_THREADS`

- **Type :** entier
- **Défaut :** `256`
- **Catégorie :** CUDA SRC classic — inlet/outlet
- **Statut :** présent état 36abd23; inventorié 0490p (0291)

Règle le nombre de threads CUDA par bloc du noyau associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** validé 0286

Active le chemin résident inlet/outlet segmenté SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0264_IO_SEGMENTED_RESIDENT.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280B_CUDA_THERMOSTAT_IO_SEGMENTED_RUNNERFIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280_CUDA_THERMOSTAT_IO_SEGMENTED.md`

### `MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** validé 0286

Active le chemin résident inlet/outlet segmenté SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0264_IO_SEGMENTED_RESIDENT.md`

### `MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** validé 0286

Active le chemin résident inlet/outlet segmenté SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260`

- **Type :** booléen/env truthy
- **Défaut :** `false/off sauf scripts CUDA`
- **Catégorie :** SRC classic CUDA résident
- **Statut :** validé 0286 | existant; confirmé 0334a

Active le chemin classic SRC CUDA résident périodique.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | Depuis 0334a, il peut rester compatible avec immersed circle; ne doit pas forcer un fallback CPU en présence d’un cylindre.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0260.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0262_RESIDENTFIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_full_periodic_circle_resident_0334a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_periodic_0245.cu`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** Autres variables internes
- **Statut :** réglage performance/interne | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0271_WALL_PERIODIC_FIXED_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_DISABLE_ASYNC_STREAM`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Autres variables internes
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0271_WALL_PERIODIC_FIXED_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_periodic_0245.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_wall_simple_0246.cu`

### `MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** Autres variables internes
- **Statut :** validé 0286

Active le chemin résident solide/rectangle SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0262.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0262_RESIDENTFIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0262_STREAMFIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0277_CUDA_THERMOSTAT_SOLID_RECTANGLE.md`

### `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Sécurité VK / chemin wall+circle résident
- **Statut :** existant 0318; quarantainé 0331

Demande l’ancien chemin résident combiné wall+circle 0318.

**Remarques.** Chemin conservé uniquement pour diagnostic; ne s’active plus sans le garde UNSAFE. Le chemin validé par défaut utilise le resident classic safe/no0318. | 0338c: le chemin performant validé est 0318 + MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_MINIMAL_DOWNLOAD_0338=1; 0318 seul reste à traiter comme chemin historique/quarantainé selon scripts.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_wall_simple_0246.cu`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318_UNSAFE_ENABLE`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Sécurité VK / chemin wall+circle résident
- **Statut :** ajout 0331

Garde explicite pour autoriser le chemin 0318 unsafe.

**Remarques.** Doit rester à 0 pour les runs de production/validation. À 1 seulement pour reproduire l’ancien chemin fautif ou diagnostiquer.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_DISABLE_MINIMAL_DOWNLOAD_0338`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA sécurité / wall+circle resident 0318
- **Statut :** ajout 0338c; debug/rollback

Désactive explicitement le pont minimal-download 0338 même si le flag d’activation est présent.

**Remarques.** Garde-fou pour comparaison flag ON/OFF et rollback rapide.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_MINIMAL_DOWNLOAD_0338`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA performance / wall+circle resident 0318
- **Statut :** ajout 0338c; opt-in; validé classic wall+circle non-VIZ et VIZ

Active le pont 0338 pour le chemin wall+circle résident 0318 : immersed_circle reconnaît 0318 comme résident, supprime le download cercle et autorise src_collision à consommer l’état partagé CUDA 0251 frais.

**Remarques.** À activer avec MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=1 pour le cas classic wall+circle validé. Ne pas généraliser sans validation Q6/resampling/viriel; préserver les miroirs host lorsque ces voies hybrides sont actives.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/host_device_authority_0340.md`
- `DEFINED_OR_USED_IN` — `src/cuda_immersed_circle_0284.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — wall-simple
- **Statut :** validé 0286

Active le chemin résident wall-simple SRC classic CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0261.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0262_RESIDENTFIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0270_WALL_RESIDENT_BOUNDARY_SKIP.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`

### `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0270_DISABLE_BOUNDARY_SKIP`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA SRC classic — wall-simple
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0270_WALL_RESIDENT_BOUNDARY_SKIP.md`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_DISABLE_FAST_DIAGNOSTICS`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA SRC classic — wall-simple
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0271_WALL_PERIODIC_FIXED_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_wall_simple_0246.cu`

### `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — wall-simple
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0271_WALL_PERIODIC_FIXED_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`

### `MPCD_CUDA_COLLISION_WRAPPER_HOST_SYNC_0315F`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315f)

Force une synchronisation ou un miroir hôte complet, principalement pour compatibilité et audit.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_DARCY_BRINKMAN_LOG_0343`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Darcy–Brinkman
- **Statut :** présent état 36abd23; inventorié 0490p (0343)

Contrôle un diagnostic ou journal runtime du composant associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_darcy_brinkman_0343.cu`

### `MPCD_CUDA_IMMERSED_CIRCLE_0284`

- **Type :** booléen/env truthy
- **Défaut :** `false/off sauf scripts VK`
- **Catégorie :** Obstacle immersed circle CUDA
- **Statut :** validé 0286 | confirmé 0334a

Active le traitement CUDA du cylindre immergé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0334a : peut consommer l’état CUDA résident partagé et éviter les upload/download particulaires à chaque step.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_full_periodic_circle_resident_0334a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_immersed_circle_0284.cu`

### `MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Obstacle immersed circle CUDA
- **Statut :** validé 0286 | existant; à éviter en production

Force un téléchargement complet après le cylindre 0284.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | Très coûteux; utile seulement pour diagnostic comparatif. Incompatible avec l’objectif chemin résident.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_immersed_circle_0284.cu`

### `MPCD_CUDA_IMMERSED_CIRCLE_0284_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA solide immergé — cercle
- **Statut :** validé 0286

Active/paramètre le support CUDA du cercle solide 0284.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_immersed_circle_0284.cu`

### `MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Diagnostics rapides immersed circle CUDA
- **Statut :** ajout 0330/0331

Active un retour diagnostic plus léger pour le cylindre CUDA.

**Remarques.** N’affecte pas la physique; seulement les compteurs/diagnostics. Utile pour benchmark mais à désactiver pour oracle hits complets.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_immersed_circle_0284.cu`

### `MPCD_CUDA_IMMERSED_RECTANGLE_0247`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA solide immergé — rectangle
- **Statut :** interne/runtime

Active/paramètre le support CUDA rectangle/step.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0247A.md`

### `MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA solide immergé — rectangle
- **Statut :** réglage performance/interne

Active/paramètre le support CUDA rectangle/step.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0262.md`

### `MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA solide immergé — rectangle
- **Statut :** réglage performance/interne

Active/paramètre le support CUDA rectangle/step.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0247A.md`

### `MPCD_CUDA_INACTIVE_TAIL_POOL_0313`

- **Type :** booléen/env truthy
- **Défaut :** `true/on`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0313

Active le fast path de collecte de slots inactifs en queue de tableau.

**Remarques.** Fallback exact conservé par défaut si la fenêtre ne suffit pas.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_INACTIVE_TAIL_POOL_MAX_SCAN_0313`

- **Type :** entier
- **Défaut :** `262144`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0313

Taille maximale de fenêtre scannée dans la queue inactive.

**Remarques.** Borne le coût du fast path avant fallback.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_INACTIVE_TAIL_POOL_MIN_SCAN_0313`

- **Type :** entier
- **Défaut :** `8192`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0313

Taille minimale de fenêtre scannée dans la queue inactive.

**Remarques.** Paramètre de performance; ne change pas la physique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_INACTIVE_TAIL_POOL_NO_FALLBACK_0313`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0313

Désactive le fallback complet si activé.

**Remarques.** À réserver aux audits; le nominal garde le fallback exact.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_INACTIVE_TAIL_POOL_SCAN_MULT_0313`

- **Type :** réel/entier
- **Défaut :** `4`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0313

Facteur multiplicatif entre besoin estimé de slots et fenêtre scannée.

**Remarques.** Augmenter si le fallback complet se déclenche trop souvent.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0249A.md`

### `MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA moments/workspace cellule
- **Statut :** interne/runtime | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** Autres variables internes
- **Statut :** interne/runtime | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_PARTICLE_STATE_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA état particulaire persistant
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA état particulaire persistant
- **Statut :** interne/runtime | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** interne/runtime | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0272_COLLISION_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_DEVICE_ROTATION_0272`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0272_COLLISION_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_EXPLICIT_GAMMA_ROLE_FASTPATH_0273`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0273_COLLISION_WRAPPER_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FAST_THERMOSTAT_DIAG_0321`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0321)

Désactive explicitement l’optimisation ou le diagnostic nommé pour audit/non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FUSED_STREAM_DEPOSIT_0274`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0275_CUDA_PRIMARY_BACKEND.md`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_KERNEL_BREAKDOWN_0324`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0324)

Désactive explicitement l’optimisation ou le diagnostic nommé pour audit/non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_KERNEL_BREAKDOWN_APPEND_0328`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0328)

Désactive explicitement l’optimisation ou le diagnostic nommé pour audit/non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_LAZY_KERNEL_CHECK_0273`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0273_COLLISION_WRAPPER_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_FINAL_SYNC_0272`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0272_COLLISION_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_HOST_CELLID_FILL_0327`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0327)

Désactive explicitement l’optimisation ou le diagnostic nommé pour audit/non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_SETUP_SYNC_0273`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0273_COLLISION_WRAPPER_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_WORKSPACE_DOWNLOAD_0272`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0272_COLLISION_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321`

- **Type :** booléen/env truthy
- **Défaut :** `1`
- **Catégorie :** CUDA collision SRC résidente — diagnostic thermostat
- **Statut :** ajout 0321; propagé Darcy 0426

Utilise le diagnostic thermostat rapide dans le chemin collision/thermostat résident.

**Remarques.** Propagé aux scripts Darcy 0426 ; son absence contribuait au chemin lent observé dans les runs segmentés.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** interne/runtime | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA solide immergé — cercle
- **Statut :** validé 0286

Active/paramètre le support CUDA du cercle solide 0284.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0284_CUDA_IMMERSED_CIRCLE_PERIODIC.md`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA solide immergé — rectangle
- **Statut :** interne/runtime

Active/paramètre le support CUDA rectangle/step.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0254.md`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0324)

Active ou règle le profilage détaillé des noyaux collision/thermostat.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324_FILE`

- **Type :** chaîne/chemin
- **Défaut :** `cuda_persistent_kernel_breakdown_0324.csv`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0324)

Définit le chemin du fichier de diagnostic associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_APPEND_0328`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0328)

Active ou règle le profilage détaillé des noyaux collision/thermostat.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0273_COLLISION_WRAPPER_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0257.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0261.md`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — piston/mobile wall
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0255.md`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251`

- **Type :** booléen/env truthy
- **Défaut :** `false/off sauf chemin résident`
- **Catégorie :** État particulaire CUDA partagé
- **Statut :** interne/runtime | existant; réutilisé 0334/0337

Active/réutilise l’état particulaire CUDA partagé pour les étapes SRC résidentes.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | Base du chemin resident et du live renderer CUDA; la fraîcheur après resampling doit être traitée avec prudence. | 0338c: pour wall+circle 0318 + minimal-download, src_collision peut autoriser le pont shared-state/thermostat 0251 afin de consommer l’état GPU frais produit par immersed_circle, sans ré-upload particulaire privé.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0252.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0261.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280B_CUDA_THERMOSTAT_IO_SEGMENTED_RUNNERFIX.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_shared_particle_state_0251.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0252.md`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0272_COLLISION_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327`

- **Type :** booléen/env truthy
- **Défaut :** `1`
- **Catégorie :** CUDA collision SRC résidente — réduction transferts hôte
- **Statut :** ajout 0327; propagé Darcy 0426

Évite le remplissage hôte des cell-id lorsque le chemin résident peut réutiliser les métadonnées.

**Remarques.** Fastflag 0426 pour scripts Darcy ; réduire upload/setup dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0273_COLLISION_WRAPPER_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319`

- **Type :** booléen/env truthy
- **Défaut :** `1`
- **Catégorie :** CUDA collision SRC résidente — diagnostic wallVP
- **Statut :** ajout 0319; propagé Darcy 0426

Désactive le diagnostic wallVP coûteux dans les chemins où il n’est pas requis.

**Remarques.** Fastflag 0426 pour scripts Darcy ; utile pour éviter le bloc géométrique/VP inutile pendant les démos Darcy.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne | propagé scripts Darcy 0426

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0272B_COLLISION_CELLCOUNT_FIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0272_COLLISION_OVERHEAD.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0274_FUSED_STREAM_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0252.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280B_CUDA_THERMOSTAT_IO_SEGMENTED_RUNNERFIX.md`

### `MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0253.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280B_CUDA_THERMOSTAT_IO_SEGMENTED_RUNNERFIX.md`

### `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_DISABLE_SKIP_VELOCITY_DOWNLOAD_0315F`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA collision SRC — profilage et synchronisation
- **Statut :** présent état 36abd23; inventorié 0490p (0315f)

Désactive explicitement l’optimisation ou le diagnostic nommé pour audit/non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_persistent_mpcd_step.cu`

### `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** validé 0286
- **Écrit / contrôle :** `thermostatEnable`

Consomme l’état particulaire partagé pour le thermostat fusionné.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. 0291b: ce flag choisit seulement le backend/chemin CUDA; thermostatEnable=false dans params.kv désactive physiquement le thermostat même si ce flag vaut 1.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0260.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280B_CUDA_THERMOSTAT_IO_SEGMENTED_RUNNERFIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280_CUDA_THERMOSTAT_IO_SEGMENTED.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291B_THERMOSTAT_ENABLE_GATE.md`

### `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA thermostat
- **Statut :** validé 0286

Consomme l’état particulaire partagé pour le thermostat fusionné.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** validé 0286
- **Écrit / contrôle :** `thermostatEnable`

Active le thermostat CUDA persistant/fusionné selon le chemin.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. 0291b: ce flag choisit seulement le backend/chemin CUDA; thermostatEnable=false dans params.kv désactive physiquement le thermostat même si ce flag vaut 1.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0278_CUDA_THERMOSTAT_PISTON.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280B_CUDA_THERMOSTAT_IO_SEGMENTED_RUNNERFIX.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0280C_CUDA_THERMOSTAT_IO_RESIDENT_SUPPORT.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291B_THERMOSTAT_ENABLE_GATE.md`

### `MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** Autres variables internes
- **Statut :** réglage performance/interne | propagé scripts Darcy 0426

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_CUDA_PRIMARY_KEEP_TEMP`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** Backend principal
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0275_CUDA_PRIMARY_BACKEND.md`

### `MPCD_CUDA_PRIMARY_VERBOSE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** Backend principal
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0275_CUDA_PRIMARY_BACKEND.md`

### `MPCD_CUDA_Q6_DEBUG_SYNC`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_DEVICE_SCALAR_CG`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_DISABLE_PLAN_CACHE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_HOST_BLOCK_SUM`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_LEGACY_HOST_SCALAR_CG`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_LEGACY_MEAN_REMOVAL_RESIDUAL_NORM`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_RESIDENT_0400`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0400)
- **Écrit / contrôle :** `projectionBackend`, `projectionEnable`, `speciesQ6Mode`

Active le backend Q6 CUDA résident lorsque projectionEnable=true et projectionBackend=cuda.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b. | 0493w7: le mode speciesQ6Mode=independent_masked réutilise ce chemin Q6 résident; aucun nouvel env flag Q6 spécifique n’est requis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407`

- **Type :** booléen/auto
- **Défaut :** `auto backend; x7i: 1 Q6 legacy petits cas, 0 Q6-g-f et grand IO`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent; politique de qualification précisée 0493x7q/x7i

Force ou interdit le solveur CG mono-bloc 0407. Dans la campagne finale, Q6-g-f le désactive pour utiliser x7j coopératif; Q6 legacy le garde sur les domaines <=65536 cellules.

**Remarques.** Gate d’exécution uniquement. x7i choisit le réglage par mode afin de ne pas pénaliser la référence src-q6; same-face IO 300x300 utilise 0 côté legacy en raison de la taille.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7j` — CG Q6-g-f entièrement CUDA résident
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_MAX_CELLS_0407`

- **Type :** entier
- **Défaut :** `65536`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0407)

Seuil de cellules du choix automatique du CG mono-bloc.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

### `MPCD_CUDA_Q6_RESIDENT_SKIP_STEP_BOUNDARY_SYNC_0400`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0400)

Supprime la synchronisation de frontière de pas lorsqu’aucun consommateur hôte ne l’exige.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0404)
- **Écrit / contrôle :** `speciesQ6Mode`

Autorise le chemin Q6 résident avec inlet/outlet full-face compatible.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b. | 0493w7: le mode speciesQ6Mode=independent_masked réutilise ce chemin Q6 résident; aucun nouvel env flag Q6 spécifique n’est requis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0409)
- **Écrit / contrôle :** `speciesQ6Mode`

Autorise le chemin Q6 résident avec segments inlet/outlet compatibles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b. | 0493w7: le mode speciesQ6Mode=independent_masked réutilise ce chemin Q6 résident; aucun nouvel env flag Q6 spécifique n’est requis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0401)
- **Écrit / contrôle :** `speciesQ6Mode`

Active la chaîne SRC+Q6 résidente expérimentale pour le cas périodique/step compatible.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b. | 0493w7: le mode speciesQ6Mode=independent_masked réutilise ce chemin Q6 résident; aucun nouvel env flag Q6 spécifique n’est requis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0402)
- **Écrit / contrôle :** `speciesQ6Mode`

Active la chaîne SRC+Q6 résidente pour les configurations wall/step compatibles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b. | 0493w7: le mode speciesQ6Mode=independent_masked réutilise ce chemin Q6 résident; aucun nouvel env flag Q6 spécifique n’est requis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_Q6_RESIDENT_STRICT_0400`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0400)
- **Écrit / contrôle :** `speciesQ6Mode`

Rend fatal tout refus ou fallback du chemin Q6 résident demandé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b. | 0493w7: le mode speciesQ6Mode=independent_masked réutilise ce chemin Q6 résident; aucun nouvel env flag Q6 spécifique n’est requis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0400)
- **Écrit / contrôle :** `speciesQ6Mode`

Active le thermostat associé au backend Q6 résident.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b. | 0493w7: le mode speciesQ6Mode=independent_masked réutilise ce chemin Q6 résident; aucun nouvel env flag Q6 spécifique n’est requis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

### `MPCD_CUDA_Q6_RESIDENT_WARM_START_0408`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 résident 0400–0409
- **Statut :** présent état 36abd23; inventorié 0490p (0408)

Réutilise la solution Q6 précédente comme initialisation du solveur résident.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

### `MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_Q6_TIMING`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** diagnostic/profilage

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0472)

Télécharge explicitement le préfixe actif après commit lorsque requis.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0304

Active le diagnostic post-SRC de support faible/vide sur grille physique non shiftée.

**Remarques.** Écrit/complète cuda_resampling_adaptive_flag_0304.csv; diagnostic passif.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY`

- **Type :** entier
- **Défaut :** `1 à 20 selon script`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0304

Cadence du diagnostic flag 0304.

**Remarques.** Plus la cadence est faible, plus la détection low-N/empty est fréquente.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_THREADS`

- **Type :** entier
- **Défaut :** `256`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0304)

Règle le nombre de threads CUDA par bloc du noyau associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_adaptive_flag_0304.cu`

### `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY`

- **Type :** booléen/env truthy
- **Défaut :** `true dans les diagnostics`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0304

Active la détection des cellules humides vides.

**Remarques.** Utile comme brique commune pour guard adaptatif ou refill futur.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN`

- **Type :** entier
- **Défaut :** `6 dans les scripts de diagnostic`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0304

Seuil de population cellulaire low-N utilisé par le flag.

**Remarques.** Ne déclenche pas de correction avant scheduler adaptatif futur.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0458)

Conserve/active le carrier d’opérations CPU de comparaison.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0468)

Diffère le téléchargement de l’état résident après resampling.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0455)

Conserve le carrier compact des opérations sur le device.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0461)

Règle la cadence d’exécution du module associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_DIAG_CSV_0484`

- **Type :** booléen/env truthy
- **Défaut :** `true sauf production strip 0484`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0484)

Contrôle l’écriture du CSV détaillé du pipeline 0484.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0471)

Valide directement les mutations dans l’état CUDA partagé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0459)

Sélectionne le matérialiseur par tranche de donneur.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0319)

Alias environnemental activant le refill CUDA des cellules humides vides.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`

### `MPCD_CUDA_RESAMPLING_EXTRACTION_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_EXTRACTION_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESAMPLING_FULL_GATE_0484`

- **Type :** booléen/env truthy
- **Défaut :** `true sauf production strip 0484`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0484)

Contrôle l’exécution des comparaisons/gates complets 0484.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U`

- **Type :** réel
- **Défaut :** `1.0`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0305

Seuil de vitesse cellulaire élevée pour la classification géométrique 0305.

**Remarques.** Classe les cellules bulk/wall/solid/open/corner adjacent.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0473)

Active le patchback hôte compact des particules effectivement modifiées.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_INSERTION_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_INSERTION_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Active le reconditionnement conservatif des masses sans changement de support.

**Remarques.** Post-SRC; conserve masse et impulsion cellulaire.

### `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY`

- **Type :** entier
- **Défaut :** `10 ou 20`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Cadence du reconditionnement de masse 0296.

**Remarques.** Utilisé dans les scripts 0296/0303.

### `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH`

- **Type :** double
- **Défaut :** `1.0`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Force du rapprochement des masses vers M_c/N_c.

**Remarques.** 0 passif; 1 homogénéisation complète dans les cellules traitées.

### `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_THREADS`

- **Type :** entier
- **Défaut :** `256`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0296)

Règle le nombre de threads CUDA par bloc du noyau associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_mass_recondition_0296.cu`

### `MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0475b)

Utilise la liste compacte de cellules du plan pour la matérialisation.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0475a)

Déclenche le matérialiseur seulement lorsqu’un plan non vide est disponible.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0475)

Fait consommer l’état partagé directement par le matérialiseur.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298`

- **Type :** booléen/env truthy
- **Défaut :** `true en guard actif`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Active la restauration de l’énergie cinétique relative cellulaire.

**Remarques.** Contrôle K_rel après split/merge.

### `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL`

- **Type :** double
- **Défaut :** `1e-14`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Tolérance absolue de restauration K_rel.

**Remarques.** Diagnostic et évitement des divisions par bruit.

### `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE`

- **Type :** double
- **Défaut :** `4.0`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Borne du facteur de rescale des vitesses relatives.

**Remarques.** Garde-fou contre les corrections thermiques extrêmes.

### `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MIN_CURRENT_KREL`

- **Type :** double >= 0
- **Défaut :** `1e-30`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0298)

Variable runtime interne contrôlant le chemin nommé dans le backend CUDA.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`

### `MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL`

- **Type :** double
- **Défaut :** `1e-12`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Tolérance relative de restauration K_rel.

**Remarques.** Diagnostic et évitement des rescale non significatifs.

### `MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0453)

Active la matérialisation CUDA des opérations à partir du plan compact.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0453)

Règle la cadence d’exécution du module associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD`

- **Type :** réel
- **Défaut :** `1.0`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0306

Seuil |U| pour déclarer une cellule outlier dans les diagnostics 0306.

**Remarques.** Alimente cuda_resampling_outlier_diagnostics_0306_worst_cells.csv.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_PERSISTENT_0240`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0240.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0241.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`

### `MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES`

- **Type :** entier
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0240.md`

### `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0241.md`

### `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0242.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0243.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`

### `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0242.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0243.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`

### `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE`

- **Type :** string
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** prototype/préservé, hors jalon SRC classic 0286

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0242.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0243.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`

### `MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0243_STRICT_ROLES_ONLY`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_persistent_active_path_0240.cpp`

### `MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0448)

Autorise l’application du pipeline CUDA de resampling.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0445)

Active le pipeline CUDA de resampling en mode shadow non autoritatif.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_EVERY_0445`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0445)

Règle la cadence d’exécution du module associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Active le population guard local par split/merge représentatif.

**Remarques.** Post-SRC; doit être utilisé avec restauration 0298 en mode actif.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY`

- **Type :** entier
- **Défaut :** `20 nominal`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Cadence du guard 0297.

**Remarques.** Validation backward step: 20.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_LEGACY_TAIL_SPLIT`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0297)

Réactive le comportement historique complet pour non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_MIN_DONOR_MASS_AFTER_SPLIT`

- **Type :** double >= 0
- **Défaut :** `1e-12`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0297)

Variable runtime interne contrôlant le chemin nommé dans le backend CUDA.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX`

- **Type :** entier
- **Défaut :** `32 nominal`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Borne riche de population cellulaire.

**Remarques.** Triplet nominal validé: 12:20:32.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN`

- **Type :** entier
- **Défaut :** `12 nominal`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Borne pauvre de population cellulaire.

**Remarques.** Triplet nominal validé: 12:20:32.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET`

- **Type :** entier
- **Défaut :** `20 nominal`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Population cible.

**Remarques.** Doit rester cohérent avec gamma nominal.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION`

- **Type :** double
- **Défaut :** `0.5`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Fraction de masse prélevée au donneur lors du split représentatif.

**Remarques.** Conserve masse et impulsion locale avant restauration énergétique.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_THREADS`

- **Type :** entier
- **Défaut :** `256`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0297)

Règle le nombre de threads CUDA par bloc du noyau associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE`

- **Type :** booléen/env truthy
- **Défaut :** `true/on dans scripts 0300+`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Active le filtrage boundary-aware des cellules candidates.

**Remarques.** Évite de mélanger support-control interne et réservoir hard inlet/outlet.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS`

- **Type :** entier
- **Défaut :** `0`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Épaisseur exclue près des parois simples.

**Remarques.** 0 par défaut pour conserver les zones de cisaillement.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Épaisseur exclue près des ouvertures.

**Remarques.** Nominalement 1 cellule.

### `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS`

- **Type :** entier
- **Défaut :** `0`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Épaisseur exclue près des solides immergés.

**Remarques.** 0 par défaut; peut être augmenté pour tests prudents.

### `MPCD_CUDA_RESAMPLING_PRODUCTION_STRIP_0484`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0484)

Désactive les diagnostics/gates coûteux du pipeline de production dépouillé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_REMAP_CELL_COUNT_DIAG_0484`

- **Type :** booléen/env truthy
- **Défaut :** `true sauf production strip 0484`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0484)

Contrôle le diagnostic du nombre de cellules remappées.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0467b)

Utilise un carrier résident fourni par l’orchestration externe.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_RESIDENT_NO_FINAL_DOWNLOAD_PROBE_0469`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0469)

Teste un pas résident sans téléchargement final de l’état complet.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_RESIDENT_UPSTREAM_COUPLED_PROBE_0470`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0470)

Teste le couplage résident direct avec l’amont du resampling.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_SHADOW`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_SHADOW_COMPARE_PLAN`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_SHADOW_CSV`

- **Type :** string
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_SHADOW_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0472)

Committe les mutations dans le shared state sans carrier hôte.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_DONOR_MIN_MASS_0307`

- **Type :** réel
- **Défaut :** `1.0 en mode cautious`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0307

Masse donneur minimale renforcée pour les cellules solid-adjacent.

**Remarques.** Utilisé en mode solid_cautious; non nécessaire dans le mode nominal 0308.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_HALO_CELLS_0307`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0307)

Variable runtime interne contrôlant le chemin nommé dans le backend CUDA.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`

### `MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307`

- **Type :** entier/enum 0 normal, 1 cautious, 2 off
- **Défaut :** `0 nominal`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0307

Contrôle le split dans les cellules solid-adjacent.

**Remarques.** Le mode normal avec split-safety suffit pour le nominal; cautious/off restent diagnostiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0461)

Active la porte de validation du carrier device sparse.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307`

- **Type :** réel
- **Défaut :** `0.5`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0307; nominal 0308

Masse minimale du donneur pour autoriser un split.

**Remarques.** Empêche les splits issus de particules trop légères.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307`

- **Type :** réel
- **Défaut :** `0.25`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0307; nominal 0308

Masse minimale de la particule créée par split et du donneur après split.

**Remarques.** Valeur validée pour couper les outliers de masse/vitesse.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307`

- **Type :** booléen/env truthy
- **Défaut :** `true`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0307; nominal 0308

Choisit préférentiellement le donneur le plus massif pour un split.

**Remarques.** Réduit le risque de resplit de particules déjà allégées.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307`

- **Type :** booléen/env truthy
- **Défaut :** `true dans scripts resampling nominal 0308+`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0307; nominal 0308

Active la prévention des cascades de split créant des particules de masse dégénérée.

**Remarques.** Doit rester activé avec le resampling CUDA nominal.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_SUCCESS_CSV_0484`

- **Type :** booléen/env truthy
- **Défaut :** `hérite de DIAG_CSV_0484`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0484)

Contrôle l’écriture des lignes de succès dans les CSV 0484.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295`

- **Type :** booléen/env truthy
- **Défaut :** `false/off sauf scripts 0295+`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Active le survey CUDA post-SRC non-mutant du support particulaire.

**Remarques.** Écrit cuda_resampling_support_survey_0295.csv; ne modifie pas l’état.

### `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY`

- **Type :** entier
- **Défaut :** `10 ou cadence script`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Cadence du survey 0295.

**Remarques.** 0 ou absent désactive selon script; utilisé après SRC sur grille physique.

### `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE`

- **Type :** string
- **Défaut :** `full`
- **Catégorie :** CUDA resampling post-SRC — survey et guard
- **Statut :** ajout 0295-0303

Mode diagnostic: csv_only, sync_only, alloc_only, deposit_only, full.

**Remarques.** Utilisé pour bisection VK 0295; pas nécessaire en production.

### `MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_THREADS`

- **Type :** entier
- **Défaut :** `256`
- **Catégorie :** CUDA resampling post-SRC — compléments 0295–0319
- **Statut :** présent état 36abd23; inventorié 0490p (0295)

Règle le nombre de threads CUDA par bloc du noyau associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_support_survey_0295.cu`

### `MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0460)

Sélectionne le matérialiseur fondé sur une liste de cellules candidates.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_TINY_MASS_THRESHOLD_0307`

- **Type :** réel
- **Défaut :** `0.1 ou valeur script`
- **Catégorie :** CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0307

Seuil de diagnostic des particules ou splits de masse très faible.

**Remarques.** Produit les compteurs splitFromMassBelow*_0307.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_CSV`

- **Type :** string
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_MAX_TRANSFERS`

- **Type :** entier
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_UNIQUE_RECEIVER`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA resampling — prototype/préservé
- **Statut :** debug/comparaison

Contrôle les prototypes CUDA de resampling; ne fait pas partie du SRC classic full CUDA 0286.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0451)

Rend la partie amont CUDA autoritative à la cadence demandée.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0451)

Règle la cadence d’exécution du module associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0450)

Active le shadow de la partie amont planification/matérialisation.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450`

- **Type :** entier
- **Défaut :** `1`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0450)

Règle la cadence d’exécution du module associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0474)

Fait consommer l’état partagé directement par la partie amont.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_pipeline_shadow_0445.cu`

### `MPCD_CUDA_RESIDENT_PROFILE_0266`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0266_RESIDENT_PERFORMANCE_INSTRUMENTATION.md`

### `MPCD_CUDA_RESIDENT_PROFILE_0267`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESIDENT_PROFILE_0268`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA SRC classic — inlet/outlet full-face
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESIDENT_PROFILE_0269A`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA SRC classic — inlet/outlet segmenté
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESIDENT_PROFILE_0270`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESIDENT_PROFILE_0271`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESIDENT_PROFILE_0272`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESIDENT_PROFILE_0273`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_RESIDENT_PROFILE_0274`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_ROLE_FILTER_FULL_ROLE_SCAN_0315D`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315d)

Variable runtime interne contrôlant le chemin nommé dans le backend CUDA.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_particle_state.cu`

### `MPCD_CUDA_SHARED_STATE_DOWNLOAD_ALL_LEGACY_0315D`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315d)

Force une synchronisation ou un miroir hôte complet, principalement pour compatibilité et audit.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_shared_particle_state_0251.cpp`

### `MPCD_CUDA_SRC_COLLISION_ACTIVE_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_SRC_COLLISION_SHADOW`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_SRC_COLLISION_SHADOW_EVERY`

- **Type :** entier
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_SRC_COLLISION_SHADOW_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_SRC_COLLISION_SHADOW_TOL`

- **Type :** double
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA collision SRC
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `MPCD_CUDA_SRC_COLLISION_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA collision SRC
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`

### `MPCD_CUDA_STREAMING_PERIODIC_0245`

- **Type :** booléen/env truthy
- **Défaut :** `false/off sauf scripts CUDA`
- **Catégorie :** Streaming CUDA résident
- **Statut :** interne/runtime | confirmé 0334a

Active le streaming périodique CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0334a : supporte le cas full-periodic + immersed circle sans téléchargement hôte par step.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0245.md`
- `DEFINED_OR_USED_IN` — `doc/README_full_periodic_circle_resident_0334a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_periodic_0245.cu`

### `MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — périodique
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0260.md`

### `MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — périodique
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0245.md`

### `MPCD_CUDA_STREAMING_PISTON_0247B`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — piston/mobile wall
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0247B.md`

### `MPCD_CUDA_STREAMING_PISTON_0247B_DOWNLOAD_ALL`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — piston/mobile wall
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_STREAMING_PISTON_0247B_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — piston/mobile wall
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — wall-simple
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0246.md`

### `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA SRC classic — wall-simple
- **Statut :** réglage performance/interne

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0261.md`

### `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA SRC classic — wall-simple
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_STREAMING_WALL_SIMPLE_DOWNLOAD_ALL_LEGACY_0315K`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315k)

Force une synchronisation ou un miroir hôte complet, principalement pour compatibilité et audit.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_wall_simple_0246.cu`

### `MPCD_CUDA_THERMOSTAT_PERSISTENT_0258`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0258.md`

### `MPCD_CUDA_THERMOSTAT_PERSISTENT_0258_METADATA_CACHE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `MPCD_CUDA_THERMOSTAT_PERSISTENT_0258_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `MPCD_CUDA_THERMOSTAT_SHADOW`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

### `MPCD_CUDA_THERMOSTAT_SHADOW_DIAG_TOL`

- **Type :** double
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `MPCD_CUDA_THERMOSTAT_SHADOW_EVERY`

- **Type :** entier
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `MPCD_CUDA_THERMOSTAT_SHADOW_STRICT`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `souvent true dans validateurs; dépend du module`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active le mode strict: erreur si le chemin CUDA demandé ne s’applique pas.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `MPCD_CUDA_THERMOSTAT_SHADOW_TOL`

- **Type :** double
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** debug/comparaison

Active comparaison shadow CUDA/CPU pour validation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK`

- **Type :** entier
- **Défaut :** `256 le plus souvent`
- **Catégorie :** CUDA thermostat
- **Statut :** réglage performance/interne

Nombre de threads CUDA par bloc pour le noyau associé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `MPCD_CUDA_THERMOSTAT_USE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off sauf activation par scripts validés`
- **Catégorie :** CUDA thermostat
- **Statut :** interne/runtime

Variable interne de contrôle du backend CUDA.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0244.md`
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0258.md`

### `MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA wall-simple / boîte fermée
- **Statut :** présent depuis 0493x1; ajouté lors du contrôle exhaustif 0493x7q

Autorise le sous-ensemble CUDA résident wall-simple/Q6 pour une boîte fermée statique à quatre faces de réflexion supportées.

**Remarques.** Omission corrigée dans l’inventaire x7q. Ne constitue pas un nouveau développement x7q.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x1` — Chemin de frontières closed-box CUDA résident
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `MPCD_DARCY_EXACT_MOMENTUM_DIAG_0493X8A`

- **Type :** booléen/env truthy
- **Défaut :** `0/off`
- **Catégorie :** Darcy — diagnostic impulsion exacte
- **Statut :** présent source courant; diagnostic; absent inventaire précédent

Active les sommes exactes d'impulsion Darcy, le suivi cumulatif du mean-kick et le CSV exact 0493x8a.

**Remarques.** Lu seulement si Darcy-Brinkman est activé. Les branches physiques de forcing ne sont pas sélectionnées par ce flag.

**Jalons associés :**
- `ASSOCIATED_WITH` → `x8a` — Diagnostic exact du moment Darcy

### `MPCD_DARCY_FASTFLAGS_ENABLE`

- **Type :** booléen | booléen/env truthy
- **Défaut :** `1`
- **Catégorie :** Alias script fastflags Darcy | Darcy/Brinkman CUDA résident — fastflags
- **Statut :** ajout/documenté 0426 | ajout 0426

Active/désactive le bloc commun fastflags 0426 des scripts Darcy. | Active le bloc commun 0426 de drapeaux rapides dans les scripts Darcy de démonstration.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement. | Mettre à 0 pour diagnostic/ablation. La correction 0426 a ramené le backward step Darcy/chiVP segmenté au coût du chemin résident rapide.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_DEPOSIT_PROFILE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_DISABLED_RESAMPLING_SUMMARY_DIAGNOSTICS_0315G`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315g)

Contrôle un diagnostic ou journal runtime du composant associé.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_ELLIPTIC_PROFILE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/elliptic_projection.cpp`

### `MPCD_ENABLE_LIVE_VIS`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Build option live visualization
- **Statut :** ajout 0335

Compile le support GLFW/OpenGL de visualisation live.

**Remarques.** Flag de build. Si absent, le module livevis reste no-op et le build standard ne dépend pas de GLFW/OpenGL.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_live_visualization_0335a.md`
- `DEFINED_OR_USED_IN` — `scripts/build_src_mpcd_cuda_0315b.sh`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_ENSURE_PARTICLE_ROLES_FULL_REFRESH_0315M`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315m)

Variable runtime interne contrôlant le chemin nommé dans le backend CUDA.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/particle_state.cpp`

### `MPCD_FILTERED_FIELD_RECORD_EVERY`

- **Type :** entier > 0 si présent
- **Défaut :** `absent par défaut; sinon override explicite`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a | mis à jour 0433a

Fallback MPCD_* pour l’override expert de cadence d’écriture des dumps filtrés.

**Remarques.** 0433a: n’est plus nécessaire pour obtenir une cadence d’enregistrement; le comportement par défaut est WYSIWYR avec recordEvery=liveEvery. Une valeur env >0 force recordEverySource=override.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_FILTERED_FIELD_RECORD_FIELDS`

- **Type :** liste CSV de champs
- **Défaut :** `current`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Fallback MPCD_* pour la liste des champs à enregistrer.

**Remarques.** Utilisé si SRC_FILTERED_FIELD_RECORD_FIELDS est absent.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_FILTERED_FIELD_RECORDING_0432`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Active le recorder observation-only de champs filtrés.

**Remarques.** Indispensable pour produire des dumps filtrés; recordEnable=true dans livevis_control.kv ne suffit pas si ce flag est absent. Alias SRC_FILTERED_FIELD_RECORDING_0432 accepté.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_FILTERED_FIELD_SAMPLE_EVERY`

- **Type :** entier >= 1
- **Défaut :** `1`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Fallback MPCD_* pour la cadence d’échantillonnage du recorder.

**Remarques.** Utilisé si SRC_FILTERED_FIELD_SAMPLE_EVERY est absent.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_FILTERED_FIELD_TAU`

- **Type :** double >= 0
- **Défaut :** `0.0`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Fallback MPCD_* pour initialiser filterTau du recorder.

**Remarques.** Utilisé si SRC_FILTERED_FIELD_TAU est absent; la clé control-file filterTau peut ensuite surcharger.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_INTERNAL_PROFILES`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage | propagé scripts Darcy 0426

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo. | 0426 : intégré au bloc fastflags Darcy pour éviter le backend collision/thermostat lent dans les cas chi/segments.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0266_RESIDENT_PERFORMANCE_INSTRUMENTATION.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_LIVE_VIS_ALPHA`

- **Type :** double [0,1]
- **Défaut :** `0.08 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c | alias/fallback MPCD_* recensé 0432a | précisé 0436b

Alias/fallback MPCD_* de SRC_LIVE_VIS_ALPHA. Lissage temporel du rendu CPU fallback.

**Remarques.** Le chemin CUDA field rend directement une image compacte; alpha est surtout utile au fallback CPU. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp. | 0436b: persistance temporelle du champ affiché; alpha=1.0 donne un affichage immédiat. Le changement de field/particleTypeFilter doit réinitialiser displayScalar une frame, puis reprendre le lissage.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_CLIP`

- **Type :** double; <=0 auto
- **Défaut :** `-1 auto`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_CLIP. Échelle de saturation/clip couleur.

**Remarques.** Valeur fixe utile pour comparer plusieurs runs; auto utile pour inspection rapide. | 0341a: valeur initiale seulement; peut être modifiée à chaud via livevis_control.kv si SRC_LIVE_VIS_CONTROL_FILE est défini. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_COLORMAP`

- **Type :** enum: blue_red | gray | thermal
- **Défaut :** `blue_red`
- **Catégorie :** Live visualization colormap
- **Statut :** ajout 0342a | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_COLORMAP. Colormap consommé par le renderer livevis, y compris le chemin CUDA field 0337.

**Remarques.** Mis à jour dans le processus lors de la relecture de livevis_control.kv lorsque la clé colormap change. Alias acceptés: grey/grayscale/greyscale -> gray; heat/hot -> thermal. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_colormap_control_0342a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_CONTROL_EVERY`

- **Type :** entier >= 1
- **Défaut :** `1`
- **Catégorie :** Live visualization runtime control
- **Statut :** ajout 0341a | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_CONTROL_EVERY. Stride de relecture du fichier de contrôle sur les opportunités d’affichage livevis.

**Remarques.** Avec LIVE_VIS_EVERY=25 et CONTROL_EVERY=1, le fichier est relu à chaque frame livevis. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_CONTROL_FILE`

- **Type :** chemin fichier .kv
- **Défaut :** `vide/off si non fourni`
- **Catégorie :** Live visualization runtime control
- **Statut :** ajout 0341a; propagé scripts 0341b/0341d | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_CONTROL_FILE. Chemin du fichier livevis_control.kv relu à chaud par le binaire pour modifier field/clip/gain/smoothPasses/colormap sans redémarrage.

**Remarques.** Le chemin recommandé est fourni par les scripts depuis LIVE_VIS_CONTROL_FILE_EFFECTIVE. Les logs de reload sont écrits dans le fichier .time. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341b_scripts.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_CONTROL_LOG`

- **Type :** booléen/env truthy
- **Défaut :** `1 dans scripts 0341b/0341d`
- **Catégorie :** Live visualization runtime control
- **Statut :** ajout 0341a | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_CONTROL_LOG. Active les lignes de diagnostic [livevis0335] control reload dans stderr/.time.

**Remarques.** Très utile pour vérifier que le fichier est bien relu et que field/clip/gain/smoothPasses/colormap changent. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_ENABLE`

- **Type :** booléen/env truthy
- **Défaut :** `copie de LIVE_VIS_ENABLE/SRC_LIVE_VIS_ENABLE`
- **Catégorie :** Live visualization runtime
- **Statut :** mis à jour 0426

Alias historique/runtime pour activer ou désactiver la visualisation temps réel.

**Remarques.** Exporté explicitement par les scripts Darcy et livevis ; garder synchronisé avec SRC_LIVE_VIS_ENABLE.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `MPCD_LIVE_VIS_EVERY`

- **Type :** entier > 0
- **Défaut :** `10 code; 20 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335 | mis à jour 0339a | alias/fallback MPCD_* recensé 0432a | mis à jour 0433a

Initialise la cadence livevis au démarrage; depuis 0433a cette cadence peut être modifiée à chaud par livevis_control.kv:liveEvery/every/visualEvery.

**Remarques.** Augmenter pour réduire le coût d’affichage. | 0339a: export effectif issu de LIVE_VIS_EVERY dans les scripts livevis; défaut script recommandé 25. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp. | 0433a: livevis_control.kv:liveEvery devient le contrôle runtime canonique; recordEvery absent ou <=0 suit cette cadence pour les dumps filtrés.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.h`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_FIELD`

- **Type :** string: mêmes valeurs que SRC_LIVE_VIS_FIELD
- **Défaut :** `fallback si SRC_LIVE_VIS_FIELD absent`
- **Catégorie :** Live visualization runtime
- **Statut :** mis à jour 0361

Alias/fallback historique pour choisir le champ live.

**Remarques.** Utilisé par live_visualization_0335.cpp comme fallback MPCD_* pour la plupart des contrôles livevis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_GAIN`

- **Type :** double > 0
- **Défaut :** `1.0`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c/0337 | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_GAIN. Gain visuel appliqué à la colormap.

**Remarques.** Réduire si l’image est saturée rouge/bleu; augmenter pour renforcer le contraste. | 0341a: valeur initiale seulement; peut être modifiée à chaud via livevis_control.kv si SRC_LIVE_VIS_CONTROL_FILE est défini. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_HOLD_ON_EXIT`

- **Type :** booléen/env truthy
- **Défaut :** `1 dans scripts interactifs; 0 recommandé en batch`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0421; propagé Darcy 0425/0426 | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_HOLD_ON_EXIT. Conserve la fenêtre livevis ouverte à la fin du run lorsque la visualisation est active.

**Remarques.** Introduit pour inspection interactive ; désactiver en campagnes automatiques afin que le script termine. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_NO_SOLID_OVERLAY`

- **Type :** voir alias SRC_* correspondant
- **Défaut :** `voir alias SRC_* correspondant`
- **Catégorie :** Live visualization runtime
- **Statut :** alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* livevis.

**Remarques.** Utilisé comme fallback runtime par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_NX`

- **Type :** entier >= 16
- **Défaut :** `300 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335/0337 | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_NX. Résolution x de la grille/champ live.

**Remarques.** Plus élevé = plus fin mais plus coûteux. 300×80 validé comme compromis. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_NY`

- **Type :** entier >= 16
- **Défaut :** `80 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335/0337 | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_NY. Résolution y de la grille/champ live.

**Remarques.** Plus élevé = plus fin mais plus coûteux. 300×80 validé comme compromis. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_PARTICLE_TYPE_FILTER`

- **Type :** entier
- **Défaut :** `-1`
- **Catégorie :** Live visualization runtime / particle type filter 0436
- **Statut :** ajout 0436 alias/fallback MPCD_*

Alias/fallback MPCD_* de SRC_LIVE_VIS_PARTICLE_TYPE_FILTER.

**Remarques.** Même convention: -1=all; 0/1/2 types particulaires. Utile pour compatibilité avec les anciens scripts MPCD_*.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_QUANTILE`

- **Type :** double dans (0,1]
- **Défaut :** `0.995`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_QUANTILE. Quantile d’échelle auto du rendu CPU fallback.

**Remarques.** Limite l’effet du bruit particulaire et des outliers. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_QUIVER_MIN_SPEED`

- **Type :** double >= 0
- **Défaut :** `0`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Seuil minimal de vitesse sous lequel les segments quiver ne sont pas dessinés.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_QUIVER_NX`

- **Type :** entier >= 1
- **Défaut :** `60`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Nombre de colonnes de la grille vectorielle quiver décimée.

**Remarques.** Un coût faible est obtenu en gardant une grille décimée, par exemple 60x32.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_QUIVER_NY`

- **Type :** entier >= 1
- **Défaut :** `32`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Nombre de lignes de la grille vectorielle quiver décimée.

**Remarques.** Un coût faible est obtenu en gardant une grille décimée, par exemple 60x32.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_QUIVER_SCALE`

- **Type :** double
- **Défaut :** `-1`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Gain manuel des segments vitesse, en pixels par unité de vitesse.

**Remarques.** Valeur <0: désactive l’overlay quiver; valeur >=0: active l’overlay.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_QUIVER_SMOOTH_PASSES`

- **Type :** entier; -1 ou >=0
- **Défaut :** `-1`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0365

Nombre de passes de lissage 3x3 appliquées aux vecteurs quiver sur la grille décimée.

**Remarques.** <0 réutilise smoothPasses; 0 désactive le lissage des vecteurs; >0 fixe le nombre de passes.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_SMOOTH_PASSES`

- **Type :** entier >= 0
- **Défaut :** `1 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c/0337 | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_SMOOTH_PASSES. Nombre de passes de lissage spatial du champ live.

**Remarques.** Vorticité: souvent 1 ou 2; champs vitesse: 0 ou 1. | 0341a: valeur initiale seulement; peut être modifiée à chaud via livevis_control.kv si SRC_LIVE_VIS_CONTROL_FILE est défini. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_LIVE_VIS_VSYNC`

- **Type :** booléen/int
- **Défaut :** `0 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335 | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_VSYNC. Contrôle vsync de la fenêtre GLFW.

**Remarques.** 0 recommandé pour ne pas brider la simulation; 1 utile si affichage trop rapide. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_LIVE_VIS_WINDOW_SCALE`

- **Type :** entier >= 1
- **Défaut :** `1`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335 | alias/fallback MPCD_* recensé 0432a

Alias/fallback MPCD_* de SRC_LIVE_VIS_WINDOW_SCALE. Facteur d’échelle de la fenêtre OpenGL.

**Remarques.** N’affecte pas la physique ni la grille de calcul. | Ajouté à l’inventaire car utilisé comme fallback par live_visualization_0335.cpp et/ou filtered_field_recorder_0432.cpp.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `MPCD_MASS_GUARD_PROFILE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_POP_GUARD_PROFILE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_PROFILE_PHASE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** Profilage / instrumentation
- **Statut :** diagnostic/profilage

Active des sorties de profiling/instrumentation.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

### `MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-G-F — mouillage expérimental
- **Statut :** ajout 0493x9i; legacy/ablation

Réactive la fermeture x9i qui impose directement la normale de Young près du mur.

**Remarques.** Conservé pour reproductibilité; angle exact mais courbure fortement biaisée hors 90 deg. Ne pas utiliser comme fermeture de production.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9i` — Première fermeture d'angle de contact par normale imposée

### `MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M`

- **Type :** booléen/env truthy
- **Défaut :** `false/off; runners x9m/x9p peuvent mettre 1`
- **Catégorie :** Q6-G-F — mouillage
- **Statut :** ajout 0493x9m; fermeture statique préférée actuelle

Active la courbure de contact x9m par ancre p3 hors support de paroi.

**Remarques.** Utilise la première normale p3 non contaminée par le support mur (couche 4, centre 4.5h) et kappa=2 sin(DeltaPhi/2)/L. Qualifié statiquement 0<theta<180 sur parois de domaine; chi-wall et dynamique quantitative restent à faire.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9m` — Fermeture statique de mouillage par ancre hors support

### `MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-G-F — mouillage expérimental
- **Statut :** ajout 0493x9l; ablation

Active la reconstruction x9l de normale au mur avant div(n).

**Remarques.** Expérience négative hors voisinage de 90 deg; gardée pour comparaison. Requiert paroi statique de domaine.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9l` — Reconstruction de normale au mur-face

### `MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-G-F — diagnostics capillaires
- **Statut :** ajout 0493x9f; diagnostic seulement

Active les moments géométriques d’ellipse/goutte: rayons principaux, ellipticité, angle, COM.

**Remarques.** Observation-only; utilisé pour la circularisation et les oscillations capillaires.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9f` — Diagnostic de bande interfaciale vraie et relaxation elliptique

### `MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y`

- **Type :** booléen/env truthy
- **Défaut :** `ON si variable absente/vide; OFF seulement si valeur non-truthy explicite`
- **Catégorie :** Q6 — ablation fermeture B1 périodique
- **Statut :** présent source courant; défaut production ON; absent inventaire précédent

Contrôle l'étape x7q de réduction exacte du résidu particulaire et la seconde fermeture B1 en périodique plein domaine.

**Remarques.** OFF est une ablation contrôlée: B1 et la correction x7d-v2-fix2 précédente restent actives.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d-v2-fix2` — Première fermeture du moment périodique B1 au niveau cellule
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1`

- **Type :** booléen/env truthy
- **Défaut :** `false/off backend; 1 dans les runners Q6-g-f`
- **Catégorie :** Q6-g-f / application face-particule
- **Statut :** ajout 0493x6h-B1; production Q6-g-f; fermeture k=0 exacte x7q

Active la reconstruction affine RT0/MAC-to-particle. En fullDomain périodique, x7q mesure ensuite le moment réellement appliqué et ferme exactement le mode k=0.

**Remarques.** Le chemin partial-domain/dam-break garde le kernel B1 historique. x7q est automatique et ne crée pas de nouveau flag.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6h-B1` — Reconstruction affine RT0/MAC des corrections face-vers-particule
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `MPCD_Q6_G_F_RESIDENT_CG_0493X7J`

- **Type :** booléen/env truthy
- **Défaut :** `true/on si variable absente ou vide`
- **Catégorie :** Q6-g-f / CG CUDA résident
- **Statut :** ajout 0493x7j; production qualifiée x7q

Sélectionne le CG Q6-g-f coopératif entièrement device-resident; 0 force le fallback historique/qualification.

**Remarques.** Gate d’exécution seulement, sans changement de physique. Le host récupère un petit état une fois le solve terminé; aucune réduction GPU→CPU à chaque itération.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X7J_Q6_G_F_RESIDENT_CG.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7j` — CG Q6-g-f entièrement CUDA résident
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `MPCD_Q6_PHASE_CURVATURE_AUDIT_WALL_MARGIN_CELLS_0493X9B`

- **Type :** entier >=0
- **Défaut :** `8`
- **Catégorie :** Q6 — diagnostic courbure
- **Statut :** présent source courant; diagnostic; absent inventaire précédent

Marge en cellules exclue autour des parois non périodiques dans les métriques d'audit de courbure.

**Remarques.** Valeur clampée à >=0; n'affecte pas la courbure de production, seulement les régions d'audit.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

### `MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-G-F — diagnostics de courbure
- **Statut :** ajout 0493x9a; diagnostic seulement

Active les audits passifs de courbure/interface x9a.

**Remarques.** Ne change pas la physique; utilisé pour les statistiques plan/cercle et la géométrie initiale.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9a_ellipse_curvature.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9a` — Premier scaffold passif de courbure résident

### `MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-G-F — diagnostics de courbure
- **Statut :** ajout 0493x9b; diagnostic seulement

Active les diagnostics du champ de courbure p1/Scharr x9b.

**Remarques.** Ne change pas la physique; p1 reste un baseline alors que p3 est retenu pour la production.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9b` — Courbure passive binomiale + Scharr et LiveVis résident

### `MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-G-F — diagnostics de courbure
- **Statut :** ajout 0493x9c; diagnostic seulement

Active les diagnostics de sweep p1/p2/p3.

**Remarques.** Ne change pas la physique; le sweep a retenu p3 (trois passes binomiales) pour la courbure de production.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9c` — Qualification du support de lissage de courbure

### `MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6g

Active la valeur Dirichlet de pression gazeuse sur les faces interfaciales préparées x6f.

**Remarques.** Requiert x6f; ne modifie pas la matrice CG. scale=0 utilise le bypass strict après fix2. | 0493x14v requiert x6g actif afin de soustraire la traction thermodynamique déjà représentée avant transfert de l’excès cinétique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_phase_gas_pressure.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14v` — Kick cinétique excédentaire
- `ASSOCIATED_WITH` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G`

- **Type :** double fini
- **Défaut :** `0.0 backend; runner=reference`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6g

Valeur p_const utilisée lorsque MODE=constant.

**Remarques.** Variable de validation; n’est pas un nouveau paramètre physique params.kv.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G`

- **Type :** enum string
- **Défaut :** `eos`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** 0493x6g; étendu x14s avec eos_accessible_volume

Choisit la source de pression interfaciale: eos, constant ou eos_accessible_volume.

**Remarques.** eos: p_g=N_g kBT/Acell avec espèces phaseFamily=gas; constant: ablation/jauge; eos_accessible_volume (x14s): p_g=p_raw/f_Q6 avec f_Q6 dérivée de g=1-alpha_Q6 sur la trace gaz, g0=0.37396789550781245, g1=0.9153533203125 et plancher défensif 0.05. La correction est évaluée sur les faces x6f déjà préparées, sans nouvelle passe globale.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_0493x14s_x6g_accessible_volume_drop.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14s` — EOS gaz volume accessible
- `ASSOCIATED_WITH` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G`

- **Type :** double fini
- **Défaut :** `0.0 backend; runner EOS=pression uniforme initiale`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6g

Définit p_ref soustrait à p_g comme jauge avant conversion en phiGamma.

**Remarques.** Le runner 0493x6g choisit normalement gamma*kBT/Acell; une constante de pression ne doit pas modifier les gradients.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_phase_gas_pressure.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G`

- **Type :** double >= 0
- **Défaut :** `1.0`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6g

Multiplie la différence de pression interfaciale avant conversion en phiGamma.

**Remarques.** scale=0 est le test de null path strict; scale=1 est le mode physique nominal.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6d; expérimental/non retenu comme chemin final

Active l’opérateur cut-face x6d sur le bord du carrier avec coefficient 1/theta.

**Remarques.** Expérience utile mais non retenue comme architecture finale: x6e montre que bord du carrier != interface alpha=0.5; theta<0.10 garde facteur 2. Mutuellement exclusif avec x6f.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6D_GUARDED_CUTFACE_ZERO_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6d` — Expérience cut-face 1/theta sur le bord du carrier
- `ASSOCIATED_WITH` → `x6e` — Audit topologique de l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6b

Active l’audit géométrique raw alpha/support/interface sans changer l’opérateur.

**Remarques.** Diagnostic sparse; mesure notamment bracket alpha=0.5 et normales brutes.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6B_PHASE_GEOMETRY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6b_phase_geometry_diagnostic.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6b` — Diagnostic géométrique support Q6 / interface alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6c

Matérialise les champs CUDA résidents phaseFillRaw et alpha filtré utilisés par la géométrie d’interface.

**Remarques.** Le filtre x6c utilise actuellement lambda=0.125 fixé dans le code; pas un paramètre utilisateur. Requis par x6f/x6g.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6C_PHASE_GEOMETRY_RESIDENT.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6c_phase_geometry_resident.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6c` — Infrastructure résidente du champ de phase alpha
- `ASSOCIATED_WITH` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6f; correctif partition near-half conservé dans Q6-g-f

Active le pressureMask alpha>=0.5 et le stencil de faces préparé une fois par solve, séparé du carrier.

**Remarques.** Requiert x6c; x6d doit être désactivé. Prépare coefficients 1, 1/theta, 2 small-theta ou 0; base du couplage pGamma x6g. Correctif Q6-g-f: pour une traversée alpha=0.5, le dénominateur est accepté dès denom>0 (et non >1e-14), afin que toute traversée topologique soit représentée par le stencil; aucun nouveau flag.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6F_PHASE_INTERFACE_STENCIL.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6f_phase_interface_stencil.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6c` — Infrastructure résidente du champ de phase alpha
- `ASSOCIATED_WITH` → `x6d` — Expérience cut-face 1/theta sur le bord du carrier
- `ASSOCIATED_WITH` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `ASSOCIATED_WITH` → `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d

### `MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6e

Active l’audit de topologie de toutes les traversées alpha=0.5, indépendamment du bord du carrier.

**Remarques.** Classe AA/AI/II pour diagnostic uniquement; x6f réutilise cet audit pour vérifier la couverture de l’interface physique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6E_PHASE_INTERFACE_TOPOLOGY.md`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6e` — Audit topologique de l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6 phase/interface 0493x6
- **Statut :** ajout 0493x6a

Active le diagnostic de pression gazeuse/interfaciale x6a sans modifier la physique Q6.

**Remarques.** Produit l’audit de pression de phase; free_surface_masked conserve pGamma=0 dans x6a.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6A_Q6_PHASE_PRESSURE_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6a_phase_pressure_diagnostic.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6a` — Diagnostic EOS de pression gazeuse interfaciale
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-g-f / diagnostic post-application
- **Statut :** ajout 0493x6h-B0; diagnostic seulement

Active un audit sparse de la divergence redéposée par régions bulk/interface/paroi après application aux particules.

**Remarques.** Lazily allocated; aucun buffer ni kernel supplémentaire lorsque désactivé. A servi à localiser le défaut face-vers-cellule; reste off dans les runs Q6-g-f de production.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/analyze_0493x6h_b0_postapply_regions.py`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6h-B0` — Diagnostic régional de divergence après application aux particules
- `ASSOCIATED_WITH` → `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d

### `MPCD_Q6_PROFILE`

- **Type :** booléen/env truthy sauf mention contraire
- **Défaut :** `false/off`
- **Catégorie :** CUDA Q6 — prototype/chantiers futurs
- **Statut :** diagnostic/profilage

Contrôle les prototypes CUDA Q6; Q6 CUDA reste un chantier séparé.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/q6_projection_adapter.cpp`

### `MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Q6-G-F — diagnostics capillaires
- **Statut :** ajout 0493x9e; diagnostic seulement; sigma=0 restauré x11c-fix6

Active les métriques goutte statique: Reff, pression Q6, vitesses RMS et résultante capillaire.

**Remarques.** Observation-only. x11c autorise la construction du p3 à cadence de diagnostic même à sigma=0, sans passer ce champ au potentiel capillaire de production; permet la soustraction de jauge Q6 appariée.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x11a_young_laplace_sigma0_baselines.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `ASSOCIATED_WITH` → `x9e` — Qualification diagnostique de goutte statique

### `MPCD_RESAMPLING_DISABLED_DIAGNOSTICS_LEGACY_0315G`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315g)

Réactive le comportement historique complet pour non-régression.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0437)

Active la recherche spatiale de donneurs du resampling pondéré CPU/OpenMP.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437_SHADOW`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA resampling résident — pipeline 0437–0484
- **Statut :** présent état 36abd23; inventorié 0490p (0437)

Exécute la recherche spatiale en miroir pour comparaison avec la recherche globale.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/weighted_resampling.cpp`

### `MPCD_RUNTIME_BACKEND`

- **Type :** string
- **Défaut :** `utilisé si MPCD_BACKEND absent; cuda par défaut dans runner primaire`
- **Catégorie :** Backend principal
- **Statut :** principal utilisateur

Alias/fallback pour choisir cuda/openmp lorsque MPCD_BACKEND absent.

**Remarques.** Ne se place pas dans params.kv; à passer dans l’environnement du shell ou dans les scripts de validation/démo.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0275_CUDA_PRIMARY_BACKEND.md`

### `MPCD_VALIDATE_PARTICLE_ROLES_FULLSCAN_0315L`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** CUDA état résident / active-prefix — audit et compatibilité
- **Statut :** présent état 36abd23; inventorié 0490p (0315l)

Force une validation exhaustive ou un scan complet de l’active-prefix/roles.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/particle_state.cpp`

### `MPCD_X10_KINETIC_INTERFACE_CIC`

- **Type :** booléen/env int
- **Défaut :** `0/off source; 1 dans x12 production`
- **Catégorie :** Surface libre cinétique — géométrie CIC x10cic
- **Statut :** actif dans chaîne x12 courante; ON

Construit un alpha CIC dédié à l'interface cinétique, séparé des buffers alpha x6c utilisés par Q6/pression/capillarité.

**Remarques.** Dépôt CIC fusionné avec le passage particulaire total-A déjà obligatoire: pas de nouveau parcours O(Np). Ajoute un filtre O(Ncell) et un champ double/cellule persistant. IMPORTANT: l'orchestration reste dans apply_independent_masked_species_q6_0493w5; ce n'est pas encore un chemin SRC-only hors Q6.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10cic` — Alpha cinétique CIC dédié
- `ASSOCIATED_WITH` → `x6c` — Infrastructure résidente du champ de phase alpha

### `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE`

- **Type :** booléen/env int
- **Défaut :** `0/off source; 1 dans x12 production`
- **Catégorie :** Surface libre cinétique — relocalisation x10u
- **Statut :** actif dans chaîne x12 courante; ON | qualifié/tag 7655b81 au 31/08/2026

Remplace l'impulsion spéculaire Q2 par une relocalisation positionnelle one-for-one de la même particule.

**Remarques.** Effectif uniquement si vrai Q2 actif; requiert x10p. Masse et vitesse de la particule ne changent pas du fait de x10u; pas de split/merge. x10u lui-même n'ajoute pas de buffer/kernel global. | Audit final: présent au commit 7655b81; chaîne x13k/x13n revalidée. x10v est full-vector lorsque NORMAL_ONLY=0.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x13h.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10p` — Résolution des recouvrements initiaux
- `ASSOCIATED_WITH` → `x10u` — Relocalisation conservative one-for-one
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x13k` — Qualification goutte oscillante n=2
- `ASSOCIATED_WITH` → `x13n` — Benchmark Taylor–Culick 2-D

### `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablation x13o normal-only
- **Statut :** implémenté au commit 7655b81; OFF dans chaîne qualifiée/tag surf-tension-qualified-x13h-20260831

Lorsque x10u+x10v sont actifs, échange uniquement la composante normale locale entre la particule relocalisée et son partenaire égal-masse; composante tangentielle inchangée.

**Remarques.** Requiert MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1. Le log distingue normal-component-swap de full-vector-swap. Les runners x13k/x13n qualifiés ne l’activent pas; le point de référence utilise full-vector swap.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x13h.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10u` — Relocalisation conservative one-for-one
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x13k` — Qualification goutte oscillante n=2
- `ASSOCIATED_WITH` → `x13n` — Benchmark Taylor–Culick 2-D
- `ASSOCIATED_WITH` → `x13o` — Ablation swap normal-only

### `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP`

- **Type :** booléen/env int
- **Défaut :** `0/off source; 1 dans x12 production`
- **Catégorie :** Surface libre cinétique — échange conservatif x10v
- **Statut :** actif dans chaîne x12 courante; ON | qualifié/tag 7655b81 au 31/08/2026

Après x10u, échange le vecteur vitesse complet avec un partenaire liquide intérieur local de même masse.

**Remarques.** Requiert x10u. Les paires de masses inégales ne sont pas échangées. Un swap égal-masse conserve exactement l'impulsion et l'énergie cinétique globales de la paire. Coût: 1 octet/particule + deux kernels particulaires; deux buffers cellule x10m sont réutilisés pour les candidats. | Audit final: présent au commit 7655b81; chaîne x13k/x13n revalidée. x10v est full-vector lorsque NORMAL_ONLY=0.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x13h.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10u` — Relocalisation conservative one-for-one
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x13k` — Qualification goutte oscillante n=2
- `ASSOCIATED_WITH` → `x13n` — Benchmark Taylor–Culick 2-D

### `MPCD_X10_KINETIC_INTERFACE_QUADRATIC`

- **Type :** booléen/env int
- **Défaut :** `0/off source; 1 dans x12 production`
- **Catégorie :** Surface libre cinétique — reconstruction vrai Q2 x10biq
- **Statut :** actif dans chaîne x12 courante; ON

Active la reconstruction biquadratique tensorielle 3x3 de l'interface cinétique.

**Remarques.** N'est effectif que sous x10o; requiert CIC. 9 charges alpha par patch actif, pas de grille de coefficients, pas de buffer/kernel/global pass supplémentaire. Exige x10r=x10s=x10t=0.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10biq` — Reconstruction Q2 biquadratique tensorielle
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10r` — Ablation vitesses endpoints full-vector
- `ASSOCIATED_WITH` → `x10s` — Ablation cinématique normale au segment
- `ASSOCIATED_WITH` → `x10t` — Ablation cinématique tangentielle rigide

### `MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — branche x10w pairwise
- **Statut :** implémenté; OFF chaîne x12 courante

Active la redistribution thermique locale pairwise pré-stream, conservative P/K, modulée par Lloc.

**Remarques.** Requiert x10v et x10o; effectif seulement avec vrai Q2. Mutuellement exclusif avec x12a. L'ancien virtual-position limiter est explicitement désactivé dans le kernel de collision.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x10w` — Limiter thermique local pairwise
- `ASSOCIATED_WITH` → `x12a` — Refroidissement thermique local des petites structures

### `MPCD_X10_MICRO_REFLECTION_TRACE`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — diagnostic microscopique
- **Statut :** diagnostic source courant; OFF production

Active un printf/trace par réflexion pour de très petits runs.

**Remarques.** Effectif seulement sous x10o; explicitement diagnostic, physique inchangée; à éviter sur runs longs.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

### `MPCD_X10I_REACTION_BLOCK_CELLS`

- **Type :** entier
- **Défaut :** `5; clamp [2,32]`
- **Catégorie :** Surface libre cinétique — réaction mésoscopique héritée x10i
- **Statut :** implémentation active uniquement dans le fallback cinétique hard-r1; hors chaîne x12 production

Fixe la taille des blocs mésoscopiques décalés déterministiquement utilisés pour la réaction conservative x10i.

**Remarques.** N'intervient que lorsqu'aucune des branches x10o/x10n/x10m/x10j/x10k n'est active et r>=1. La chaîne x12 courante x10o bypass x10i.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10i` — Réaction exacte par réservoirs mésoscopiques décalés
- `ASSOCIATED_WITH` → `x10j` — Ablation spéculaire dans le repère laboratoire
- `ASSOCIATED_WITH` → `x10k` — Ablation spéculaire dans le repère liquide local
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

### `MPCD_X10J_SIMPLE_SPECULAR_ABLATION`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablations x10
- **Statut :** implémentation historique retenue dans le source; OFF chaîne x12 courante

Sélectionne l’ablation de réflexion spéculaire simple en repère laboratoire.

**Remarques.** Ablation labo selectable uniquement lorsque x10o/x10n/x10m/x10k sont inactifs et r>=1. Priorité la plus basse des ablations spéculaires. Non utilisée par les runners x12 de production.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10j` — Ablation spéculaire dans le repère laboratoire
- `ASSOCIATED_WITH` → `x10k` — Ablation spéculaire dans le repère liquide local
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablations x10
- **Statut :** implémentation historique retenue dans le source; OFF chaîne x12 courante

Sélectionne l’ablation spéculaire dans un repère liquide local.

**Remarques.** Ablation local-frame selectable seulement si x10o/x10n/x10m sont OFF et r>=1. Non utilisée en production x12.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10k` — Ablation spéculaire dans le repère liquide local
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS`

- **Type :** booléen/env int
- **Défaut :** `0/off source; x12d JFM=1; x12cal/x12yl=0`
- **Catégorie :** Surface libre cinétique — diagnostic
- **Statut :** diagnostic passif courant; ON JFM x12d, OFF calibrateurs x12cal/x12yl
- **Écrit / contrôle :** `summaryEvery`

Accumule la vitesse normale liquide post-Q6/B1 avant le traitement cinétique.

**Remarques.** Deux kernels de diagnostic sont lancés seulement aux pas d'audit (step<=1 ou step%summaryEvery==0). Ils mesurent l'état pré-paroi et ne changent pas la physique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12yl_young_laplace_calibrator.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10l` — Diagnostic passif pré-paroi cinétique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `ASSOCIATED_WITH` → `x12cal` — Calibrateur dynamique de tension superficielle
- `ASSOCIATED_WITH` → `x12d` — Cas de mesure JFM 524 à géométrie/We/Fr ciblés
- `ASSOCIATED_WITH` → `x12yl` — Calibrateur mécanique/statique de tension superficielle

### `MPCD_X10M_MOVING_INTERFACE_WALL`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablations x10
- **Statut :** implémentation historique selectable; OFF chaîne x12 courante

Active l’ancienne géométrie locale de paroi mobile pilotée par Q6.

**Remarques.** Paroi mobile locale antérieure à la polyligne continue. Effective seulement si x10o et x10n sont OFF et r>=1.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablations x10
- **Statut :** implémentation historique selectable; OFF chaîne x12 courante

Active la polyligne continue alpha=0.5 sans enveloppe thermique x10o.

**Remarques.** Polyligne continue alpha=0.5 sans enveloppe thermique x10o. Effective seulement si x10o est OFF et r>=1. Les primitives x10n sont encore réutilisées par x10o/Q2/x12a.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `ASSOCIATED_WITH` → `x12a` — Refroidissement thermique local des petites structures

### `MPCD_X10O_Q6_THERMAL_INTERFACE_WALL`

- **Type :** booléen/env int
- **Défaut :** `0/off source; 1 dans x12 production`
- **Catégorie :** Surface libre cinétique — chaîne retenue
- **Statut :** socle cinétique de la chaîne x12 courante; ON

Active la surface continue pilotée par le champ hydro Q6 du même pas avec enveloppe cinétique thermique.

**Remarques.** Actif seulement pour r>=1. Exige un champ hydrodynamique Q6 projeté du même pas/type. A priorité sur x10n/x10m/x10k/x10j. Dans la chaîne x12 actuelle il est combiné à CIC+Q2+x10u+x10v+x12a.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10j` — Ablation spéculaire dans le repère laboratoire
- `ASSOCIATED_WITH` → `x10k` — Ablation spéculaire dans le repère liquide local
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x10u` — Relocalisation conservative one-for-one
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `ASSOCIATED_WITH` → `x12a` — Refroidissement thermique local des petites structures

### `MPCD_X10O_THERMAL_MAX_CELLS`

- **Type :** double >=0
- **Défaut :** `0.75`
- **Catégorie :** Surface libre cinétique — enveloppe thermique
- **Statut :** paramètre env actif dans chaîne x10o/x12

Plafond de l’enveloppe thermique en nombre de cellules.

**Remarques.** Plafond de l'épaisseur x10o: min(maxCells*h, C*dt*sqrt(kBT/m)). La chaîne x12/JFM le verrouille à 0.75.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `MPCD_X10O_THERMAL_PARTICLE_MASS`

- **Type :** double >0
- **Défaut :** `1.0 source; runners x12: LIQUID_MASS`
- **Catégorie :** Surface libre cinétique — enveloppe thermique
- **Statut :** paramètre env actif dans chaîne x10o/x12

Masse m dans delta=min(C dt sqrt(kBT/m), maxCells*h).

**Remarques.** Masse utilisée dans dt*sqrt(kBT/m). Les runners x12 la verrouillent sur LIQUID_MASS. Elle est aussi relue par la métrique x10w même lorsque x10w est OFF.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x10w` — Limiter thermique local pairwise
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `MPCD_X10O_THERMAL_SIGMAS`

- **Type :** double >=0
- **Défaut :** `3.0`
- **Catégorie :** Surface libre cinétique — enveloppe thermique
- **Statut :** paramètre env actif dans chaîne x10o/x12

Coefficient C_T du déplacement balistique thermique C_T*dt*sqrt(kBT/m).

**Remarques.** Coefficient de l'épaisseur balistique. La chaîne x12/JFM le verrouille à 3.0. Également utilisé dans les grandeurs x10w.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x10w` — Limiter thermique local pairwise
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `MPCD_X10P_INITIAL_OVERLAP_RESOLUTION`

- **Type :** booléen/env int
- **Défaut :** `1/on si x10o est actif`
- **Catégorie :** Surface libre cinétique — robustesse topologique
- **Statut :** robustesse active dans chaîne x12; ON

Active la résolution des particules déjà à l’extérieur de l’enveloppe au début d’un pas.

**Remarques.** Effectif seulement sous x10o. Requis par x10u. Le fallback x10q 7x7 est intégré en source et n'a pas de flag indépendant: il ne s'active que pour initial-overlap sans segment trouvé au 3x3.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10p` — Résolution des recouvrements initiaux
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x10u` — Relocalisation conservative one-for-one
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0

### `MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablation cinématique x10r
- **Statut :** implémentation retenue pour ablation; OFF chaîne x12 courante

Utilise la vitesse hydro Q6 vectorielle complète aux endpoints de la surface x10o.

**Remarques.** Effectif seulement sous x10o. Mutuellement exclusif avec x10s/x10t et incompatible avec le vrai Q2 x10biq. Rejeté de la chaîne production après qualification.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10biq` — Reconstruction Q2 biquadratique tensorielle
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10r` — Ablation vitesses endpoints full-vector
- `ASSOCIATED_WITH` → `x10s` — Ablation cinématique normale au segment
- `ASSOCIATED_WITH` → `x10t` — Ablation cinématique tangentielle rigide

### `MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablation cinématique x10s
- **Statut :** implémentation retenue pour ablation; OFF chaîne x12 courante

Projette la cinématique endpoint sur la normale du segment fini.

**Remarques.** Effectif seulement sous x10o. Mutuellement exclusif avec x10r/x10t et incompatible avec le vrai Q2 x10biq.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10biq` — Reconstruction Q2 biquadratique tensorielle
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10r` — Ablation vitesses endpoints full-vector
- `ASSOCIATED_WITH` → `x10s` — Ablation cinématique normale au segment
- `ASSOCIATED_WITH` → `x10t` — Ablation cinématique tangentielle rigide

### `MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS`

- **Type :** booléen/env int
- **Défaut :** `0/off`
- **Catégorie :** Surface libre cinétique — ablation cinématique x10t
- **Statut :** implémentation retenue pour ablation; OFF chaîne x12 courante

Active la variante de cinématique tangentielle rigide x10t.

**Remarques.** Effectif seulement sous x10o. Mutuellement exclusif avec x10r/x10s et incompatible avec le vrai Q2 x10biq.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10biq` — Reconstruction Q2 biquadratique tensorielle
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10r` — Ablation vitesses endpoints full-vector
- `ASSOCIATED_WITH` → `x10s` — Ablation cinématique normale au segment
- `ASSOCIATED_WITH` → `x10t` — Ablation cinématique tangentielle rigide

### `MPCD_X10W_THERMAL_PHASE_CHI_FULL`

- **Type :** double > chiOn
- **Défaut :** `0.028`
- **Catégorie :** Surface libre cinétique — seuil x10w
- **Statut :** paramètre de branche x10w; branche OFF production

Seuil supérieur chi du limiter x10w.

**Remarques.** Validé avec chiFull>chiOn. Lu même si le flag x10w est OFF lorsque le chemin cinétique s'exécute.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10w` — Limiter thermique local pairwise

### `MPCD_X10W_THERMAL_PHASE_CHI_ON`

- **Type :** double >0
- **Défaut :** `0.022`
- **Catégorie :** Surface libre cinétique — seuil x10w
- **Statut :** paramètre de branche x10w; branche OFF production

Seuil inférieur chi=delta_th/Lloc du limiter x10w.

**Remarques.** Les trois seuils x10w sont lus et validés dès que la fonction d'interface cinétique est exécutée, même si le limiter est OFF; fournir une valeur invalide peut donc arrêter un run avec réflexion cinétique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10w` — Limiter thermique local pairwise

### `MPCD_X10W_THERMAL_PHASE_ETA_CAP`

- **Type :** double >0
- **Défaut :** `0.05724334`
- **Catégorie :** Surface libre cinétique — seuil x10w
- **Statut :** paramètre de branche x10w; branche OFF production

Borne eta=(dt*sqrt(kBT/m))/h utilisée pour plafonner l'amplitude du limiter x10w.

**Remarques.** Tolérance de neutralité relative 1e-8 autour de etaCap. Lu/validé même si le limiter est OFF lorsque le chemin cinétique s'exécute.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10w` — Limiter thermique local pairwise

### `MPCD_X11C_FORCE_X9E_SIGMA0`

- **Type :** booléen/env truthy
- **Défaut :** `0/off`
- **Catégorie :** Validation capillaire x11 — diagnostics
- **Statut :** flag de runner x11c/x12yl; diagnostic uniquement; non lu directement par C++

Dans run_0493x9s_splash.sh, force MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1 pour les baselines sigma=0 appariées.

**Remarques.** Le C++ x11c construit p3 à la cadence x9e lorsque le diagnostic statique est demandé, même à sigma=0, mais le potentiel capillaire reste nul si sigma=0. x12yl utilise ce mécanisme pour la paire Young-Laplace.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12yl_young_laplace_calibrator.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `ASSOCIATED_WITH` → `x12yl` — Calibrateur mécanique/statique de tension superficielle
- `ASSOCIATED_WITH` → `x9e` — Qualification diagnostique de goutte statique
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `MPCD_X12A_LOCAL_THERMAL_COOLING`

- **Type :** booléen/env int
- **Défaut :** `0/off source; 1 dans x12 production`
- **Catégorie :** Surface libre cinétique — refroidissement local x12a
- **Statut :** actif dans chaîne x12 courante; ON | qualifié/tag 7655b81 au 31/08/2026

Active kBT_eff/kBT=min(1,(Lloc/Rc)^2) et réduit à la fois l'enveloppe thermique d'interface et la cible locale du thermostat.

**Remarques.** Requiert x10v + x10o + CIC + vrai Q2; mutuellement exclusif avec x10w. Ajoute un float/cellule persistant. Le champ fT est construit depuis l'épaisseur opposée et mappé au thermostat dans le dépôt de moments existant. | Audit final: présent au commit 7655b81; chaîne x13k/x13n revalidée. x10v est full-vector lorsque NORMAL_ONLY=0.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x13h.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x10w` — Limiter thermique local pairwise
- `ASSOCIATED_WITH` → `x12a` — Refroidissement thermique local des petites structures
- `ASSOCIATED_WITH` → `x13k` — Qualification goutte oscillante n=2
- `ASSOCIATED_WITH` → `x13n` — Benchmark Taylor–Culick 2-D

### `MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS`

- **Type :** double >0 lorsque x12a ON
- **Défaut :** `25.298221281347036 (=8*sqrt(10))`
- **Catégorie :** Surface libre cinétique — échelle x12a
- **Statut :** paramètre actif dans chaîne x12 courante | qualifié/tag 7655b81 au 31/08/2026

Rc/h dans la loi locale fT=min(1,(Lloc/Rc)^2).

**Remarques.** La courbure n'entre pas dans cette loi; Lloc est la demi-distance vers l'interface opposée le long de la normale Q2 intérieure. | Audit final: présent au commit 7655b81; chaîne x13k/x13n revalidée. x10v est full-vector lorsque NORMAL_ONLY=0.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x13h.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x12a` — Refroidissement thermique local des petites structures
- `ASSOCIATED_WITH` → `x13k` — Qualification goutte oscillante n=2
- `ASSOCIATED_WITH` → `x13n` — Benchmark Taylor–Culick 2-D

### `MPCD_X14L_GAS_SPECULAR_REFLECTION`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14
- **Statut :** ajout 0493x14l; actif dans la chaîne x14m+
- **Écrit / contrôle :** `phaseInterfaceKineticBilateralRelocation`

Active la réflexion spéculaire du gaz B sur la paroi cinétique liquide; composante normale relative réfléchie, tangentielle inchangée.

**Remarques.** Requiert phaseInterfaceKineticBilateralRelocation=true. Le liquide A conserve x10u; le chemin gaz préserve la vitesse spéculaire au lieu de la faire écraser par la relocalisation positionnelle.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_0493x14l_gas_specular_drop.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_0493x14w_two_phase_couette.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10u` — Relocalisation conservative one-for-one
- `ASSOCIATED_WITH` → `x14l` — Réflexion spéculaire du gaz
- `ASSOCIATED_WITH` → `x14m` — Assemblage bilatéral + compatibilité x12a

### `MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14ai-fix1 — fermeture conservative
- **Statut :** candidat production x14ai-fix1 pour composante liquide fermée/isolée; OFF par défaut

Utilise comme cible de résultante x14ad l’impulsion Q6 réellement appliquée par B1 après correction périodique: ΣmΔv_RT0 - M_active C_periodic.

**Remarques.** Requiert x14ad local-face + x10o/CIC et x14z=0. +16 octets persistants; aucun nouveau kernel/passe/CG/transfert D2H par pas. Ne pas utiliser sans qualification si le liquide touche une frontière Q6 externe.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x14ai_cost_ab.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x14ai_drag_device_closure.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x14ad` — Traction locale cohérente avec faces x6g
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14z` — Fermeture géométrique p_ref

### `MPCD_X14V_GAS_KINETIC_EXCESS_KICK`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14
- **Statut :** ajout 0493x14v; qualifié sur impact normal et actif dans x14w

Transfère collectivement au liquide l’impulsion normale réelle des réflexions gazeuses moins la traction thermodynamique déjà représentée par x6g.

**Remarques.** Requiert x6g actif, x10o+CIC+Q2+x10u+x10v, géométrie bilatérale et x14l. Réutilise les stockages x9t/x10m, aucun buffer résident permanent et aucune nouvelle passe O(Np); lois liquides inchangées.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_0493x14u_normal_kinetic_impact.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_0493x14w_two_phase_couette.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `ASSOCIATED_WITH` → `x10u` — Relocalisation conservative one-for-one
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector one-for-one
- `ASSOCIATED_WITH` → `x14l` — Réflexion spéculaire du gaz
- `ASSOCIATED_WITH` → `x14v` — Kick cinétique excédentaire
- `ASSOCIATED_WITH` → `x14w` — Couette biphasique
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `ASSOCIATED_WITH` → `x9t` — Première rétention cinétique liquide-vide conservative

### `MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14af — diagnostic
- **Statut :** diagnostic x14af uniquement; OFF production

Cumule les résultantes x14ad/x14v et Q6 nécessaires pour fermer le bilan global de quantité de mouvement.

**Remarques.** 11 doubles/88 octets; requiert x14ad et x14z=0. Le diagnostic a établi ΔP_tot=J_Q6(applied)-J_thermo(x14ad) au roundoff.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14ad` — Traction locale cohérente avec faces x6g
- `ASSOCIATED_WITH` → `x14af` — Diagnostic bilan global
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14v` — Kick cinétique excédentaire
- `ASSOCIATED_WITH` → `x14z` — Fermeture géométrique p_ref

### `MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14z — prototype de résultante
- **Statut :** prototype x14z rejeté; OFF production

Projette la contribution uniforme p_ref reconstruite sur la polyligne x10n vers une résultante globale nulle, sans modifier la partie de jauge.

**Remarques.** 24 octets de scratch, aucune nouvelle passe/kernel. N’explique pas le défaut n=1 observé; incompatible avec les modes x14aa–x14ad et requis OFF par x14ai.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x14aa` — Traction thermodynamique absolue sur faces x6g
- `ASSOCIATED_WITH` → `x14ad` — Traction locale cohérente avec faces x6g
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14z` — Fermeture géométrique p_ref

### `MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14ae — diagnostic
- **Statut :** diagnostic x14ae uniquement; OFF production

Cumule le nombre et l’impulsion des kicks x14v valides qui ne trouvent aucun support liquide après CIC puis fallback jusqu’au rayon 2.

**Remarques.** 3 doubles/24 octets; aucun changement de physique. Le cas discriminant a donné zéro perte terminale et a innocenté le scatter.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14ae` — Diagnostic pertes scatter
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14v` — Kick cinétique excédentaire

### `MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION`

- **Type :** booléen entier 0/1
- **Défaut :** `1`
- **Catégorie :** Interface liquide/gaz x14v — séparation thermo/cinétique
- **Statut :** ajout 0493x14y; production x14v/x14ai-fix1 = 1

Soustrait de l’impulsion brute de réflexion gazeuse la traction thermodynamique déjà représentée par x6g; à 0, x14v transfère J_raw sans soustraction.

**Remarques.** Le défaut 1 est la sémantique physique retenue. La valeur 0 est l’ablation x14y et n’est pas un mode de production.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14v` — Kick cinétique excédentaire
- `ASSOCIATED_WITH` → `x14y` — Ablation sans soustraction p_g
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_X14V_X6G_FACE_THERMO_TRACTION`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14aa — prototype de traction
- **Statut :** prototype x14aa non retenu; OFF production

Évalue toute la traction thermodynamique absolue sur les faces x6f/x6g représentées et la disperse vers le liquide via les buffers CIC x14v.

**Remarques.** Déplace aussi le grand terme uniforme p_ref de la géométrie x10n/CIC vers les faces Q6; mode mutuellement exclusif avec x14ab/x14ac/x14ad.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x14aa` — Traction thermodynamique absolue sur faces x6g
- `ASSOCIATED_WITH` → `x14ab` — p_ref sur x10n + jauge sur faces x6g
- `ASSOCIATED_WITH` → `x14ac` — Projection globale minimum-L2
- `ASSOCIATED_WITH` → `x14ad` — Traction locale cohérente avec faces x6g
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14v` — Kick cinétique excédentaire
- `ASSOCIATED_WITH` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14ab — prototype hybride
- **Statut :** prototype x14ab non retenu; OFF production

Conserve p_ref sur les segments x10n/CIC mais soustrait la seule pression de jauge p_g-p_ref sur les faces x6g représentées.

**Remarques.** Séparation référence/jauge plus cohérente que x14aa mais traction de jauge encore portée par les normales axiales des faces Q6; mode mutuellement exclusif avec x14aa/x14ac/x14ad.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x14aa` — Traction thermodynamique absolue sur faces x6g
- `ASSOCIATED_WITH` → `x14ab` — p_ref sur x10n + jauge sur faces x6g
- `ASSOCIATED_WITH` → `x14ac` — Projection globale minimum-L2
- `ASSOCIATED_WITH` → `x14ad` — Traction locale cohérente avec faces x6g
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14ac — projection de résultante
- **Statut :** prototype x14ac supplanté par x14ad; OFF production

Conserve la traction locale x10n et impose à sa pression de jauge la résultante globale des faces x6g par correction minimum-L2 delta p_s=m_s·lambda.

**Remarques.** Utilise un scratch de 7 doubles sans nouvelle passe. Le principe de projection est conservé dans x14ad, qui améliore l’association locale pression/segment.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x14ac` — Projection globale minimum-L2
- `ASSOCIATED_WITH` → `x14ad` — Traction locale cohérente avec faces x6g
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION`

- **Type :** booléen entier 0/1
- **Défaut :** `0`
- **Catégorie :** Interface liquide/gaz x14ad — traction locale retenue
- **Statut :** retenu x14ad; prérequis x14ai-fix1 pour composante liquide fermée

Échantillonne la pression de jauge sur les faces x6g qui terminent chaque segment x10n, applique cette pression sur la normale x10n, puis corrige la résultante résiduelle par projection minimum-L2.

**Remarques.** Réutilise le scratch 7 doubles x14ac et l’octet/cellule x10m pour les ids d’arêtes; aucune nouvelle passe/buffer O(N). Mutuellement exclusif avec x14aa/x14ab/x14ac. Doit être 1 lorsque x14ai est actif.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x14ai_drag_device_closure.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10m` — Paroi locale mobile alpha=0.5
- `ASSOCIATED_WITH` → `x10n` — Interface continue marching-squares mobile
- `ASSOCIATED_WITH` → `x14aa` — Traction thermodynamique absolue sur faces x6g
- `ASSOCIATED_WITH` → `x14ab` — p_ref sur x10n + jauge sur faces x6g
- `ASSOCIATED_WITH` → `x14ac` — Projection globale minimum-L2
- `ASSOCIATED_WITH` → `x14ad` — Traction locale cohérente avec faces x6g
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `NX`

- **Type :** entier >0
- **Défaut :** `64`
- **Catégorie :** Validateurs CUDA resampling — géométrie
- **Statut :** lecture C++ directe dans validateurs shadow; également variable shell courante des runners
- **Écrit / contrôle :** `Nx`

Nombre de cellules x des exécutables de validation CUDA resampling shadow.

**Remarques.** La lecture getenv directe identifiée dans le C++ est limitée aux exécutables de validation CUDA resampling shadow. Le même nom est aussi utilisé comme variable shell par de nombreux runners qui l'écrivent ensuite dans les paramètres; ne pas le confondre avec un getenv du binaire de production.

### `NY`

- **Type :** entier >0
- **Défaut :** `32`
- **Catégorie :** Validateurs CUDA resampling — géométrie
- **Statut :** lecture C++ directe dans validateurs shadow; également variable shell courante des runners
- **Écrit / contrôle :** `Ny`

Nombre de cellules y des exécutables de validation CUDA resampling shadow.

**Remarques.** La lecture getenv directe identifiée dans le C++ est limitée aux exécutables de validation CUDA resampling shadow. Le même nom est aussi utilisé comme variable shell par de nombreux runners qui l'écrivent ensuite dans les paramètres; ne pas le confondre avec un getenv du binaire de production.

### `OMP_DYNAMIC`

- **Type :** booléen OpenMP
- **Défaut :** `false`
- **Catégorie :** OpenMP runtime
- **Statut :** documenté 0426

Autorise ou non l’ajustement dynamique du nombre de threads OpenMP.

**Remarques.** Désactivé par les scripts pour garder des timings reproductibles.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OMP_NUM_THREADS`

- **Type :** entier positif
- **Défaut :** `THREADS du script`
- **Catégorie :** OpenMP runtime
- **Statut :** documenté 0426

Nombre de threads OpenMP utilisés par le binaire hôte et certaines phases CPU.

**Remarques.** Les scripts Darcy exportent explicitement OMP_NUM_THREADS pour reproductibilité.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OMP_PLACES`

- **Type :** chaîne OpenMP
- **Défaut :** `cores`
- **Catégorie :** OpenMP runtime
- **Statut :** documenté 0426

Ensemble de lieux de placement OpenMP.

**Remarques.** Exporté par les scripts de démonstration pour stabiliser les mesures.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OMP_PROC_BIND`

- **Type :** chaîne OpenMP
- **Défaut :** `close`
- **Catégorie :** OpenMP runtime
- **Statut :** documenté 0426

Politique de liaison des threads OpenMP.

**Remarques.** Exporté par les scripts de démonstration pour réduire les variations de runtime.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OUT_CSV`

- **Type :** chemin de fichier CSV
- **Défaut :** `nom propre au validateur`
- **Catégorie :** Validateurs CUDA resampling — sortie
- **Statut :** présent code; ajouté consolidation 0493w8

Impose le chemin du CSV produit par plusieurs binaires de validation du resampling CUDA.

**Remarques.** Variable de validateur, pas une option du solveur de production et ne se place pas dans params.kv.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_guard_0227.cpp`
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_particle_select_0232.cpp`
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_plan_0228.cpp`
- `DEFINED_OR_USED_IN` — `src/main_validate_cuda_resampling_shadow_transfer_0233.cpp`

### `OUTLET_FACE`

- **Type :** double/chaîne selon variable
- **Défaut :** `right`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Face portant le segment outlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OUTLET_FORCED_LAYER_CELLS`

- **Type :** entier
- **Défaut :** `3 dans la démo boîte; défaut noyau 1`
- **Catégorie :** Scripts démo 0283/0291 — inlet/outlet
- **Statut :** contrôle utilisateur script
- **Écrit / contrôle :** `openBoundaryOutletForcedLayerCells`

Écrit openBoundaryOutletForcedLayerCells dans params.kv.

**Remarques.** Épaisseur de la couche outlet utilisée pour forced_flux/equilibrium_flux.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291_EXPLICIT_OUTLET_REGIMES.md`

### `OUTLET_FORCED_MASS_FLUX`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Scripts démo 0283/0291 — inlet/outlet
- **Statut :** contrôle utilisateur script
- **Écrit / contrôle :** `openBoundaryOutletForcedMassFlux`

Écrit openBoundaryOutletForcedMassFlux dans params.kv.

**Remarques.** Utilisé avec OUTLET_MODE=forced_flux; extraction découplée de l’inlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291_EXPLICIT_OUTLET_REGIMES.md`

### `OUTLET_FORCED_MASS_PER_STEP`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Scripts démo 0283/0291 — inlet/outlet
- **Statut :** contrôle utilisateur script
- **Écrit / contrôle :** `openBoundaryOutletForcedMassPerStep`

Écrit openBoundaryOutletForcedMassPerStep dans params.kv.

**Remarques.** Prioritaire sur le flux massique par temps si positif; les paramètres particulaires restent prioritaires sur la masse.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291_EXPLICIT_OUTLET_REGIMES.md`

### `OUTLET_FORCED_PARTICLE_FLUX`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Scripts démo 0283/0291 — inlet/outlet
- **Statut :** contrôle utilisateur script
- **Écrit / contrôle :** `openBoundaryOutletForcedParticleFlux`

Écrit openBoundaryOutletForcedParticleFlux dans params.kv.

**Remarques.** Utilisé avec OUTLET_MODE=forced_flux; les flux particulaires sont prioritaires sur les flux massiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291_EXPLICIT_OUTLET_REGIMES.md`

### `OUTLET_FORCED_PARTICLES_PER_STEP`

- **Type :** entier
- **Défaut :** `0`
- **Catégorie :** Scripts démo 0283/0291 — inlet/outlet
- **Statut :** contrôle utilisateur script
- **Écrit / contrôle :** `openBoundaryOutletForcedParticlesPerStep`

Écrit openBoundaryOutletForcedParticlesPerStep dans params.kv.

**Remarques.** Paramètre simple pour régler une extraction forcée indépendante de l’inlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291_EXPLICIT_OUTLET_REGIMES.md`

### `OUTLET_MODE`

- **Type :** double/chaîne selon variable | string
- **Défaut :** `hybrid/neumann selon script | neumann dans scripts mis à jour`
- **Catégorie :** Alias script géométrie/segments Darcy | Scripts démo 0283/0291 — inlet/outlet
- **Statut :** ajout/documenté 0426 | contrôle utilisateur script
- **Écrit / contrôle :** `openBoundaryOutletMode`

Mode de sortie ouvert écrit vers openBoundaryOutletMode. | Écrit openBoundaryOutletMode dans params.kv pour les démos inlet/outlet.

**Remarques.** Valeurs utiles: neumann, equilibrium_flux, forced_flux. Paramètre script, pas lu directement par le noyau C++ si absent du .kv.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291_EXPLICIT_OUTLET_REGIMES.md`
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OUTLET_SMAX`

- **Type :** double/chaîne selon variable
- **Défaut :** `1.0 ou 0.25 selon script`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Coordonnée relative maximale du segment outlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OUTLET_SMIN`

- **Type :** double/chaîne selon variable
- **Défaut :** `0.0`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Coordonnée relative minimale du segment outlet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `PARTICLE_TYPE_FILTER`

- **Type :** entier
- **Défaut :** `-1`
- **Catégorie :** Alias script livevis / filtrage type 0436 | Alias script livevis / particle type filter 0436
- **Statut :** ajout runner 0436

Override de script qui patche livevis_control.kv et exporte les variables runtime pour forcer le filtre dans les runs 0434. | Alias de script pour patcher livevis_control.kv:particleTypeFilter et exporter SRC/MPCD_LIVE_VIS_PARTICLE_TYPE_FILTER.

**Remarques.** Utilisé dans la suite injection_type1_into_type2 pour générer des runs total/type1/type2 comparables. | Utilisé dans run_0434_injection_type1_into_type2.sh pour générer des runs total/type1/type2 sans modifier le solveur.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0434_injection_type1_into_type2.sh`

### `PHASE_INTERFACE_KINETIC_BILATERAL_RELOCATION`

- **Type :** booléen
- **Défaut :** `true dans les runners liquide/gaz x14k+`
- **Catégorie :** Runner x14 — interface
- **Statut :** alias conceptuel / écriture params x14k
- **Écrit / contrôle :** `phaseInterfaceKineticBilateralRelocation`

Écrit phaseInterfaceKineticBilateralRelocation=true dans params.kv.

**Remarques.** La plupart des runners x14 écrivent directement la clé params plutôt que de dépendre de cet alias.

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14k` — Géométrie cinétique bilatérale

### `POSTCHECK_SPECIES_ENABLE`

- **Type :** booléen
- **Défaut :** `true`
- **Catégorie :** Alias runner / validation injection
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `speciesDiagnosticsEnable`

Active le checker runtime par espèce après le run.

**Remarques.** Exige speciesDiagnosticsEnable=true.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `PREFLIGHT_ONLY`

- **Type :** booléen/int | booléen
- **Défaut :** `0`
- **Catégorie :** Alias runner / validation | Runner qualification 0493x7i / préflight
- **Statut :** ajout/normalisé 0493w4–0493w8 | profil final x7q/x7i

Génère et valide les six branches sans exécuter les pas physiques. | Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `PROJECTION_MOMENTUM_CORRECTION_ENABLE`

- **Type :** booléen
- **Défaut :** `false dans 0493w8`
- **Catégorie :** Alias runner / projection Q6
- **Statut :** documenté 0493w8
- **Écrit / contrôle :** `projectionMomentumCorrectionEnable`

Écrit projectionMomentumCorrectionEnable dans params.kv.

**Remarques.** Désactivé dans les branches Q6 historique et independent_masked afin de comparer le même opérateur sans patch uniforme de moment.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W8_TG_MONO_DUAL_IDENTICAL_EQUIVALENCE.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`

### `PROJECTION_TOLERANCE`

- **Type :** double >0
- **Défaut :** `1.0e-5 dans la qualification finale`
- **Catégorie :** Alias script projection Q6
- **Statut :** documenté x5b–x6g; profil de qualification final x7q/x7i
- **Écrit / contrôle :** `projectionTolerance`

Alias shell écrit projectionTolerance dans params.kv généré.

**Remarques.** Le défaut C++ reste 1e-10. La campagne finale TG/Poiseuille/bend/io utilise 1e-5; le dam-break Q6-g-f est également qualifié à 1e-5.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_dambreak.sh`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x5b` — Qualification liquide-gaz : Q6-g liquide et gaz compressible explicite
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `PUDDLE_DEPTH_CELLS`

- **Type :** double >=0
- **Défaut :** `40`
- **Catégorie :** Alias runner — splash x9s
- **Statut :** ajout 0493x9s

Profondeur de la flaque liquide initiale pour TARGET=puddle.

**Remarques.** Sans effet pour TARGET=wall.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/generate_0493x9s_splash_state.py`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `Q6_DENSITY_RELAXATION_BETA`

- **Type :** double [0,1]
- **Défaut :** `0.0`
- **Catégorie :** Alias runner Q6-g-f / restauration de densité
- **Statut :** ajout runner 0493x7c; conservé 0493x7d/x7e
- **Écrit / contrôle :** `q6DensityRelaxationBeta`

Alias shell écrit q6DensityRelaxationBeta dans params.kv.

**Remarques.** Entrée par pas legacy. Dans les qualifications x7d/x7e elle est mise à 0 lorsque Q6_DENSITY_RELAXATION_TIME est utilisée.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X7C_Q6_DENSITY_RELAXATION_RHS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5a_partial_liquid_free_surface.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7c` — Restauration de densité intégrée au RHS Q6
- `ASSOCIATED_WITH` → `x7d` — Constante de temps physique de restauration de densité
- `ASSOCIATED_WITH` → `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d

### `Q6_DENSITY_RELAXATION_TIME`

- **Type :** double >=0
- **Défaut :** `0.0 runner historique; tau=0.25 dans la chaîne qualifiée`
- **Catégorie :** Alias runner historique Q6-g-f / restauration de densité
- **Statut :** ajout 0493x7d; remplacé dans le helper commun par profil Q6_GF; valeur physique toujours qualifiée x7q
- **Écrit / contrôle :** `q6DensityRelaxationTime`

Alias shell historique écrivant q6DensityRelaxationTime dans params.kv.

**Remarques.** Conservé pour compatibilité des anciens runners. La chaîne run_ok/x7i utilise Q6_GF_DENSITY_RELAXATION_TIME=0.25.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5a_partial_liquid_free_surface.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d` — Constante de temps physique de restauration de densité
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_FORCE_PROJECTION_MODE`

- **Type :** enum string
- **Défaut :** `selon runner; prestream_single_fused dans les runners surface libre`
- **Catégorie :** Alias script 0493x force-aware
- **Statut :** ajout runners 0493x3–0493x5; réutilisé Q6-g-f jusqu’à x7e
- **Écrit / contrôle :** `q6ForceProjectionMode`

Alias shell écrit q6ForceProjectionMode dans le fichier params.kv généré.

**Remarques.** Ce n’est pas un getenv du backend; la valeur canonique reste q6ForceProjectionMode. prestream_single_fused est le séquencement Q6-g-f qualifié.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x3_q6_force_projection_tg.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x4a_q6_force_single_tg.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x4b_q6_force_fusion_tg.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5a_partial_liquid_free_surface.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x3` — Q6-g force-aware — preuve de concept prestream à deux solves
- `ASSOCIATED_WITH` → `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d

### `Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE`

- **Type :** booléen
- **Défaut :** `0 helper générique; 1 profil x7i`
- **Catégorie :** Alias run_ok Q6-g-f / densité signée
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Active le gate cohérent de compression dans params.kv.

**Remarques.** La chaîne qualifiée x7q/x7i impose 1.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d-v2` — Gate cohérent de compression pour la restauration de densité
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES`

- **Type :** double >=0
- **Défaut :** `3.0`
- **Catégorie :** Alias run_ok Q6-g-f / densité signée
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Convertit le seuil de compression exprimé en nombre de particules en fraction via gamma.

**Remarques.** Donne 0.15 à gamma=20 et 0.30 à gamma=10.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d-v2` — Gate cohérent de compression pour la restauration de densité
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_DENSITY_RELAXATION_TIME`

- **Type :** double >=0
- **Défaut :** `0.25`
- **Catégorie :** Alias run_ok Q6-g-f / densité
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i
- **Écrit / contrôle :** `q6DensityRelaxationTime`

Écrit q6DensityRelaxationTime; constante de temps physique de restauration.

**Remarques.** Profil générique actuel et qualification signed1/x7q.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_DENSITY_TRACTION_GAIN`

- **Type :** double >=0
- **Défaut :** `0.0 helper générique; 1.0 profil x7i`
- **Catégorie :** Alias run_ok Q6-g-f / densité signée
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i
- **Écrit / contrôle :** `q6DensityRelaxationTractionGain`

Écrit q6DensityRelaxationTractionGain.

**Remarques.** La chaîne signed1 qualifiée utilise 1.0; 0 désactive exactement la branche négative.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d-v2-signed1` — Restauration de densité signée à gates cohérents
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES`

- **Type :** double >=0
- **Défaut :** `6.0`
- **Catégorie :** Alias run_ok Q6-g-f / densité signée
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Convertit le seuil de traction/déplétion exprimé en particules en fraction via gamma.

**Remarques.** Donne 0.30 à gamma=20 et 0.60 à gamma=10.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d-v2-signed1` — Restauration de densité signée à gates cohérents
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_EXTERNAL_SPECIES`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Alias run_ok Q6-g-f / registre espèces
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Demande au helper de conserver un registre d’espèces fourni par le cas au lieu de synthétiser une espèce.

**Remarques.** Utilisé par les cas explicitement multi-espèces.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_GAS_PRESSURE_REFERENCE`

- **Type :** double >=0
- **Défaut :** `gamma*kBT/cellArea si non fourni`
- **Catégorie :** Alias run_ok Q6-g-f / pression gazeuse
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Override la pression EOS de référence gaz utilisée par le helper lorsqu’une phase gazeuse Q6-g-f est déclarée.

**Remarques.** Si Q6_GF_HAS_GAS_PHASE=1, alimente les réglages x6g REFERENCE et CONSTANT; sinon sans effet.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_HAS_GAS_PHASE`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Alias run_ok Q6-g-f / registre phases
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Déclare au helper qu’une phase gaz est présente et active la configuration x6g/x7m correspondante.

**Remarques.** 0 sur monophase TG/Poiseuille; 1 sur dam-break liquide+gaz.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7m` — Garde topologique monophase par registre de phases
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_MIN_FILL_FRACTION`

- **Type :** double [0,1]
- **Défaut :** `0.10`
- **Catégorie :** Alias run_ok Q6-g-f / support
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i
- **Écrit / contrôle :** `speciesQ6MinOccupancyFraction`

Écrit speciesQ6MinOccupancyFraction pour free_surface_masked.

**Remarques.** Seuil de support numérique, distinct de l’interface alpha=0.5.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_SINGLE_PHASE_PARTICLE_MASS`

- **Type :** double >0
- **Défaut :** `PARTICLE_MASS`
- **Catégorie :** Alias run_ok Q6-g-f / espèce monophase
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Masse déclarée de l’espèce synthétisée.

**Remarques.** Variable de script; pas un getenv backend.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_SINGLE_PHASE_TYPE`

- **Type :** entier type
- **Défaut :** `BACKGROUND_TYPE ou 0`
- **Catégorie :** Alias run_ok Q6-g-f / espèce monophase
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Type de l’espèce synthétisée par le helper monophase.

**Remarques.** Variable de script; pas un getenv backend.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_GF_SPECIES_DIAGNOSTICS_ENABLE`

- **Type :** booléen texte
- **Défaut :** `false`
- **Catégorie :** Alias run_ok Q6-g-f / diagnostics espèces
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i
- **Écrit / contrôle :** `speciesDiagnosticsEnable`

Écrit speciesDiagnosticsEnable pour le registre Q6-g-f synthétisé.

**Remarques.** Diagnostic opt-in; la production évite la télémétrie lourde.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `Q6_PRESSURE_OUTLET_DEFLATION_ENABLE`

- **Type :** booléen
- **Défaut :** `true`
- **Catégorie :** Runner 0414 / x8s ablation
- **Statut :** ajout 0414d
- **Écrit / contrôle :** `q6PressureOutletDeflationEnable`

Runner alias writing q6PressureOutletDeflationEnable.

**Remarques.** Qualification conditioning-only ablation.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0414_segmented_xy_neumann_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x8s` — Déflation exacte des modes longitudinaux lents du CG

### `QUAL_MODES`

- **Type :** liste/chaîne
- **Défaut :** `src src-q6 src-q6-g-f`
- **Catégorie :** Runner qualification 0493x7i / sélection de modes
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `RECORD_FIELDS`

- **Type :** liste CSV de champs
- **Défaut :** `rho,ux,uy dans les profils 0434 récents | rho,ux,uy dans les profils récents`
- **Catégorie :** Alias script filtered recording 0434/0436
- **Statut :** documenté 0436

Sélectionne les champs enregistrés par les dumps filtrés .f32. | Alias de script pour choisir les champs dumpés par filtered_field_recorder_0432.

**Remarques.** Pour les comparaisons type1/type2/total, utiliser au minimum rho,ux,uy; particleTypeFilter est tracé dans manifest.kv. | À utiliser avec PARTICLE_TYPE_FILTER pour produire les comparaisons total/type1/type2.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`

### `REQUIRE_MIXED_CELL_AT_END`

- **Type :** booléen
- **Défaut :** `false`
- **Catégorie :** Alias runner / validation injection
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `speciesCellDiagnosticsEnable`

Exige au moins une cellule contenant les deux types à la fin.

**Remarques.** Exige speciesCellDiagnosticsEnable=true.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `REQUIRE_VALIDATED_SEGMENTED_RESIDENT`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Alias script sécurité CUDA
- **Statut :** ajout/documenté 0426

Force le strict mode du chemin segmented resident 0264.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `RUN_MODES`

- **Type :** liste de modes: src; src-q6; src-resampling; src-q6-resampling
- **Défaut :** `dépend du runner; src src-q6 pour les comparaisons injection/TG`
- **Catégorie :** Alias script / cas de run
- **Statut :** existant; utilisé scripts portables

Choisit les branches d’ablation SRC, Q6 et resampling exécutées par les runners.

**Remarques.** 0493w4–0493w8: Q6 et resampling restent deux axes indépendants; la qualification Q6 initiale garde le resampling désactivé.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `RUN_OK_DARCY_COMMON_FILLED_STATE`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Alias run_ok Darcy / qualification
- **Statut :** documenté helper commun 0493x7h; profil final x7q/x7i

Force un état initial rempli commun pour comparer les modes sur les cas Darcy.

**Remarques.** x7i bend-pipe l’active afin d’isoler la réponse dynamique de la méthode.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `ASSOCIATED_WITH` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `RUN_ROOT`

- **Type :** chaîne chemin
- **Défaut :** `runs/0493x7q_q6_g_f_physical_qualification`
- **Catégorie :** Runner qualification 0493x7i / racine de sortie
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `RUN_ZERO_REFERENCE`

- **Type :** booléen/int 0|1
- **Défaut :** `1`
- **Catégorie :** Alias script 0493x6g final
- **Statut :** ajout runner 0493x6g

Contrôle l’exécution de la référence appariée pGamma=0 dans le runner dam-break final.

**Remarques.** Mettre 0 pour relancer seulement le cas EOS, notamment lors d’une inspection LiveVis après qu’une référence existe déjà.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x6g_final_dam_break.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `SCENARIO_EXPECTATION`

- **Type :** empty|two_species
- **Défaut :** `cohérent avec INITIAL_DOMAIN_MODE`
- **Catégorie :** Alias runner / validation injection
- **Statut :** ajout/normalisé 0493w4–0493w8

Sélectionne le contrat du checker d’état et de diagnostic par espèce.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/check_injection_species_0492b.py`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `SCENARIOS`

- **Type :** liste de noms
- **Défaut :** `mono_legacy mono_independent dual_identical`
- **Catégorie :** Alias runner / matrice TG
- **Statut :** ajout/normalisé 0493w4–0493w8

Sélectionne les scénarios de qualification TG.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`

### `SEED`

- **Type :** uint64
- **Défaut :** `1628638`
- **Catégorie :** Validateurs CUDA resampling — reproductibilité
- **Statut :** lecture C++ directe dans validateurs shadow; également variable shell courante des runners

Seed des exécutables de validation CUDA resampling shadow.

**Remarques.** La lecture getenv directe identifiée dans le C++ est limitée aux exécutables de validation CUDA resampling shadow. Le même nom est aussi utilisé comme variable shell par de nombreux runners qui l'écrivent ensuite dans les paramètres; ne pas le confondre avec un getenv du binaire de production.

### `SEEDS`

- **Type :** liste d’entiers
- **Défaut :** `493801`
- **Catégorie :** Alias runner / ensemble statistique
- **Statut :** ajout/normalisé 0493w4–0493w8

Liste des graines TG à exécuter ou analyser.

**Remarques.** Qualification finale: 493801 493802 493803.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`

### `SIGMA_ACTIVE`

- **Type :** double >=0
- **Défaut :** `dépend du runner; x12b/x12c/x12d JFM: 392.149185; x12a splash: campagne-dépendant`
- **Catégorie :** Alias runner — tension superficielle
- **Statut :** runner alias courant; x12 splash/JFM
- **Écrit / contrôle :** `surfaceTensionSigma`

Surcharge surfaceTensionSigma dans les runners capillaires/splash/JFM.

**Remarques.** Alias de runner, pas un champ C++ autonome. Dans le cas JFM x12d, la valeur par défaut est 392.149185 (campagne We≈514). Les calibrateurs x12cal/x12yl utilisent plutôt SIGMA_DECLARED et écrivent surfaceTensionSigma.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12b_obstacle_JFM_D320_Re649_We514.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12c_obstacle_JFM_D320_Re649_We514_compactY.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `ASSOCIATED_WITH` → `x12cal` — Calibrateur dynamique de tension superficielle
- `ASSOCIATED_WITH` → `x12d` — Cas de mesure JFM 524 à géométrie/We/Fr ciblés
- `ASSOCIATED_WITH` → `x12yl` — Calibrateur mécanique/statique de tension superficielle

### `SPECIES_Q6_COMPARISON_TOLERANCE`

- **Type :** double >0
- **Défaut :** `1.0e-11`
- **Catégorie :** Alias runner / Q6 multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `speciesQ6ComparisonTolerance`

Écrit speciesQ6ComparisonTolerance.

**Remarques.** Tolérance de qualification; ne modifie pas la physique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `SPECIES_Q6_ENABLE`

- **Type :** booléen
- **Défaut :** `true dans le runner injection; selon scénario TG`
- **Catégorie :** Alias runner / Q6 multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `projectionEnable`, `speciesQ6Enable`

Active speciesQ6Enable dans params.kv pour les modes contenant Q6.

**Remarques.** N’active pas projectionEnable à lui seul.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `SPECIES_Q6_FALLBACK_MODE`

- **Type :** common|fatal
- **Défaut :** `common`
- **Catégorie :** Alias runner / Q6 multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `speciesQ6FallbackMode`

Écrit speciesQ6FallbackMode.

**Remarques.** Legacy weighted uniquement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `SPECIES_Q6_MIN_FILL_FRACTION`

- **Type :** double [0,1]
- **Défaut :** `0.25 dans les premiers runners x5/x6; 0.10 dans les qualifications Q6-g-f x7d/x7e`
- **Catégorie :** Alias script 0493x surface libre
- **Statut :** ajout runner 0493x5a; réutilisé x5b–x7e
- **Écrit / contrôle :** `speciesQ6MinOccupancyFraction`

Alias shell écrit speciesQ6MinOccupancyFraction dans params.kv.

**Remarques.** Alias shell écrit speciesQ6MinOccupancyFraction dans params.kv. Pour free_surface_masked, seuil de support absolu liquide; distinct de l’interface physique alpha=0.5.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5a_partial_liquid_free_surface.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli
- `ASSOCIATED_WITH` → `x5b` — Qualification liquide-gaz : Q6-g liquide et gaz compressible explicite
- `ASSOCIATED_WITH` → `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d

### `SPECIES_Q6_MIN_OCCUPANCY_FRACTION`

- **Type :** double dans [0,1]
- **Défaut :** `0.5 injection/smokes; 0.0 dual_identical`
- **Catégorie :** Alias runner / Q6 multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `speciesQ6MinOccupancyFraction`

Écrit speciesQ6MinOccupancyFraction.

**Remarques.** Le seuil 0.5 est un défaut de test; 0.0 projette chaque type partout où sa masse locale est positive.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w5_independent_masked_periodic_smoke.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `SPECIES_Q6_MODE`

- **Type :** common|weighted|independent_masked
- **Défaut :** `weighted dans le runner partagé historique; independent_masked par override/qualification`
- **Catégorie :** Alias runner / Q6 multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `speciesQ6Mode`

Écrit speciesQ6Mode dans params.kv.

**Remarques.** Utiliser independent_masked pour liquide incompressible/gaz compressible; weighted reste reproductible.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493w5_independent_masked_periodic_smoke.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493w8_tg_mono_dual_equivalence.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `SPECIES_Q6_SENSITIVITY`

- **Type :** double dans [0,1]
- **Défaut :** `1.0 dans le runner injection`
- **Catégorie :** Alias runner / Q6 multi-espèces
- **Statut :** ajout/normalisé 0493w4–0493w8
- **Écrit / contrôle :** `speciesQ6Sensitivity`

Écrit speciesQ6Sensitivity.

**Remarques.** Pertinent pour weighted, sans effet sur independent_masked.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_injection_type1_into_type2_empty.sh`

### `SPECIES_THERMOSTAT_ENABLE`

- **Type :** booléen 0/1 ou true/false
- **Défaut :** `1 dans les runners biphasés x14`
- **Catégorie :** Runner x14 — thermostat
- **Statut :** alias de runner x14
- **Écrit / contrôle :** `speciesThermostatEnable`

Écrit speciesThermostatEnable dans params.kv.

**Remarques.** Alias de script; la physique canonique est le paramètre params.kv speciesThermostatEnable.

### `SRC_FILTERED_FIELD_RECORD_EVERY`

- **Type :** entier > 0 si présent
- **Défaut :** `absent par défaut; sinon override explicite`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a | mis à jour 0433a

Override expert de la cadence d’écriture des dumps filtrés. Si absent, recordEvery suit liveEvery.

**Remarques.** 0433a: n’est plus nécessaire pour obtenir une cadence d’enregistrement; le comportement par défaut est WYSIWYR avec recordEvery=liveEvery. Une valeur env >0 force recordEverySource=override.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_FILTERED_FIELD_RECORD_FIELDS`

- **Type :** liste CSV de champs
- **Défaut :** `current`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Initialise la liste des champs à enregistrer.

**Remarques.** Exemples: current,ux,uy,rho,Y1. La clé control-file recordFields peut surcharger avant session.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_FILTERED_FIELD_RECORDING_0432`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Alias SRC_* pour activer le recorder observation-only de champs filtrés.

**Remarques.** Même rôle que MPCD_FILTERED_FIELD_RECORDING_0432; utile dans les scripts livevis SRC.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_FILTERED_FIELD_SAMPLE_EVERY`

- **Type :** entier >= 1
- **Défaut :** `1`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Initialise la cadence d’échantillonnage du recorder.

**Remarques.** Cadence de sample des champs conservatifs; la clé control-file filterSampleEvery peut surcharger.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_FILTERED_FIELD_TAU`

- **Type :** double >= 0
- **Défaut :** `0.0`
- **Catégorie :** Filtered field recording 0432a
- **Statut :** ajout 0432a

Initialise filterTau du recorder avant éventuelle surcharge par livevis_control.kv.

**Remarques.** tau=0 désactive l’EMA; la clé control-file filterTau a priorité lors des reloads.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0432A_FILTERED_FIELD_RECORDING_STRICT.md`
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330`

- **Type :** booléen/env truthy
- **Défaut :** `0 dans validations sûres`
- **Catégorie :** Diagnostics rapides immersed circle CUDA
- **Statut :** utilisé validations 0331+

Contrôle côté script les diagnostics rapides du cylindre.

**Remarques.** À 0 pour valider les hits cylindre complets; à 1 pour réduire le coût diagnostic si disponible.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_immersed_circle_0284.cu`

### `SRC_GPU_WALL_CIRCLE_RESIDENT_0318`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Alias script / sécurité VK
- **Statut :** ajout scripts 0331

Alias de script pour documenter/désactiver le chemin 0318.

**Remarques.** Ne remplace pas le garde UNSAFE. Préférer MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=0 dans les scripts. | 0338c: le chemin performant validé est 0318 + MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_MINIMAL_DOWNLOAD_0338=1; 0318 seul reste à traiter comme chemin historique/quarantainé selon scripts.

### `SRC_GPU_WALL_FAST_DIAG_0320`

- **Type :** booléen/env truthy
- **Défaut :** `0 dans validations sûres`
- **Catégorie :** Diagnostics rapides wall CUDA
- **Statut :** utilisé validations 0331+

Contrôle côté script les diagnostics rapides wall.

**Remarques.** Désactivé dans les oracles lorsque l’on veut des hits complets. Peut être activé pour réduire les retours diagnostics.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_streaming_wall_simple_0246.cu`

### `SRC_LIVE_VIS_ALPHA`

- **Type :** double [0,1]
- **Défaut :** `0.08 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c | précisé 0436b

Lissage temporel du rendu CPU fallback.

**Remarques.** Le chemin CUDA field rend directement une image compacte; alpha est surtout utile au fallback CPU. | 0436b: persistance temporelle du champ affiché; alpha=1.0 donne un affichage immédiat. Le changement de field/particleTypeFilter doit réinitialiser displayScalar une frame, puis reprendre le lissage.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_CLIP`

- **Type :** double; <=0 auto
- **Défaut :** `-1 auto`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c

Échelle de saturation/clip couleur.

**Remarques.** Valeur fixe utile pour comparer plusieurs runs; auto utile pour inspection rapide. | 0341a: valeur initiale seulement; peut être modifiée à chaud via livevis_control.kv si SRC_LIVE_VIS_CONTROL_FILE est défini.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_COLORMAP`

- **Type :** enum: blue_red | gray | thermal
- **Défaut :** `blue_red`
- **Catégorie :** Live visualization colormap
- **Statut :** ajout 0342a

Colormap consommé par le renderer livevis, y compris le chemin CUDA field 0337.

**Remarques.** Mis à jour dans le processus lors de la relecture de livevis_control.kv lorsque la clé colormap change. Alias acceptés: grey/grayscale/greyscale -> gray; heat/hot -> thermal.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_colormap_control_0342a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_CONTROL_EVERY`

- **Type :** entier >= 1
- **Défaut :** `1`
- **Catégorie :** Live visualization runtime control
- **Statut :** ajout 0341a

Stride de relecture du fichier de contrôle sur les opportunités d’affichage livevis.

**Remarques.** Avec LIVE_VIS_EVERY=25 et CONTROL_EVERY=1, le fichier est relu à chaque frame livevis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_CONTROL_FILE`

- **Type :** chemin fichier .kv
- **Défaut :** `vide/off si non fourni`
- **Catégorie :** Live visualization runtime control
- **Statut :** ajout 0341a; propagé scripts 0341b/0341d

Chemin du fichier livevis_control.kv relu à chaud par le binaire pour modifier field/clip/gain/smoothPasses/colormap sans redémarrage.

**Remarques.** Le chemin recommandé est fourni par les scripts depuis LIVE_VIS_CONTROL_FILE_EFFECTIVE. Les logs de reload sont écrits dans le fichier .time.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341b_scripts.md`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_CONTROL_LOG`

- **Type :** booléen/env truthy
- **Défaut :** `1 dans scripts 0341b/0341d`
- **Catégorie :** Live visualization runtime control
- **Statut :** ajout 0341a

Active les lignes de diagnostic [livevis0335] control reload dans stderr/.time.

**Remarques.** Très utile pour vérifier que le fichier est bien relu et que field/clip/gain/smoothPasses/colormap changent.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_CUDA_FIELD`

- **Type :** booléen/env truthy
- **Défaut :** `0 code; 1 scripts 0337`
- **Catégorie :** Live visualization CUDA field renderer
- **Statut :** ajout 0337a

Active le rendu de champ sur GPU avec téléchargement RGBA compact.

**Remarques.** Chemin recommandé pour visualiser resampling sans host mirror lent. Transfert typique 300×80×4 octets/frame. | 0342a: le chemin CUDA field utilise désormais SRC_LIVE_VIS_COLORMAP pour la projection scalaire -> RGBA.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_CUDA_SNAPSHOT`

- **Type :** booléen/env truthy
- **Défaut :** `0`
- **Catégorie :** Live visualization snapshot expérimental
- **Statut :** ajout 0336a; gardé expérimental

Tente un snapshot compact des particules depuis l’état CUDA partagé.

**Remarques.** Non fiable après resampling dans les tests 0336a; ne pas utiliser par défaut.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_livevis_cuda_field_0337a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_shared_particle_state_0251.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_ENABLE`

- **Type :** booléen/env truthy
- **Défaut :** `false/off; 1 dans scripts livevis 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335

Active la fenêtre livevis au runtime.

**Remarques.** N’affecte pas les builds/runs production si absent. Les scripts 0337 livevis l’activent par défaut.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_live_visualization_0335a.md`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_EVERY`

- **Type :** entier > 0
- **Défaut :** `10 code; 20 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335 | mis à jour 0339a | mis à jour 0433a

Initialise la cadence livevis au démarrage; depuis 0433a cette cadence peut être modifiée à chaud par livevis_control.kv:liveEvery/every/visualEvery.

**Remarques.** Augmenter pour réduire le coût d’affichage. | 0339a: export effectif issu de LIVE_VIS_EVERY dans les scripts livevis; défaut script recommandé 25. | 0433a: livevis_control.kv:liveEvery devient le contrôle runtime canonique; recordEvery absent ou <=0 suit cette cadence pour les dumps filtrés.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.h`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_FIELD`

- **Type :** string: ux|uy|speed|vorticity|omega|curl|mass|density|N|n|count|population|particle_count|cell_count|chi|topo_chi|alpha|darcy_alpha|darcy_power|darcy|brinkman_power
- **Défaut :** `ux dans code; dépend des scripts`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335/0337 | mis à jour 0361

Choisit le champ scalaire rendu dans la fenêtre live. 0361 ajoute le vrai comptage particulaire N/count.

**Remarques.** Par défaut scripts: VK/TG=vorticity, Poiseuille=ux, step/box=speed. | 0341a: valeur initiale seulement; peut être modifiée à chaud via livevis_control.kv si SRC_LIVE_VIS_CONTROL_FILE est défini. | N/count compte les particules fluides par cellule live; distinct de mass/density si masses non unitaires.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_FORCE_HOST_MIRROR`

- **Type :** booléen/env truthy
- **Défaut :** `0`
- **Catégorie :** Live visualization fallback/debug
- **Statut :** ajout 0335c

Force la visualisation à utiliser un miroir hôte.

**Remarques.** Debug uniquement; plus lent que CUDA_FIELD.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_GAIN`

- **Type :** double > 0
- **Défaut :** `1.0`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c/0337

Gain visuel appliqué à la colormap.

**Remarques.** Réduire si l’image est saturée rouge/bleu; augmenter pour renforcer le contraste. | 0341a: valeur initiale seulement; peut être modifiée à chaud via livevis_control.kv si SRC_LIVE_VIS_CONTROL_FILE est défini.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_HOLD_ON_EXIT`

- **Type :** booléen/env truthy
- **Défaut :** `1 dans scripts interactifs; 0 recommandé en batch`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0421; propagé Darcy 0425/0426

Conserve la fenêtre livevis ouverte à la fin du run lorsque la visualisation est active.

**Remarques.** Introduit pour inspection interactive ; désactiver en campagnes automatiques afin que le script termine.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `SRC_LIVE_VIS_LOG_SOURCE`

- **Type :** booléen/env truthy
- **Défaut :** `0`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c; amélioré 0337d | mis à jour 0339a | mis à jour 0363/0364/0365

Active les logs de source livevis; affiche désormais min/max/scale et quiver/qscale/qsmooth quand disponibles.

**Remarques.** Depuis 0337d, le statut se réécrit sur la même ligne au lieu d’empiler les logs. | 0339a: export effectif issu de LIVE_VIS_LOG_SOURCE; défaut script recommandé 0. | 0363 ajoute min/max/scale/minmax_s; 0364 ajoute quiver/qscale; 0365 ajoute qsmooth.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_NO_SOLID_OVERLAY`

- **Type :** booléen/env truthy
- **Défaut :** `false/off`
- **Catégorie :** Live visualization runtime
- **Statut :** présent état 36abd23; inventorié 0490p (0490p)

Désactive l’overlay géométrique du solide dans la visualisation live.

**Remarques.** À passer dans l’environnement du shell, pas dans params.kv. Ligne ajoutée par comparaison exhaustive des appels getenv du code courant avec l’inventaire 0436b.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_NX`

- **Type :** entier >= 16
- **Défaut :** `300 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335/0337

Résolution x de la grille/champ live.

**Remarques.** Plus élevé = plus fin mais plus coûteux. 300×80 validé comme compromis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_NY`

- **Type :** entier >= 16
- **Défaut :** `80 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335/0337

Résolution y de la grille/champ live.

**Remarques.** Plus élevé = plus fin mais plus coûteux. 300×80 validé comme compromis.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_PARTICLE_TYPE_FILTER`

- **Type :** entier
- **Défaut :** `-1`
- **Catégorie :** Live visualization runtime / particle type filter 0436
- **Statut :** ajout 0436

Filtre les particules avant accumulation livevis et filtered recording; -1 conserve le comportement all-types.

**Remarques.** Runtime visualisation/enregistrement uniquement. Alias MPCD_* disponible. Recommandé de tracer manifest.kv:particleTypeFilter pour les runs comparatifs.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/filtered_field_recorder_0432.cpp`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_QUANTILE`

- **Type :** double dans (0,1]
- **Défaut :** `0.995`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c

Quantile d’échelle auto du rendu CPU fallback.

**Remarques.** Limite l’effet du bruit particulaire et des outliers.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_QUIVER_MIN_SPEED`

- **Type :** double >= 0
- **Défaut :** `0`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Seuil minimal de vitesse sous lequel les segments quiver ne sont pas dessinés.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_QUIVER_NX`

- **Type :** entier >= 1
- **Défaut :** `60`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Nombre de colonnes de la grille vectorielle quiver décimée.

**Remarques.** Un coût faible est obtenu en gardant une grille décimée, par exemple 60x32.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_QUIVER_NY`

- **Type :** entier >= 1
- **Défaut :** `32`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Nombre de lignes de la grille vectorielle quiver décimée.

**Remarques.** Un coût faible est obtenu en gardant une grille décimée, par exemple 60x32.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_QUIVER_SCALE`

- **Type :** double
- **Défaut :** `-1`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0364

Gain manuel des segments vitesse, en pixels par unité de vitesse.

**Remarques.** Valeur <0: désactive l’overlay quiver; valeur >=0: active l’overlay.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_QUIVER_SMOOTH_PASSES`

- **Type :** entier; -1 ou >=0
- **Défaut :** `-1`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0365

Nombre de passes de lissage 3x3 appliquées aux vecteurs quiver sur la grille décimée.

**Remarques.** <0 réutilise smoothPasses; 0 désactive le lissage des vecteurs; >0 fixe le nombre de passes.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_field_N_0361.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_field_minmax_0363.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_overlay_0364.md`
- `DEFINED_OR_USED_IN` — `doc/livevis_quiver_smoothing_0365.md`
- `DEFINED_OR_USED_IN` — `include/cuda_live_field_0337.h`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR`

- **Type :** booléen/env truthy
- **Défaut :** `0 scripts 0337; 1 fallback manuel`
- **Catégorie :** Live visualization fallback resampling
- **Statut :** ajout 0335d

Force une voie hôte visible pour le resampling.

**Remarques.** Fiable mais lente. À utiliser si CUDA_FIELD échoue ou pour debug.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_SMOOTH_PASSES`

- **Type :** entier >= 0
- **Défaut :** `1 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335c/0337

Nombre de passes de lissage spatial du champ live.

**Remarques.** Vorticité: souvent 1 ou 2; champs vitesse: 0 ou 1. | 0341a: valeur initiale seulement; peut être modifiée à chaud via livevis_control.kv si SRC_LIVE_VIS_CONTROL_FILE est défini.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/livevis_runtime_control_0341a.md`
- `DEFINED_OR_USED_IN` — `src/cuda_live_field_0337.cu`
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`
- `DEFINED_OR_USED_IN` — `src/main_src_mpcd_base.cpp`

### `SRC_LIVE_VIS_VSYNC`

- **Type :** booléen/int
- **Défaut :** `0 scripts 0337`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335

Contrôle vsync de la fenêtre GLFW.

**Remarques.** 0 recommandé pour ne pas brider la simulation; 1 utile si affichage trop rapide.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `SRC_LIVE_VIS_WINDOW_SCALE`

- **Type :** entier >= 1
- **Défaut :** `1`
- **Catégorie :** Live visualization runtime
- **Statut :** ajout 0335

Facteur d’échelle de la fenêtre OpenGL.

**Remarques.** N’affecte pas la physique ni la grille de calcul.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/live_visualization_0335.cpp`

### `STATE_SOURCE`

- **Type :** chemin fichier
- **Défaut :** `selon cas`
- **Catégorie :** Alias script état initial
- **Statut :** ajout/documenté 0426

Chemin source de l’état .smpcd copié dans RUN_ROOT/init.

**Remarques.** Utilisé dans les scripts 0411/0414/0416.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `STEP_XMAX`

- **Type :** double/chaîne selon variable
- **Défaut :** `1.0`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Borne x maximale du rectangle solide step généré en chi.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `STEP_XMIN`

- **Type :** double/chaîne selon variable
- **Défaut :** `0.0`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Borne x minimale du rectangle solide step généré en chi.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `STEP_YMAX`

- **Type :** double/chaîne selon variable
- **Défaut :** `0.52`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Borne y maximale du rectangle solide step généré en chi et borne inférieure de l’inlet segmenté.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `STEP_YMIN`

- **Type :** double/chaîne selon variable
- **Défaut :** `0.0`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Borne y minimale du rectangle solide step généré en chi.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `SUMMARY_ROLE_FILTER`

- **Type :** all|fluid | alias script utilisateur
- **Défaut :** `fluid dans scripts visual 0309+ | fluid dans scripts visuels 0309+`
- **Catégorie :** Alias script | CUDA resampling post-SRC — diagnostics, split-safety et optimisation inactive
- **Statut :** ajout 0314 | script 0314
- **Écrit / contrôle :** `summaryRoleFilter`

Alias exporté par les scripts vers summaryRoleFilter. | Alias script vers summaryRoleFilter.

**Remarques.** Paramètre de script, pas toujours une clé directe. | fluid évite de résumer inutilement les slots Inactive.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`

### `SURFACE_TENSION_MIN_RADIUS_CELLS`

- **Type :** double >=0
- **Défaut :** `source Params=0.0; x12b/x12c/x12d JFM et x12yl: 4; x12cal dynamique et anciens splash x12a obstacle: 3`
- **Catégorie :** Alias runner — tension superficielle
- **Statut :** runner alias courant; valeur dépend de la campagne x12
- **Écrit / contrôle :** `surfaceTensionMinRadiusCells`

Surcharge surfaceTensionMinRadiusCells.

**Remarques.** Ne pas présenter 3 comme valeur universelle actuelle. Le cutoff ne modifie que la courbure utilisée dans sigma*kappa; le champ brut reste disponible. JFM/Young-Laplace courant emploie 4, le calibrateur dynamique x12cal conserve 3.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12cal_capillary_calibrator.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12yl_young_laplace_calibrator.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10q` — Récupération large des recouvrements initiaux rares
- `ASSOCIATED_WITH` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `ASSOCIATED_WITH` → `x12cal` — Calibrateur dynamique de tension superficielle

### `TARGET`

- **Type :** wall | puddle
- **Défaut :** `wall dans runner principal; wrappers dédiés disponibles`
- **Catégorie :** Alias runner — splash x9s
- **Statut :** ajout 0493x9s

Choisit la cible du splash: paroi sèche ou flaque liquide initiale.

**Remarques.** Runner de démonstration/qualification qualitative; ne modifie pas le backend en dehors de l’état initial.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash_puddle.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9s_splash_wall.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9s` — Benchmark paramétrable d'impact et splash

### `THERMOSTAT_ENABLE`

- **Type :** booléen/env truthy
- **Défaut :** `1 dans les démos CUDA isothermes; 0 désactive`
- **Catégorie :** Scripts démo 0283/0291b — thermostat
- **Statut :** contrôle utilisateur script
- **Écrit / contrôle :** `thermostatEnable`

Écrit thermostatEnable dans params.kv et active/désactive les flags CUDA thermostat cohérents.

**Remarques.** 0291b: thermostatEnable devient le commutateur physique unique CPU/GPU; utile pour distinguer aspiration isotherme et libre/adiabatique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/GPU_PATCH_0291B_THERMOSTAT_ENABLE_GATE.md`

### `TOL_ABS`

- **Type :** double >=0
- **Défaut :** `2e-10`
- **Catégorie :** Validateurs CUDA resampling — tolérance
- **Statut :** lecture C++ directe dans validateurs shadow uniquement

Tolérance absolue CPU/GPU des validateurs shadow.

**Remarques.** N'affecte que le verdict CPU/GPU des exécutables de validation CUDA resampling shadow.

### `TOL_REL`

- **Type :** double >=0
- **Défaut :** `2e-12`
- **Catégorie :** Validateurs CUDA resampling — tolérance
- **Statut :** lecture C++ directe dans validateurs shadow uniquement

Tolérance relative CPU/GPU des validateurs shadow.

**Remarques.** N'affecte que le verdict CPU/GPU des exécutables de validation CUDA resampling shadow.

### `TOPO_BENCHMARK_DRAG_LIFT_ENABLE`

- **Type :** booléen
- **Défaut :** `true`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkDragLiftEnable.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_ENABLE`

- **Type :** booléen
- **Défaut :** `true`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkEnable.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_EVERY`

- **Type :** entier
- **Défaut :** `DARCY_COST_EVERY`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkEvery.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_FILENAME`

- **Type :** nom fichier
- **Défaut :** `topo_benchmark_0348.csv`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkFilename.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_FLOW_DIR_X`

- **Type :** double
- **Défaut :** `1.0`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkFlowDirX.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_FLOW_DIR_Y`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkFlowDirY.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_FORCE_ENABLE`

- **Type :** booléen
- **Défaut :** `true`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkForceEnable.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_LIFT_DIR_X`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkLiftDirX.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TOPO_BENCHMARK_LIFT_DIR_Y`

- **Type :** double
- **Défaut :** `1.0`
- **Catégorie :** Alias script topo benchmark
- **Statut :** ajout/documenté 0426

Alias script de topoBenchmarkLiftDirY.

**Remarques.** Les alias script sont résolus avant écriture du .kv ou export de l’environnement.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `UIN`

- **Type :** double/chaîne selon variable
- **Défaut :** `0.25`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Vitesse imposée au segment inlet du backward step.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `UINIT`

- **Type :** double/chaîne selon variable
- **Défaut :** `cas dépendant`
- **Catégorie :** Alias script géométrie/segments Darcy
- **Statut :** ajout/documenté 0426

Vitesse moyenne initiale utilisée lors de la génération d’état.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `VACUUM_BACKGROUND`

- **Type :** booléen shell
- **Défaut :** `1 dans les variantes liquide-vide récentes`
- **Catégorie :** Alias runner — phase extérieure
- **Statut :** ajout 0493x9q/x9r

Choisit un domaine initial sans particules gazeuses et phase B=vacuum dans les runners compatibles.

**Remarques.** Réduit fortement le coût des tests de surface libre lorsque la dynamique gazeuse n’est pas étudiée; ne remplace pas un vrai cas liquide-gaz.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9q_dripping_jet_potential.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x9r_dripping_jet_cutoff.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x9q` — Test de potentialité jet gravitaire / pincement / impact
- `ASSOCIATED_WITH` → `x9r` — Cutoff de résolution du saut capillaire

### `WALL_KBT`

- **Type :** double
- **Défaut :** `-1.0`
- **Catégorie :** Alias script paroi/VP
- **Statut :** ajout/documenté 0426
- **Écrit / contrôle :** `wallKBT`

Température cible des parois/VP, écrite vers wallKBT.

**Remarques.** -1 hérite du comportement par défaut/thermostat selon code.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `WALL_SPEED`

- **Type :** double fini non nul
- **Défaut :** `0.02 dans le runner; campagne de qualification renforcée: 0.075`
- **Catégorie :** Runner x14w — Couette
- **Statut :** paramètre physique visible du benchmark x14w

Impose wallUxBottom=-WALL_SPEED et wallUxTop=+WALL_SPEED.

**Remarques.** La campagne à 0.075 augmente le rapport signal/bruit sans changer la chaîne physique.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_0493x14w_two_phase_couette.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14w` — Couette biphasique

### `X6G_MODE`

- **Type :** enum string
- **Défaut :** `selon benchmark`
- **Catégorie :** Runner x14 — pression gaz
- **Statut :** alias d’ablation/qualification x14u

Sélectionne côté runner le mode x6g à exporter vers MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G.

**Remarques.** Utilisé pour comparer constant et eos_accessible_volume sans modifier le backend.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_ok_0493x14u_normal_kinetic_impact.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14u` — Gaz incident normal
- `ASSOCIATED_WITH` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `X7I_BEND_COMMON_FILLED_STATE`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Runner qualification 0493x7i / bend-pipe
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_BEND_DUMP_EVERY`

- **Type :** entier >=0
- **Défaut :** `25`
- **Catégorie :** Runner qualification 0493x7i / bend-pipe
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_BEND_START_FROM_REST`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Runner qualification 0493x7i / bend-pipe
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_BEND_STEPS`

- **Type :** entier >0
- **Défaut :** `1000`
- **Catégorie :** Runner qualification 0493x7i / bend-pipe
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_BEND_SUMMARY_EVERY`

- **Type :** entier >0
- **Défaut :** `25`
- **Catégorie :** Runner qualification 0493x7i / bend-pipe
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_IO_BOX_DUMP_EVERY`

- **Type :** entier >=0
- **Défaut :** `50`
- **Catégorie :** Runner qualification 0493x7i / same-face IO
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_IO_BOX_STEPS`

- **Type :** entier >0
- **Défaut :** `500`
- **Catégorie :** Runner qualification 0493x7i / same-face IO
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_IO_BOX_SUMMARY_EVERY`

- **Type :** entier >0
- **Défaut :** `25`
- **Catégorie :** Runner qualification 0493x7i / same-face IO
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_LIVE_VIS_ENABLE`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Runner qualification 0493x7i / LiveVis campagne
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_LIVE_VIS_HOLD_ON_EXIT`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Runner qualification 0493x7i / LiveVis campagne
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_POISEUILLE_BODY_AX`

- **Type :** double
- **Défaut :** `0.0004`
- **Catégorie :** Runner qualification 0493x7i / Poiseuille
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_POISEUILLE_DUMP_EVERY`

- **Type :** entier >=0
- **Défaut :** `500`
- **Catégorie :** Runner qualification 0493x7i / Poiseuille
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_POISEUILLE_STEPS`

- **Type :** entier >0
- **Défaut :** `30000`
- **Catégorie :** Runner qualification 0493x7i / Poiseuille
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_POISEUILLE_SUMMARY_EVERY`

- **Type :** entier >0
- **Défaut :** `100`
- **Catégorie :** Runner qualification 0493x7i / Poiseuille
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_POISEUILLE_U0`

- **Type :** double
- **Défaut :** `0.0`
- **Catégorie :** Runner qualification 0493x7i / Poiseuille
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_POISEUILLE_VELOCITY_MODE`

- **Type :** enum string
- **Défaut :** `zero`
- **Catégorie :** Runner qualification 0493x7i / Poiseuille
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_PROJECTION_MAX_ITERATIONS`

- **Type :** entier >0
- **Défaut :** `800`
- **Catégorie :** Runner qualification 0493x7i / projection
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_PROJECTION_TOLERANCE`

- **Type :** double >0
- **Défaut :** `1.0e-5`
- **Catégorie :** Runner qualification 0493x7i / projection
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_G_F_RESIDENT_CG_0493X7J`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f CG resident
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f densité
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES`

- **Type :** double >=0
- **Défaut :** `3`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f densité
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_GF_DENSITY_RELAXATION_TIME`

- **Type :** double >=0
- **Défaut :** `0.25`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f densité
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_GF_DENSITY_TRACTION_GAIN`

- **Type :** double >=0
- **Défaut :** `1.0`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f densité
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES`

- **Type :** double >=0
- **Défaut :** `6`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f densité
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_GF_MIN_FILL_FRACTION`

- **Type :** double [0,1]
- **Défaut :** `0.10`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f support
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_GF_SINGLE_BLOCK_CG_0407`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Runner qualification 0493x7i / Q6-g-f politique CG
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_LEGACY_SINGLE_BLOCK_CG_LARGE`

- **Type :** booléen
- **Défaut :** `0`
- **Catégorie :** Runner qualification 0493x7i / Q6 legacy politique CG
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Runner qualification 0493x7i / Q6 legacy politique CG
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_Q6_STRICT`

- **Type :** booléen
- **Défaut :** `1`
- **Catégorie :** Runner qualification 0493x7i / Q6 strict
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_TG_DUMP_EVERY`

- **Type :** entier >=0
- **Défaut :** `500`
- **Catégorie :** Runner qualification 0493x7i / TG
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_TG_STEPS`

- **Type :** entier >0
- **Défaut :** `10000`
- **Catégorie :** Runner qualification 0493x7i / TG
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `X7I_TG_SUMMARY_EVERY`

- **Type :** entier >0
- **Défaut :** `100`
- **Catégorie :** Runner qualification 0493x7i / TG
- **Statut :** profil final x7q/x7i

Contrôle le runner de qualification physique sans ajouter de clé backend propre.

**Remarques.** Variable de script x7i; le runner transmet ensuite les paramètres/gates canoniques appropriés par mode. Profil gelé pour éviter le retour à des cas Poiseuille pathologiques.

**Défini/utilisé dans :**
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

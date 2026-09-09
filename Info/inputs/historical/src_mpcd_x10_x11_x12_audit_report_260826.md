# Audit du snapshot `snap_260826` — implémentations x10*/x11*/x12*

Source de vérité analysée : `/mnt/data/snap_260826`.

## Chaîne runtime x12 actuellement verrouillée

Les runners x12d JFM, x12yl et x12cal verrouillent la chaîne suivante :

- `MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1`
- `MPCD_X10_KINETIC_INTERFACE_CIC=1`
- `MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1`
- `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1`
- `MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1`
- `MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1`
- `MPCD_X12A_LOCAL_THERMAL_COOLING=1`
- `MPCD_X10R_*=0`, `MPCD_X10S_*=0`, `MPCD_X10T_*=0`
- `MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0`
- x10j/x10k/x10m/x10n = 0
- x10l = 1 dans JFM x12d, 0 dans x12cal/x12yl.

## Point architectural à ne pas perdre

Le CIC `MPCD_X10_KINETIC_INTERFACE_CIC` est bien **dédié à la géométrie cinétique** et ne remplace pas les buffers x6c utilisés par Q6/pression/capillarité. Son dépôt est fusionné avec le passage particulaire total-A, donc il n'ajoute pas de nouveau parcours O(Np).

En revanche, son orchestration est toujours appelée depuis `apply_independent_masked_species_q6_0493w5()` (`src/cuda_q6_resident_0400.cu`, appel vers lignes 22329-22345). Le snapshot ne contient donc **pas** de chemin CIC interface SRC-only hors Q6.

## Corrections majeures apportées aux inventaires

1. Ajout de tous les contrôles tardifs x10/x12 réellement lus par le C++ : CIC, vrai Q2, x10u, x10v, x10w, x10r/s/t, x10i, diagnostic micro, x12a et ses seuils.
2. `phaseInterfaceKineticReflectionFraction` : défaut struct corrigé à **0.0**; `1.0` est un choix des runners x12.
3. Alias parseur ajoutés dans les inventaires : `kineticReflectionFraction` et `evaporationTargetType`.
4. `surfaceTensionMinRadiusCells` : suppression de l'affirmation obsolète « 3 est le choix actuel ». JFM/x12yl utilisent 4; x12cal dynamique conserve 3; défaut struct 0.
5. `surfaceTensionSigma` : distinction explicite entre calibration mécanique/statique x12yl et dispersion dynamique x12cal.
6. `MPCD_X11C_FORCE_X9E_SIGMA0` reclassé comme **flag de runner**, non comme getenv C++ direct.
7. Ajout de trois omissions source antérieures détectées par audit exhaustif : x7y exact periodic B1 closure, x9b curvature audit wall margin, x8a Darcy exact momentum diagnostic.
8. Ajout des six env génériques propres aux validateurs CUDA shadow (`NX`, `NY`, `GAMMA`, `SEED`, `TOL_ABS`, `TOL_REL`) pour que l'inventaire couvre aussi ces exécutables.

## Statut des branches historiques

- x10b/x10c/x10e historiques : supplantés; pas de mode runtime distinct courant.
- x10d hard-r1 : branche de kernel encore présente, mais l'orchestration actuelle n'appelle ce kernel que pour r<1; hard-r1 actif passe par x10i lorsque les ablations continues sont absentes.
- x10f/x10g : kernels/définitions conservés sans call-site actif.
- x10h : sémantique encore intégrée au chemin legacy.
- x10i : fallback hard-r1 encore actif, mais bypassé par x10o dans la chaîne x12.
- x10j/k/m/n/r/s/t : implémentations d'ablation conservées, OFF production.
- x10o/p/q/cic/biq/u/v : composants actifs de la chaîne x12.
- x10w : implémenté, OFF production; incompatible avec x12a.
- x11a/x11b : validation/analyse seulement.
- x11c : support diagnostic C++ observation-only.
- x12a : seule nouvelle physique runtime x12 identifiée.
- x12b/c/d/cal/yl : orchestration de campagnes/benchmarks/calibrateurs, pas de nouvelle physique C++.

## Fichiers produits

- `src_mpcd_env_flags_inventory_consolidated_0493x12_current_260826.csv`
- `src_mpcd_params_inventory_consolidated_0493x12_current_260826.csv`
- `src_mpcd_x10_x11_x12_implementation_audit_260826.csv`

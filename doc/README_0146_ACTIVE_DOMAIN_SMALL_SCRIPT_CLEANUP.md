# 0146 — nettoyage du script small pour `resamplingWetMaskMode=active_domain`

Ce correctif met à jour `scripts/run_injection_fill_resampling_validation_0139_small.sh`
pour le rendre compatible avec la logique 0144 et avec les essais de cuve pleine.

## Changements

- le script n'écrit plus la clé supprimée `method` ;
- Q6 est activé uniquement par `projectionEnable = true` ;
- le script ne contient plus de ligne `resamplingPopulationGuardEnable` ;
- le mode humide par défaut est `resamplingWetMaskMode = active_domain` ;
- l'état initial attendu par défaut est désormais un domaine plein généré par
  `prepare_injection_fill_fluid_uniform_0145`, et non l'état initial inactive-pool
  du remplissage 0139 ;
- le dossier de sortie par défaut est `runs/injection_fill_resampling_0146_active_domain_small`.

## Utilisation recommandée

Depuis la racine du dépôt :

```bash
cd matlab
prepare_injection_fill_fluid_uniform_0145( ...
    'output', '../init/injection_fill_fluid_uniform_0145/initial_state_fluid_uniform_0145.smpcd', ...
    'Lx', 1.0, 'Ly', 1.0, ...
    'Nx', 48, 'Ny', 48, ...
    'gamma', 20, ...
    'capacityMultiplier', 1.25, ...
    'kBT', 0.001, ...
    'seed', 1390145, ...
    'makePreview', true);
cd ..

bash scripts/run_injection_fill_resampling_validation_0139_small.sh
```

Pour forcer un autre masque humide :

```bash
FILL_RESAMP_WET_MASK_MODE=occupied bash scripts/run_injection_fill_resampling_validation_0139_small.sh
```

Pour le test actuel des cellules de paroi, garder la valeur par défaut :

```bash
FILL_RESAMP_WET_MASK_MODE=active_domain
```

## Point de diagnostic

Si des cellules proches des parois solides se vident encore avec `active_domain`,
le problème ne vient plus du reclassement dry par `occupied`. Il faudra alors regarder
la capacité de l'algorithme de resampling à réensemencer une cellule wet strictement vide
depuis ses voisines.

# Catalogue paramètres SRC_GPU 0292 — modes outlet 0291/0291b

Cette mise à jour part du catalogue 0287 et ajoute les paramètres introduits par les patchs 0291/0291b.

## Ajouts principaux

- `openBoundaryOutletMode` couvre désormais explicitement les régimes outlet du SRC classic CUDA :
  - `neumann` : sortie passive ;
  - `equilibrium_flux` : extraction équilibrante couplée au gain net du step ;
  - `forced_flux` : extraction forcée indépendante du flux inlet.
- Nouveaux réglages d’extraction forcée :
  - `openBoundaryOutletForcedMassFlux` ;
  - `openBoundaryOutletForcedMassPerStep` ;
  - `openBoundaryOutletForcedParticleFlux` ;
  - `openBoundaryOutletForcedParticlesPerStep` ;
  - `openBoundaryOutletForcedLayerCells`.
- `thermostatEnable` est documenté comme commutateur physique unique CPU/GPU après 0291b.
- Les variables de script `OUTLET_MODE`, `OUTLET_FORCED_*` et `THERMOSTAT_ENABLE` sont ajoutées au tableau des contrôles d’environnement/scripts.

## Remarque importante

Les anciennes valeurs Q6/open-boundary de `openBoundaryOutletMode` restent documentées pour compatibilité. Pour les démos SRC classic CUDA, il est recommandé d’expliciter `openBoundaryOutletMode=neumann`, `equilibrium_flux` ou `forced_flux` dans le fichier `.kv`.

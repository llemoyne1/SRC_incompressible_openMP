# GPU patch 0262 residentfix — no per-step velocity download in solid resident mode

## Objet

Ce correctif termine le jalon 0262 côté performance résidente. Le chemin
`MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=1` utilisait déjà :

```text
streaming périodique CUDA résident
→ réflexion rectangle immergé CUDA résidente
→ collision SRC CUDA sur l'état partagé 0251
```

mais la sous-étape de collision persistante ne reconnaissait comme modes
résidents sans téléchargement de vitesses que :

```text
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260
MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261
```

Le mode solide 0262 retombait donc encore sur un `download_velocities()` après
collision. Cela ne remet pas nécessairement en cause la validation physique, mais
cela contredit l'objectif du jalon 0262 : conserver l'état particulaire complet
sur GPU entre deux summaries/final sync.

## Modification

`src/cuda_persistent_mpcd_step.cu` ajoute maintenant :

```text
MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262
```

à la garde `residentClassicNoVelocityDownload` de la collision SRC persistante
sans thermostat. En mode 0262, les vitesses ne sont donc plus rapatriées à chaque
pas ; l'état partagé 0251 reste l'état autoritatif jusqu'à la synchronisation de
summary/final déjà prévue dans `src/src_mpcd_base.cpp`.

## Portée

Ce correctif ajoute aussi une garde de sûreté dans `src/src_mpcd_base.cpp` : les modes résidents wall 0261 et solid 0262 ne sont actifs que lorsque `thermostatEnable=false`. Cela évite une application accidentelle du thermostat CPU sur un état hôte volontairement obsolète.

Ce correctif ne change pas la physique GPU :

- Q6/Q9 restent désactivés dans le runner 0262 ;
- le resampling reste désactivé ;
- le viriel / closed-capacity reste désactivé ;
- le thermostat reste désactivé pour le cas solide résident ; la garde 0262 refuse maintenant explicitement `thermostatEnable=true` ;
- le chantier thermostat CUDA wall/solid/piston/inlet-outlet-aware reste ouvert.

Il ne prétend pas encore traiter les inlet/outlet résidents. Ceux-ci nécessitent
un second verrou : l'inlet hard-cell ne se limite pas à supprimer des sorties, il
réactive ou insère aussi les particules du réservoir. Tant que cette activation
n'est pas portée sur l'état partagé GPU, une étape CPU rendrait l'état résident
obsolète.

## Validation attendue

Relancer le jalon existant :

```bash
bash scripts/run_cuda_classic_src_solid_resident_0262.sh
```

Critère :

```text
verdict=PASS
failed_metrics=0
```

À examiner en plus dans le CSV de profiling collision : le mode 0262 doit garder
`sharedParticleStateEnabled≈1` et ne doit plus effectuer le téléchargement plein
des vitesses après collision ; les copies résiduelles de compteurs/cell counts
destinées aux diagnostics peuvent subsister.

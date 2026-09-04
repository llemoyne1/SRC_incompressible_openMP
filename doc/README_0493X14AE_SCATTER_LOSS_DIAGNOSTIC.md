# 0493x14ae — diagnostic minimal de perte d'impulsion dans le scatter x14v

## Objet

Tester un seul mécanisme encore plausible dans x14ad : une impulsion x14v valide
atteint le fallback de support CIC, mais aucune masse liquide n'est trouvée dans
le voisinage de rayon 2 (zone 5x5), donc l'impulsion n'est pas déposée.

Le diagnostic ne modifie aucune loi physique ni aucun fallback.

Gate :

```text
MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=1
```

## Mesure

Trois scalaires cumulatifs sur GPU :

- `terminalNoSupportCount`
- `lostJx`
- `lostJy`

Une perte n'est comptée que dans la branche terminale après échec des quatre
nœuds CIC immédiats puis des anneaux `radius=0..2`.

La ligne finale est :

```text
[0493x14ae-scatter-loss] step=2000 terminalNoSupportCount=... lostJx=... lostJy=... lostJnorm=... semantics=cumulative-valid-nonzero-impulse-untransmitted-after-radius2
```

Une ligne de contrôle est aussi imprimée au premier pas.

## Contrat de coût

- aucun nouveau kernel ;
- aucune nouvelle passe cellule ;
- aucune nouvelle passe particule ;
- aucun changement de la physique x14ad ;
- scratch : 3 doubles = 24 octets ;
- un seul `cudaMemset` lors de l'initialisation du diagnostic ;
- 3 `atomicAdd(double)` uniquement si une perte terminale se produit ;
- téléchargement de 24 octets seulement au premier pas et au pas final.

Gate OFF : chemin de production inchangé, pointeur diagnostic nul.

## Application

Depuis la racine du dépôt x14ad :

```bash
python3 tools/apply_0493x14ae_scatter_loss_diagnostic.py
git diff --check
git diff --stat
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

L'installateur attend la préimage x14ad et est idempotent.

## Test discriminant

Rejouer exactement le cas x14ad n=2 / seed 493180 / 2000 steps :

```bash
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1 \
MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1 \
MPCD_X14V_X6G_FACE_THERMO_TRACTION=0 \
MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0 \
MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0 \
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1 \
MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=1 \
MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0 \
CASE_LABEL=0493x14ae_n2_scatter_loss_diag \
CAMPAIGN_ROOT=runs/0493x14ae_n2_scatter_loss_diag_seed493180 \
SEED=493180 \
MODE=2 \
EPSILON=0.04 \
RADIUS_CELLS=40 \
SURFACE_TENSION_SIGMA=2560 \
STEPS=2000 \
SUMMARY_EVERY=10 \
DUMP_STATE_EVERY=1000 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY=1 \
LIVE_VIS_HOLD_ON_EXIT=1 \
RECORD_ENABLE=true \
RECORD_FIELDS=mass \
RECORD_EVERY=100 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_ok_0493x14x_two_phase_oscillating_drop_n2.sh
```

Le startup doit contenir :

```text
thermoGeometry=x10n-local-x6g-face-gauge+residual-resultant-projection
scatterLossDiag=terminal-radius2
newScratchBytes-x14ae=24
newKernelLaunch=0
newCellPass=0
newParticlePass=0
```

## Verdict

Le run x14ad précédent avait une dérive barycentrique
`|dU/dt| ~= 4.74e-4`, soit une erreur d'impulsion globale de l'ordre de
`0.39` par pas pour ce benchmark.

- Si `terminalNoSupportCount=0`, la branche terminale de support est innocentée.
- Si des pertes existent mais `|(lostJx,lostJy)|` est très inférieur à
  l'impulsion cumulée requise pour expliquer la dérive, elle est également
  secondaire.
- Si le vecteur cumulé des pertes explique en ordre de grandeur et direction la
  dérive totale, le prochain correctif doit viser uniquement le fallback de
  support, sans toucher à la pression x14ad ni à la géométrie x10n.

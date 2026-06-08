# 0304 — Diagnostic de déclenchement adaptatif par flag cellulaire CUDA

## Objectif

Ce jalon ajoute un diagnostic passif post-SRC permettant d'identifier les pas où
un population guard adaptatif devrait être déclenché.  Il ne lance pas encore le
guard hors cadence, ne reconstruit pas de cellule vide, ne maintient pas encore
de champ `last-valid`, et ne modifie jamais l'état particulaire.

Le point d'insertion est volontairement le même que celui validé pour le
resampling CUDA post-SRC : après advection, conditions limites, collision SRC,
thermostat éventuel et `keepMeanFlow`, sur la grille physique non shiftée.

```text
SRC classic CUDA
→ thermostat si thermostatEnable=true
→ dépôt physique non shifté N/M/P
→ émission flag low-N / empty
→ survey 0295 éventuel
→ mass recondition 0296 éventuel
→ population guard 0297/0298/0299 éventuel
```

## Principe

La passe 0304 dépose les particules fluides dans les cellules physiques et
calcule uniquement des compteurs compacts côté device :

- nombre de cellules actives ;
- nombre de cellules humides non vides ;
- nombre de cellules humides vides ;
- nombre de cellules sous le seuil `triggerNMin` ;
- `minNWet`, `maxNWet` ;
- masse et impulsion totales vues par le dépôt ;
- flag global `triggerFlag`.

La fonction écrit `cuda_resampling_adaptive_flag_0304.csv` dans `outputDir`.

Le module est un diagnostic-only : il ne déclenche pas encore le guard.  Le patch
suivant pourra utiliser le même mécanisme pour déclencher le guard adaptatif,
puis un éventuel refill de cellules vides.

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---:|---|
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304` | `0` | Active le diagnostic. |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY` | `1` | Cadence du diagnostic. |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN` | `6` | Seuil low-N déclenchant le flag. |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY` | `0/1` | Déclenchement si cellule active vide. Dans les scripts 0304, il vaut `1`. |
| `MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_THREADS` | `256` | Threads CUDA par bloc. |

## Fichier CSV

Colonnes principales :

```text
step, stage, triggerFlag, triggeredByLowN, triggeredByEmpty,
triggerNMin, triggerEmpty,
activeCells, wetCells, emptyWetCells, lowNCells,
fluidParticles, minNWet, maxNWet,
totalMass, totalPx, totalPy,
depositKernelSeconds, flagKernelSeconds, downloadSeconds, totalSeconds
```

`authoritativeDeviceState=1` signifie que le diagnostic a lu l'état CUDA partagé
frais.  Si l'état CUDA partagé n'est pas marqué frais, le module utilise un état
CUDA privé alimenté depuis le miroir host pour rester non-mutant, comme le survey
0295 corrigé.

## Script de validation

```bash
BIN=build/src_mpcd_base_cuda_0304 \
FORCE_REBUILD=0 \
NX=96 NY=48 STEPS=3000 UIN_GRID="0.60" \
FLAG_EVERY_GRID="1 5 20" \
TRIGGER_NMIN_GRID="4 6 8" \
bash scripts/run_cuda_resampling_adaptive_flag_backward_step_0304.sh
```

Le script lance le backward step avec le flag 0304 activé, sans déclenchement
adaptatif réel.  Il peut comparer un mode `classic_flag` et un mode
`guard_fixed_flag` pour mesurer si le guard fixe réduit les flags low-N/empty.

Sorties :

```text
dev_history/artifacts/gpu_cuda_resampling_adaptive_flag_0304/
  cuda_resampling_adaptive_flag_0304_run_manifest.csv
  cuda_resampling_adaptive_flag_0304_per_run.csv
  cuda_resampling_adaptive_flag_0304_timeseries.csv
```

## Suite prévue

- 0305 : utiliser `triggerFlag` pour déclencher le guard 0297/0298/0299 hors
  cadence nominale, avec `minInterval` et diagnostics d'appels supplémentaires.
- 0306 éventuel : maintenir des champs cellulaires `last-valid` pour les
  cellules récemment vidées.
- Refill Maxwellien seulement ensuite, si le guard adaptatif ne suffit pas.

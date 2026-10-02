# 0493x22c — JCP Section 3.6 liquid–gas cost benchmark

Runner/tooling only. No source or physics modification.

## Question
Measure the cost of the full liquid–gas particle/field chain relative to a two-species kinetic reference with the same initial state, populations, masses, common SRC collisions and species-specific thermostats.

- **B0**: kinetic two-species reference. No liquid projection, phase-field reconstruction, capillary closure or interface momentum-transfer mechanics.
- **B1**: full qualified x14ai-fix1 liquid–gas chain: phase geometry, liquid Q6 projection/density closure, x6g gas pressure, capillary pressure, x10o/CIC/Q2/x10p/x10u/x10v/x12a, x14l, x14v and x14ai-fix1.

B0 is a computational reference only and is not a physical validation model.

## Fixed state
400x400, h=1/256, gamma=20, dt=0.002, seed=493180, R/h=40, n=2, epsilon=0.04, mL=1, mG=0.1, kBTL=0.02, kBTG=0.08. The same generated state is read by B0 and B1. B1 uses sigma=2560.

LiveVis, recording, state dumps and article-only diagnostics are disabled in measured runs.

## Required sequence
1. Preflight only.
2. B0 smoke only (`SMOKE_ONLY=1`), 400 steps, non-timed for publication. It verifies fixed species populations/masses and finite kinetic state.
3. Only after smoke PASS: measured campaign, five paired B0/B1 timings of 400 steps with 100-step excluded warm-ups and alternating AB/BA order.

## Outputs
- `timing_twophase_raw.csv`
- `gpu_state_twophase.csv`
- `analysis/twophase_B0_smoke.txt`
- `analysis/timing_twophase_pairs.csv`
- `analysis/timing_twophase_summary.txt`
- `analysis/timing_twophase_summary.json`

The published ratio is the median of the five within-pair ratios B1/B0. GPU state is checked pairwise; no pair is silently excluded.


## fix1 — preflight under `set -u`

`CASE_LABEL` is now initialized before `suite_defaults_common_0434`. The common helper uses it while defaulting `RECORD_SESSION_PREFIX`; without this initialization, preflight stopped with `CASE_LABEL: unbound variable`. No benchmark parameter or solver physics is changed.

## fix2 — canonicalisation des paramètres

Le writer commun `src-q6-g-f` publie historiquement `projectionMomentumCorrectionEnable`
deux fois (bloc mode puis bloc projection générique). Les deux valeurs sont identiques
(`false`) pour x22c. Le runner canonicalise désormais uniquement les doublons strictement
identiques avant l'audit; toute valeur dupliquée contradictoire provoque un arrêt immédiat.
Aucun paramètre physique ou numérique n'est modifié.

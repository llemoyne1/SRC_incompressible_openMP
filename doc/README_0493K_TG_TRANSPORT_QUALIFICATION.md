# 0493k — Taylor–Green transport, interdiffusion and mono-path non-regression

## Objective

0493k extends the short invariant checks 0493g–0493j with a periodic physical
qualification based on an unforced two-dimensional Taylor–Green vortex.  It
compares the four production paths:

```text
src
src-resampling
src-q6
src-q6-resampling
```

across three scenarios:

```text
mono_legacy     historical mono-species resampling backend
mono_species    resident species backend with speciesCount=1
binary_species  resident two-species backend with a composition Fourier mode
```

The mono state is byte-identical for `mono_legacy` and `mono_species`.  Their
comparison therefore directly checks that the generalized resident species
path does not regress the historical mono-species resampling physics.

## Initial fields

The velocity field is

```text
ux = U0 sin(kx x) cos(ky y)
uy =-U0 cos(kx x) sin(ky y)
```

with `kx=ky=2*pi*TG_MODE`.  Its modal amplitude should decay as

```text
U(t) = U0 exp[-nu (kx^2 + ky^2) t].
```

The binary case uses a uniform total cell mass and

```text
c1 = 1/2 + epsilon sin(kx x) sin(ky y)
c2 = 1 - c1.
```

This scalar mode is aligned with the Taylor–Green stream function, so its ideal
advection term vanishes.  Its decay gives the interdiffusion coefficient:

```text
epsilon(t) = epsilon0 exp[-D (kx^2 + ky^2) t].
Sc = nu / D.
```

Each species starts with paired opposite peculiar velocities.  Consequently,
its cellwise peculiar momentum is exactly zero and both species share the same
initial barycentric velocity.

## Measurements

The analyzer reports, for every seed/scenario/path:

- Taylor–Green amplitude, fit quality and effective viscosity `nu`;
- composition-mode amplitude, fit quality and interdiffusion coefficient `D`;
- Schmidt number `Sc`;
- total and per-species mass, momentum and kinetic-energy changes;
- raw cell-field divergence, vorticity and enstrophy;
- modal residual and spatial correlation;
- species barycentric slip;
- species thermal velocity variance;
- velocity skewness and excess kurtosis;
- occupancy statistics and empty-cell count;
- resampling activity, invalid operations and resident-pool integrity;
- 0493j kinetic-closure activity, infeasible-cell count and residual;
- Q6 application diagnostics;
- elapsed time.

It also produces paired comparisons:

- `src-resampling` versus `src`;
- `src-q6-resampling` versus `src-q6`;
- historical mono resampling versus resident `speciesCount=1`;
- Q6 versus the matching non-Q6 path;
- binary diffusion with and without resampling.

## Empty-refill scope

The current common run helper configures empty-refill on resampling paths, as
required by the production preflight.  0493k does **not** qualify empty-refill.
At the default occupancy, no cell should require it.  The analyzer therefore
requires both counters to remain exactly zero:

```text
emptyRefillCells0319 = 0
emptyRefillParticles0319 = 0
```

Any nonzero value fails the qualification and indicates that this run has left
the intended TG-only scope.

## Files

```text
scripts/generate_0493k_tg_state.py
scripts/run_0493k_tg_transport_matrix.sh
scripts/analyze_0493k_tg_transport.py
```

## Build

```bash
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

## Default qualification

The default executes twelve runs for one seed: three scenarios times four
paths.  Progress is visible through `LIVE_PROGRESS=1`.

```bash
RUN_ROOT=runs/0493k_tg_transport_matrix \
CLEAN_RUN_ROOT=1 \
LIVE_PROGRESS=1 \
bash scripts/run_0493k_tg_transport_matrix.sh
```

Defaults:

```text
grid              32 x 32
gamma             20
steps             300
dt                0.002
dump interval     10
seed              493101
U0                0.08
composition mode  0.15
thermal amplitude 0.04
inactive capacity 8 slots/cell
```

## Short smoke

```bash
RUN_ROOT=runs/0493k_tg_transport_smoke \
CLEAN_RUN_ROOT=1 \
STEPS=80 \
DUMP_EVERY=5 \
SEEDS=493101 \
LIVE_PROGRESS=1 \
bash scripts/run_0493k_tg_transport_matrix.sh
```

This checks execution and invariants, but 80 steps may be too short for the
strictest viscosity and diffusion fits.

## Multi-seed qualification

```bash
RUN_ROOT=runs/0493k_tg_transport_3seeds \
CLEAN_RUN_ROOT=1 \
STEPS=300 \
DUMP_EVERY=10 \
SEEDS="493101 493102 493103" \
LIVE_PROGRESS=1 \
bash scripts/run_0493k_tg_transport_matrix.sh
```

## Selective reruns

Examples:

```bash
SCENARIOS="mono_legacy mono_species" \
RUN_MODES="src-resampling src-q6-resampling" \
SEEDS=493101 \
RUN_ROOT=runs/0493k_mono_nonreg \
CLEAN_RUN_ROOT=1 \
LIVE_PROGRESS=1 \
bash scripts/run_0493k_tg_transport_matrix.sh
```

```bash
SCENARIOS=binary_species \
RUN_MODES="src src-resampling src-q6 src-q6-resampling" \
SEEDS="493101 493102" \
RUN_ROOT=runs/0493k_binary_transport \
CLEAN_RUN_ROOT=1 \
LIVE_PROGRESS=1 \
bash scripts/run_0493k_tg_transport_matrix.sh
```

## Analysis-only mode

```bash
RUN_ROOT=runs/0493k_tg_transport_matrix \
ANALYZE_ONLY=1 \
STEPS=300 \
DUMP_EVERY=10 \
SEEDS=493101 \
bash scripts/run_0493k_tg_transport_matrix.sh
```

The run parameters supplied to analysis-only mode must match those used to
create the snapshots.

## Main outputs

```text
status_0493k.csv
tg_0493k_timeseries.csv
tg_0493k_summary.csv
physics_0493k_checks.csv
physics_0493k.json
physics_0493k.md
```

The default tolerances are intentionally configurable through the analyzer
arguments.  The runner uses conservative first-pass values: 20% for paired
viscosity, 25% for paired diffusion, 15% for legacy/resident mono viscosity,
and 6% normalized modal-curve RMS.  A failed comparison should be diagnosed
from the time series before any tolerance is relaxed.

## 0493k-fix1 — interprétation correcte du smoke court

Le smoke à 80 pas a montré trois catégories distinctes qui ne doivent pas être confondues :

1. les invariants du chemin résident 0493j restent des critères bloquants ;
2. les dérives historiques du chemin mono legacy sont conservées comme observations de référence, sans devenir des critères de validation du nouveau chemin ;
3. Q6 est évalué par comparaison appariée de sa réponse énergétique avec et sans resampling, car la projection Q6 n'est pas un opérateur de conservation brute de l'énergie cinétique initiale ;
4. une estimation de diffusion n'est qualifiée que si la décroissance relative du mode de composition dépasse `diffusion-min-decay-rel` (1 % par défaut). En dessous, le résultat est marqué `INCONCLUSIVE` au lieu de produire un faux échec sur une pente dominée par le bruit.

Le statut global devient :

- `PASS` : tous les critères qualifiables passent ;
- `PASS_WITH_INCONCLUSIVE` : aucun défaut physique détecté, mais la diffusion n'a pas encore suffisamment décru ;
- `FAIL` : au moins un critère physiquement applicable échoue.

Cette correction ne modifie ni le générateur, ni le runner, ni le solveur.

### 0493k-fix2 — Q6 endpoint normalization

When Q6 has removed almost all kinetic energy, a relative comparison normalized by the two final energies is ill-conditioned: a minute absolute difference can appear as a large relative discrepancy. The paired Q6 endpoint gate is therefore normalized by the common initial kinetic energy, consistently with the whole-curve RMS metric. This is an analyzer-only change; existing dumps can be reanalyzed without rerunning.

The fundamental composition mode (`TG_MODE=1`) is intentionally a low-gradient smoke configuration. A resolved diffusion qualification should use a higher, still well-resolved Taylor--Green mode (recommended next step: `TG_MODE=3` on the 32x32 grid) and several seeds.

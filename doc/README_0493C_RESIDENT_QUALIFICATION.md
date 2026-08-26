# 0493c — CUDA-resident species-resampling qualification

## Purpose

0493c is a validation-only package layered on top of 0493b. It does not modify
SRC, Q6, boundary-condition, Darcy, thermostat, resampling or CUDA kernels.

It adds:

- a scalar audit of the 0493b eight-case matrix;
- six complementary short cases;
- a medium-duration qualification runner;
- a targeted collection script for sharing results.

## 0493c-fix1

The first analyzer counted only detailed split/extraction counters from the
generic runtime summary. The CUDA 0490j adapter exposes the authoritative
`resampPopulationGuardApplied` bit, but does not copy all detailed split/merge
counters into those generic fields. The original 0493b runs therefore reported
`no-resampling-activity` even though the resident population guard had edited
the support.

Fix1 separates three notions:

- population-guard mutation (`resampPopulationGuardApplied`);
- native CUDA plan activity (`gpuPlanEntries` from 0490k);
- direct resident particle moves (`operations` and `movedMass` from 0490m).

The qualification runners also use a deterministic interior donor/receiver
pair and physically consistent mixture masses:

- nominal cell mass: `gamma * (m_solvent + m_colloid) / 2`;
- species reference masses: `gamma * m_species / 2`;
- poor/rich thresholds: `0.9` and `1.1` times the nominal cell mass;
- donor population: `gamma + 2`;
- receiver population: `gamma - 2`;
- collision grid shift disabled by default in these qualification runners only.

These are test-runner settings. Production defaults and solver physics are not
changed.

## 0493c-fix2: Darcy/chi reference scope

The first complementary matrix included two legacy `immersedSolid` circle
cases. Runtime results showed that these paths still depend on the older
explicit immersed-solid collision flags. The project now uses the more general
Darcy/chi representation for internal geometry and porous/solid regions.

Fix2 therefore removes explicit immersed-solid cases from the 0493c
qualification scope. It does not repair, reactivate or change the legacy solid
kernels. The two cases are replaced by Darcy/chi cases, and the final case now
combines Q6, segmented boundaries, Darcy/chi and a disabled colloid resampling
switch.

## Complementary cases

- `09_periodic_colloid_only`: solvent disabled, colloid enabled;
- `10_periodic_none`: both species disabled;
- `11_periodic_darcy_colloid_only`: periodic Darcy/chi, solvent disabled;
- `12_periodic_darcy_none`: periodic Darcy/chi, both species disabled;
- `13_q6_segmented_solvent_only`: Q6 + segmented boundaries, colloid disabled;
- `14_q6_segmented_darcy_solvent_only`: Q6 + segmented boundaries + Darcy/chi,
  colloid disabled.

The Darcy field uses the supported analytic circle representation:

- `darcyChiMode = circle`;
- center `(0.5, 0.5)`;
- radius `0.18`;
- interface width `0.02`;
- resampling chi filter enabled with `cudaResamplingChiMin = 0.05`.

The donor/receiver cells are placed away from the circle and from open faces.

## Audited invariants

The analyzer reads `summary_runtime.csv` and the native scalar CUDA diagnostics
from 0490i, 0490k, 0490m and 0490n. It checks:

- zero mutation of disabled species across 0490i/0490m and the runtime summary;
- zero invalid operations, type mismatch and plan overflow;
- enabled particle type only in one-species transfer plans;
- no duplicate, invalid or simultaneously active/free pool slot;
- exact role/capacity and resident-pool slot balances;
- no host cell-policy mirror;
- no plan round trip, full-state download or patchback;
- finite, non-negative masses and the scalar species-mass residual from 0490i;
- bounded mass drift for closed cases;
- Q6 convergence and barycentric residual when Q6 is active;
- nonzero resampling mutation except when every species is disabled;
- optional mandatory nonzero 0490k plan and 0490m direct transfer.

## 0493c-fix3: gamma-relative medium population guard

The short qualification uses `gamma=6`, so the historical guard values
`5/6/7` were appropriate there. The medium runner uses `gamma=10`; retaining
those fixed values would incorrectly classify every nominal ten-particle cell
as overfull and extract particles until at most seven remained.

Fix3 makes the qualification guard defaults relative to `GAMMA`:

- `NMin = GAMMA - 1`;
- `NTarget = GAMMA`;
- `NMax = GAMMA + 1`.

The short matrix therefore remains at `5/6/7`, while the medium matrix uses
`9/10/11`. Explicit environment overrides remain supported. This is a runner
correction only and does not change production defaults or solver physics.

The checker now invokes the actual medium wrapper and verifies the generated
`9/10/11` parameters. The collector also excludes `MANIFEST_SHA256.txt` from
its own manifest, avoiding the impossible self-hash entry previously recorded
as the hash of an empty file.

## Commands

Audit the completed corrected 0493b matrix:

```bash
python3 scripts/analyze_0493c_resident_qualification.py \
  --root runs/0493b_universal_species_resampling_matrix \
  --require-activity \
  --require-direct-transfer
```

Run the six complementary short cases. Their automatic audit requires direct
resident transfers in every case except the two all-disabled cases:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493c_species_resampling_qualification.sh
```

Run the medium qualification (`48x24`, `gamma=10`, `300` steps by default):

```bash
LIVE_PROGRESS=1 bash scripts/run_0493c_medium_qualification.sh
```

Create one targeted bundle to share:

```bash
bash scripts/collect_0493c_validation_bundle.sh
```

The collector writes a `.tar.gz` archive and a matching `.sha256` file. Build
artifacts, particle dumps and unrelated historical runs are intentionally
excluded.

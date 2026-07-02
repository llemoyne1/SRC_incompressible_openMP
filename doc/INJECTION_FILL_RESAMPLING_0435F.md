# Injection-fill SRC+resampling validation 0435f

## Objective

Test whether SRC+resampling can regulate population only over currently
occupied cells while an inlet progressively fills an initially empty domain,
without numerical explosion or non-resident CUDA guard fallback.

## Matched 1000-step runs

Both runs use the same 192x48 grid, gamma=20, seed, inactive pool, inlet ramp,
`dt=5e-4` and nominal `kBT=1e-4`.

| path | peak global kBT | final global kBT | final fluid particles |
| --- | ---: | ---: | ---: |
| SRC control | 6.75e-2 | 5.12e-2 | 20053 |
| SRC+resampling baseline | 3.35e-2 | 4.23e-3 | 4171 |

The resampling run completes without fatal error, non-finite value or velocity
explosion (`maxParticleSpeed < 1.71`). It strongly damps the global kinetic
temperature estimate relative to SRC. This estimate includes macroscopic
front/mean-flow variance and is not by itself the local thermodynamic kBT.

Population regulation follows the changing occupied support:

| step | occupied cells | fluid/occupied cell | maximum cell N |
| --- | ---: | ---: | ---: |
| 100 | 5 | 27.8 | 21 |
| 250 | 11 | 27.5 | 95 |
| 500 | 55 | 21.6 | 82 |
| 750 | 117 | 20.7 | 81 |
| 1000 | 207 | 20.1 | 58 |

The occupied-cell mean therefore converges toward the target population 20 as
the wet region grows. High instantaneous maximum occupancy remains near the
advancing inlet/front and requires later physical interpretation.

## Resident-path defect found

The initial injection-fill runner forced
`MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0`. Consequently:

- CUDA mass recondition 0296 and population guard 0297 were requested but every
  record had `sharedStateFreshBefore=0` and `skippedBecauseStateNotFresh=1`;
- the CPU resampling continuation performed the observed regulation;
- final particle masses reached approximately 0.0041 to 17.35 despite requested
  bounds 0.5 to 2.0.

This is not acceptable as validation of CUDA-resident resampling.

## Script corrections

The runner now follows the existing 0434 SRC-resident configuration:

- persistent thermostat shared-state consumption defaults to enabled and
  strict for non-Q6 SRC paths while preserving explicit validation overrides;
- population guard boundary-awareness is forced on for resampling;
- open-boundary and solid-wall halos default to one cell.

No new solver flag or simulation parameter was added.

The already completed 0434 injection SRC+resampling run demonstrates that this
shared configuration gives `handled=1`, `sharedStateFreshBefore=1` and
`skippedBecauseStateNotFresh=0` for both 0296 and 0297, with cell mass and
momentum residuals around 1e-15.

## Validation status

The corrected injection-fill run itself could not be launched in this stage
because external GPU execution became unavailable. Therefore:

- absence of a baseline numerical explosion is established;
- occupied-cell population modulation is established for the CPU continuation;
- the CUDA-resident wiring defect is identified and corrected in the script;
- corrected injection-fill CUDA-resident stability and particle-mass bounds
  remain to be verified before closing 0435f.

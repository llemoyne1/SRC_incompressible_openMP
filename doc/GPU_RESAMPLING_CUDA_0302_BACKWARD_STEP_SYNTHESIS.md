# 0302 — Backward-step active CUDA resampling synthesis

## Purpose

Patch 0302 is a documentation and reproducibility patch.  It does not modify the C++ core.

It records the first active long/backward-step validation of the post-SRC CUDA resampling chain:

```text
0295 passive post-SRC support survey
0296 optional conservative mass reconditioning
0297 local population guard by representative-particle split/merge
0298 mass/momentum/relative-energy restoration
0299 boundary-aware guard filtering
0300/0301 active validation scripts
```

The physical interpretation remains unchanged: SRC classic produces the fluid state; resampling is a conservative statistical remeshing of the particle representation after SRC, not a new physical collision, force, inlet or outlet process.

## Validated backward-step campaign

The discriminating test is the backward step, because the classic compressible SRC CUDA run loses support in the recirculation region behind the step at sufficiently large inlet velocity.

The aggressive 0301 sweep used:

```text
Nx = 96
Ny = 48
steps = 3000
dt = 8e-4
gamma = 20
kBT = 0.001
Uin = 0.30, 0.45, 0.60
summaryEvery = 100
surveyEvery = 100
dumpStateEvery = 1000
```

The compared modes were:

```text
classic
guard0299_nmin10_nt20_nmax34
guard0299_nmin12_nt20_nmax32
guard0299_nmin14_nt20_nmax30
```

All runs completed with `exitCode = 0`.

## Main result: empty wet cells are eliminated

Final wet empty-cell count:

| Uin | classic | nmin10/nt20/nmax34 | nmin12/nt20/nmax32 | nmin14/nt20/nmax30 |
| ---: | ---: | ---: | ---: | ---: |
| 0.30 | 21 | 0 | 0 | 0 |
| 0.45 | 98 | 0 | 0 | 0 |
| 0.60 | 191 | 0 | 0 | 0 |

This is the central validation point: the local post-SRC CUDA population guard prevents the durable depletion of wet cells behind the backward step.

## Support-quality metrics

Final poor-cell count:

| Uin | classic | nmin10 | nmin12 | nmin14 |
| ---: | ---: | ---: | ---: | ---: |
| 0.30 | 543 | 467 | 370 | 289 |
| 0.45 | 845 | 674 | 632 | 480 |
| 0.60 | 1074 | 872 | 775 | 708 |

Final active-cell population standard deviation (`stdNActive` from the 0295 survey):

| Uin | classic | nmin10 | nmin12 | nmin14 |
| ---: | ---: | ---: | ---: | ---: |
| 0.30 | 8.052 | 5.702 | 5.184 | 4.593 |
| 0.45 | 10.563 | 6.935 | 6.366 | 5.665 |
| 0.60 | 12.808 | 8.090 | 7.325 | 6.611 |

Final maximum wet-cell population (`maxNWet`):

| Uin | classic | nmin10 | nmin12 | nmin14 |
| ---: | ---: | ---: | ---: | ---: |
| 0.30 | 97 | 58 | 57 | 56 |
| 0.45 | 108 | 66 | 68 | 66 |
| 0.60 | 121 | 82 | 86 | 81 |

The stronger the guard threshold, the better the population conditioning, but the number of mutations also increases.

## Mutation intensity

Cumulative split/merge counts:

| Uin | mode | split | merge |
| ---: | --- | ---: | ---: |
| 0.30 | nmin10 | 2 271 | 2 185 |
| 0.30 | nmin12 | 3 563 | 2 754 |
| 0.30 | nmin14 | 6 137 | 3 518 |
| 0.45 | nmin10 | 4 834 | 4 124 |
| 0.45 | nmin12 | 6 882 | 5 016 |
| 0.45 | nmin14 | 10 311 | 6 206 |
| 0.60 | nmin10 | 8 250 | 6 631 |
| 0.60 | nmin12 | 10 832 | 7 759 |
| 0.60 | nmin14 | 14 768 | 9 418 |

`nmin14` is the most efficient support-control setting, but it is also clearly the most intrusive.  The provisional nominal setting is therefore:

```text
Nmin = 12
Ntarget = 20
Nmax = 32
```

This setting eliminates final empty wet cells at all tested inlet velocities, reduces poor-cell counts substantially, and remains less aggressive than `nmin14`.

## Local conservation diagnostics

The guard diagnostics remain at machine precision in the aggressive sweep:

```text
maxAbsCellMassError      = 0 to about 3.6e-15
maxAbsCellMomentumError  = about 7e-15 to 1.8e-14
maxAbsCellKrelError0298  = about 1e-16 to 8e-13
```

The last-guard-call budgets satisfy, to output precision:

```text
totalMassBefore0298 = totalMassAfter0298
totalPxBefore0298   = totalPxAfter0298
totalPyBefore0298   = totalPyAfter0298
totalKrelBefore0298 = totalKrelAfter0298
```

This is the key numerical safety result: the population guard changes the support representation, but the local mass, momentum and relative kinetic-energy budgets are restored.

## Global effects relative to classic

At `Uin = 0.60`, the final differences relative to classic are:

| mode | delta total mass | delta Px | delta kBT estimate |
| --- | ---: | ---: | ---: |
| nmin10 | +30.0 | +132.1 | -2.41e-5 |
| nmin12 | -3.0 | +141.7 | -1.40e-4 |
| nmin14 | +6.56 | +241.3 | -2.55e-4 |

The global mass differences are small compared with a total mass around `8.2e4`.  The longitudinal momentum shift is more visible at high inlet velocity; this should be monitored in longer physical runs.  The stronger `nmin14` setting is the most intrusive by this criterion as well.

## Recommended nominal backward-step validation command

Use the dedicated 0302 nominal script:

```bash
BIN=build/src_mpcd_base_cuda_0302 \
FORCE_REBUILD=0 \
NX=96 \
NY=48 \
STEPS=3000 \
UIN=0.60 \
GUARD_TRIPLE=12:20:32 \
bash scripts/run_cuda_resampling_backward_step_nominal_0302.sh
```

The script runs exactly two modes:

```text
classic
guard0299_nmin12_nt20_nmax32
```

and writes results to:

```text
dev_history/artifacts/gpu_cuda_resampling_backward_step_nominal_0302/
```

## Recommended interpretation

The active guard run is not expected to be bit-identical to classic.  The relevant checks are:

```text
exitCode = 0
final empty wet cells reduced, ideally eliminated
poor cells and stdNActive reduced
split/merge counts finite and interpretable
maxAbsCellMassError at machine precision
maxAbsCellMomentumError at machine precision
maxAbsCellKrelError0298 at machine precision
no runaway total mass, momentum, kBT or max velocity
```

## Current recommendation

Use the following as the provisional nominal CUDA resampling configuration for backward-step support-control tests:

```text
MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY=50
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN=12
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET=20
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX=32
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS=0
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS=0
```

## Next recommended work

The next algorithmic step should not yet be long-distance redistribution.  Before adding a new mechanism, run one or two longer physical checks with the nominal `12:20:32` setting:

```text
backward step, Uin = 0.60, steps = 5000 or 10000
possibly Uin = 0.75 if the classic run remains stable enough for comparison
```

If persistent poor/empty pockets remain after those longer tests, the next algorithmic extension should be local and bounded:

```text
0303 — robust local activation/splitting policy for nearly empty cells
0304 — nearest-neighbour poor/rich transfer, not global redistribution
0305 — optional thermally symmetric representative-particle split
```

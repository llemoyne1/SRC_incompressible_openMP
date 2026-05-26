# Q9 low-k filtering incident and correction

This note documents the Q9 channel instability observed during the first
filtered Poiseuille-channel validation and the correction that brought the C++
implementation back in line with the validated MATLAB method.

## Context

The first C++ Q9 implementation used the generic elliptic projection core for
mass-flux correction and then added an elliptic low-pass filter to the density
relaxation target:

```text
targetRaw     = beta/dt * (M - mean(M))
targetLowK    = lowpass(targetRaw)
```

However, the projection still solved against the full mismatch:

```text
targetLowK - div(J_base)
```

This means that even though the density target was low-pass filtered, the solver
still tried to correct the full high-frequency divergence of the instantaneous
mass flux. That is not the intended MATLAB-like `relax_to_uniform_lowk` behavior.

The validated MATLAB approach corrects the low-k part of the mismatch. It does
not try to remove every cell-level fluctuation of `div(J_base)`.

## Symptom

The Q9 filtered Poiseuille-channel run initially looked clean:

```text
q9CorrectionVelocityRms      ~ 0.002
q9CorrectionVelocityMaxAbs   ~ 0.012 to 0.025
q9TargetFilterRatio          ~ 0.008
q9ResidualRel                ~ 1e-10
kBT                          ~ 0.0099
```

but stopped around `t ≈ 16.43` with:

```text
Fatal error: Too many y-wall reflections in one step; step=16430 time=16.43
particle=12110 attemptedReflections=65 x=0.161999 y=75.3205
vx=-92862.1 vy=139067 predictedNextX=-92.7001 predictedNextY=214.388
dt=0.001 domain=[0,1]x[0,1]
```

The wall reflection was only the final symptom. The particle had already become
ballistic.

## Diagnostics added

The following runtime diagnostics were added to identify the failure mode:

```text
meanParticleSpeed
maxParticleSpeed
maxParticleAbsVx
maxParticleAbsVy
maxXWallReflectionsPerParticle
maxYWallReflectionsPerParticle
q9CorrectionVelocityMaxAbs
```

The enriched wall-reflection exception now reports step, time, particle index,
position, velocity, predicted streamed position, time step and domain bounds.

A `summaryEvery = 1` debug run showed the true blow-up mechanism:

```text
step ≈ 16397-16417
kBT                         : O(1e3) to O(1e5)
maxParticleSpeed            : O(1e4) to O(1e5)
q9CorrectionVelocityRms     : O(1e2) to O(1e3)
q9CorrectionVelocityMaxAbs  : O(1e4) to O(1e5)
q9DensityStdBefore          : O(50-60)
q9ResidualRel               : O(1e-10)
```

The elliptic solve still converged, so the issue was not linear-solver failure.
The issue was that the right-hand side being solved was no longer the intended
low-k mismatch.

## Correction

The corrected C++ Q9 logic is:

```text
targetRaw      = beta/dt * (M - mean(M))
targetLowK     = lowpass(targetRaw)

rhsFull        = targetLowK - div(J_base)
rhsLowK        = lowpass(rhsFull)

projectionTarget = div(J_base) + rhsLowK
```

Then the generic elliptic projection solves:

```text
div(J_base + dJ) = projectionTarget
```

This makes the correction operate only on the low-k mismatch, consistent with
the MATLAB `relax_to_uniform_lowk` / `general_bc` philosophy.

## Result after correction

After filtering the low-k mismatch, the Poiseuille-channel Q9 run reached
`tEnd = 50` cleanly.

Representative result:

```text
classic     : fitR2 = 0.76987, nuEff = 0.11691, kBTEnd = 0.0099887
q6          : fitR2 = 0.79313, nuEff = 0.12044, kBTEnd = 0.0099031
q9_filtered : fitR2 = 0.79540, nuEff = 0.11631, kBTEnd = 0.0099081
```

Low-k density metric:

```text
filteredStdNTailMean q6          = 0.054823
filteredStdNTailMean q9_filtered = 0.048259
filteredStdNRelToQ6              = 0.88028
```

Q9 correction and wall diagnostics after correction:

```text
q9RuntimeResidualEnd         = 8.14e-11
q9TargetFilterRatioEnd       = 0.0099155
q9CorrectionVelocityRmsEnd   = 1.494e-4
q9CorrectionVelocityMaxEnd   = 2.9921e-4
maxParticleAbsVyEnd          = 0.38804
yWallReflectionMaxEnd        = 1
```

## Lesson

For Q9, it is not sufficient to low-pass filter only the density relaxation
target. The mass-flux divergence mismatch must also be restricted to the same
low-k content. Otherwise Q9 can still attempt to correct high-frequency
cell-level mass-flux noise and produce catastrophic local velocity kicks.

This correction is deliberately preferred over adding a velocity limiter. A
limiter may still be useful as a safety feature later, but the primary fix is to
match the validated MATLAB method.

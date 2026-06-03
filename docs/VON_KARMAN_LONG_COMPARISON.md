# Von Karman long comparison: classic vs Q9/virial liquid closure

## Purpose

This test prepares a long periodic-cylinder comparison inspired by the standalone
CUDA `mpcd_vkkh.cu` von-Karman case.  The CUDA code uses a fixed circular
obstacle, y-periodicity, an x-open clean inlet/outlet reinjection path, a
thermostat, and a global mean-flow controller.  The current OpenMP Q6/Q9 branch
intentionally does **not** implement inlet/outlet projection yet, so this test is
not the final open-flow von-Karman benchmark.

The overnight comparison instead uses the part that is already compatible with
classic and full liquid closure:

- fixed immersed analytic circle;
- periodic x/y domain;
- imposed global mean flow around the obstacle;
- identical geometry for classic and Q9/virial;
- Q6/Q9 immersed-solid hard-wall mask for the liquid closure case;
- strict closure of curved cut faces around the analytic circle.

This gives a useful stress test of structure preservation around a curved solid
before introducing inlet/outlet boundary conditions.

## Geometry and scaling

The CUDA default geometry has a thin domain and a cylinder with `D/Ly = 0.2`.
The OpenMP long test keeps this ratio, but uses a CPU-manageable grid:

```text
Lx = 2.0
Ly = 0.4
Nx = 320
Ny = 64
gamma = 20
circle center = (0.35, 0.20)
R = 0.04
D = 0.08
```

The default target mean flow is scaled to the same order as the backward-step
liquid validation:

```text
kBT = 0.0025
sqrt(kBT) = 0.05
targetMeanUx = 0.015
U/sqrt(kBT) = 0.30
```

The CUDA code used `alphaDeg=90`, so this test also uses `alphaDeg=90`.

## Mean-flow controller

The patch adds a compact `keepMeanFlowEnable` controller to the OpenMP code.  At
the end of each step, after SRC/Q6/Q9/virial/thermostat, the code computes the
mass-weighted global mean velocity and adds a uniform velocity shift so that

```text
<ux> = targetMeanUx
<uy> = targetMeanUy
```

This mirrors the CUDA `keepMeanFlow` idea without adding inlet/outlet logic.
It preserves relative thermal velocities and is intended for periodic wake tests
where a body force alone would otherwise allow long-time mean drift.

Accepted parameter keys:

```text
keepMeanFlowEnable = true
keepMeanFlow = true        # alias
targetMeanUx = ...
targetMeanUy = ...
meanFlowUx = ...           # alias
meanFlowUy = ...           # alias
U0 = ...                   # alias for targetMeanUx
```

## Runs

The script generates the initial state if needed, writes two parameter files, and
launches:

```text
runs/von_karman_classic_long_320x64
runs/von_karman_q9_virial_long_320x64
```

The liquid-closure configuration uses the current backward-step final candidate:

```text
method = q9_virial
q6ProjectionStrength = 0.50
q9DensityRelaxationBeta = 0.001
q9LowKMaxIndex = 4
Kvirial = 0.50
virialBeta = 0.05
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
```

## Usage

Build after applying the patch:

```bash
./scripts/build_src_mpcd_base.sh
```

Launch the full overnight comparison:

```bash
./scripts/run_von_karman_long_comparison.sh
```

Useful overrides:

```bash
N_STEPS=20000 ./scripts/run_von_karman_long_comparison.sh        # smoke/preflight
RUN_CLASSIC=0 ./scripts/run_von_karman_long_comparison.sh        # liquid only
RUN_LIQUID=0 ./scripts/run_von_karman_long_comparison.sh         # classic only
THREADS=8 N_STEPS=160000 ./scripts/run_von_karman_long_comparison.sh
```

Run the MATLAB analysis:

```matlab
cd matlab
suite = validate_von_karman_long_comparison();
```

or directly after the simulation:

```bash
RUN_ANALYSIS=1 ./scripts/run_von_karman_long_comparison.sh
```

## Diagnostics

The MATLAB validator writes:

```text
runs/von_karman_long_comparison_analysis/von_karman_long_comparison_summary.csv
runs/von_karman_long_comparison_analysis/von_karman_long_comparison_metrics.png
runs/von_karman_long_comparison_analysis/von_karman_fields_<case>.csv
```

Key quantities:

- `maxParticlesInsideCircle`;
- late `meanVx`, `meanVy`, `kBT`;
- wake population lower tail: `populationP05WakeOverReference`,
  `populationBelow5FractionWake`, `populationTemporalCvMeanWake`;
- coherent, total, and fluctuating wake vorticity;
- `omegaMeanLowKFractionWake`;
- immersed-solid projection leak diagnostics for Q6/Q9, including the split between cell/boundary closed faces and curved cut faces when available;
- `virialDuOverThermalRmsLate`.

## Interpretation caveat

This is a periodic wake comparison, not yet the final open-flow von-Karman
benchmark.  The true CUDA-like case requires external inlet/outlet support in the
OpenMP boundary layer and then in the Q6/Q9 elliptic boundary conditions.  The
present test is nevertheless useful for validating whether the final liquid
closure preserves organized wake structures around a curved immersed solid.


## Curved-solid hard-wall update

For circular obstacles, the liquid run must close not only cells whose centres
are classified as solid, but also fluid-fluid faces whose segment intersects the
analytic circle.  The option:

```text
projectionImmersedSolidCloseCutFaces = true
```

is enabled by default and written explicitly by the von-Karman script.  The
runtime summary appends cut-face diagnostics such as
`q6ImmersedSolidLeakCutProjectedFluxRms` and
`q9ImmersedSolidLeakCutMassFluxRms`.  A clean curved-solid projection should
report non-zero cut-face counts but near-zero leak on those faces.  See
`docs/IMMERSED_SOLID_CURVED_HARDWALL_MASK.md` for details.

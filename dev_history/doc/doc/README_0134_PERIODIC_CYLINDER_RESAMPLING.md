# 0134 — Periodic immersed-cylinder validation for Q6 + resampling

This patch adds a first immersed-solid validation for the OpenMP weighted-resampling branch.
It deliberately uses a **fully periodic cylinder** rather than an inlet/outlet von-Karman case.  This isolates the immersed-solid coupling and the Q6/resampling interaction from open-boundary effects.  Once this case is stable, a true inlet/outlet wake benchmark can be added separately.

Workflow convention is unchanged:

- MATLAB prepares the `.smpcd` initial state in `../init/**` when launched from `matlab/`.
- Bash scripts generate `.kv` files and run `build/src_mpcd_base` from the repository root.
- MATLAB post-processes `../runs/**`.
- The C++ code does not generate initial particle states.

## Files

```text
matlab/prepare_periodic_cylinder_resampling_0134.m
matlab/analyze_periodic_cylinder_resampling_0134.m
scripts/run_periodic_cylinder_resampling_validation_0134.sh
doc/README_0134_PERIODIC_CYLINDER_RESAMPLING.md
```

## Geometry

Default geometry:

```text
Lx = 2.0, Ly = 1.0
Nx = 96, Ny = 48
gamma = 20
circle: Cx = 0.5, Cy = 0.5, R = 0.12
BC: periodic in x and y
bodyAccelerationX = 0.005
```

The initial state is generated only in fluid cells whose centers are outside the cylinder.  Particle positions are sampled in those cells and rejected if they fall inside the cylinder.  The default population mode is `random`, with exactly conserved total population over fluid cells.

## 1. Prepare the initial state with MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_periodic_cylinder_resampling_0134( ...
    'output', '../init/periodic_cylinder_resampling_0134/initial_state_periodic_cylinder_0134.smpcd', ...
    'Lx', 2.0, 'Ly', 1.0, ...
    'Nx', 96, 'Ny', 48, 'gamma', 20, ...
    'cylinderCx', 0.5, 'cylinderCy', 0.5, 'cylinderR', 0.12, ...
    'populationMode', 'random', ...
    'populationStd', 6.0, 'populationMin', 4, 'populationMax', 36, ...
    'initialMeanUx', 0.02, ...
    'kBT', 0.001, ...
    'seed', 1340134, ...
    'makePreview', true);
```

This writes:

```text
../init/periodic_cylinder_resampling_0134/initial_state_periodic_cylinder_0134.smpcd
../init/periodic_cylinder_resampling_0134/initial_periodic_cylinder_layout_0134.csv
../init/periodic_cylinder_resampling_0134/initial_periodic_cylinder_population_0134.png
```

## 2. Run OpenMP

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

CYL_STEPS=3000 \
CYL_DUMP_EVERY=100 \
CYL_SUMMARY_EVERY=25 \
CYL_THREADS=8 \
./scripts/run_periodic_cylinder_resampling_validation_0134.sh
```

For a short performance/visual smoke:

```bash
CYL_STEPS=1000 \
CYL_DUMP_EVERY=250 \
CYL_SUMMARY_EVERY=10 \
CYL_THREADS=8 \
./scripts/run_periodic_cylinder_resampling_validation_0134.sh
```

The script launches:

```text
classic
q6
q6_resampling
```

with the same initial `.smpcd` state.

## 3. Analyze with MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
analyze_periodic_cylinder_resampling_0134('../runs/periodic_cylinder_resampling_0134');
```

The analysis writes:

```text
../runs/periodic_cylinder_resampling_0134/analysis/periodic_cylinder_summary_0134.csv
../runs/periodic_cylinder_resampling_0134/analysis/periodic_cylinder_metrics_*.csv
../runs/periodic_cylinder_resampling_0134/analysis/periodic_cylinder_0134_timeseries.png
../runs/periodic_cylinder_resampling_0134/analysis/periodic_cylinder_0134_final_fields_*.png
```

## Quantities to inspect

Primary checks:

- no mass/population leak inside the cylinder (`solidLeakMass`, `solidLeakCount`);
- `q6` and `q6_resampling` keep the immersed-solid Q6 mask active;
- `q6_resampling` reduces `resampMRelRms` without creating a spurious ring around the cylinder;
- wake diagnostics remain finite and comparable between `q6` and `q6_resampling`;
- runtime remains close to the optimized post-0133 behavior.

This is not yet a physical inlet/outlet von-Karman benchmark. It is a controlled immersed-cylinder validation for the resampling core.

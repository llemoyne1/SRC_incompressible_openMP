# 0493x0 — two-species closed-box dam-break demonstration

## Purpose

This runner provides a qualitative closed-box demonstration of the validated
multi-species Q6 operator:

```text
speciesQ6Mode = independent_masked
liquid q6Strength = 1
gas q6Strength = 0
```

The initial state is a dense liquid column at the lower-left corner of a rigid
tank, surrounded by a compressible gas. Gravity releases the column at the
first step. No inlet, outlet, reservoir or atmospheric vent is present.

This is a visualization and integration demonstration, not a calibrated
free-surface benchmark. The current model has no surface-tension law and uses
the stage-1 `phi=0` correction-pressure condition at the masked liquid/gas
interface.

## Default case in the current runner

```text
domain               1.0 x 1.0
grid                 200 x 200
gamma                10
active particles     400,000
liquid column        0.25 x 0.99
liquid/gas mass      1000 / 1
kBT                  0.5
gravity y            -0.05
dt                    0.005
steps                 15,000
Q6 tolerance          1e-5 relative
Q6 max iterations     800
mode                  src-q6
resampling            disabled
left/right walls      specular
bottom wall           solid
upper wall            specular
open boundaries       none
```

The density-ratio proxy is the particle-mass ratio. Both phases initially
contain the same particle count per cell. The state generator constructs paired
thermal velocities with exactly zero cell mean, so the initial macroscopic
velocity is zero.

The default wall choice is deliberate:

- the left and right specular faces are impermeable and tangentially free, so
  the liquid does not form the long no-slip wall trail seen with solid lateral
  walls;
- the solid bottom retains the established virtual-particle wall coupling;
- the specular top closes the gas volume without injecting particles.

`BC_LEFT`, `BC_RIGHT`, `BC_BOTTOM` and `BC_TOP` may be overridden, but the first
closed-box CUDA subset accepts only `solid` and `specular`. Bounceback corners
remain excluded until a separate corner-order validation is available.

## Run

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x0_dam_break_demo.sh
```

LiveVis defaults to liquid density only (`particleTypeFilter=1`). The root
`livevis_control.kv` remains the active interactive control file.

The Q6 solve budget remains explicit and overridable:

```bash
Q6_PROJECTION_TOLERANCE=1e-7 \
Q6_PROJECTION_MAX_ITERATIONS=1600 \
LIVE_PROGRESS=1 bash scripts/run_0493x0_dam_break_demo.sh
```

To compare unprojected SRC and independent-masked Q6 from the same initial
state:

```bash
RUN_MODES="src src-q6" LIVE_PROGRESS=1 \
  bash scripts/run_0493x0_dam_break_demo.sh
```

A generation/parameter preflight without launching the binary is available:

```bash
PREFLIGHT_ONLY=1 NX=48 NY=32 GAMMA=4 LIVE_VIS_ENABLE=0 \
  bash scripts/run_0493x0_dam_break_demo.sh
```

## Runtime contract

The runner deliberately accepts only `src` and `src-q6`. Resampling is disabled
so the demonstration remains inside the already-qualified Q6 scope. The
`closed_box` suite topology enables the opt-in resident CUDA path
`MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1=1` and requires:

- four static `solid`/`specular` faces;
- `openBoundarySegmentsEnable=false` and `openBoundarySegmentCount=0`;
- no immersed solid, moving fluid bound or closed-capacity response;
- resident CUDA streaming, SRC collision and thermostat handling;
- for `src-q6`, resident `independent_masked` Q6 with boundary family
  `closed_box`, no host cell array, weight upload, full-state download or CPU
  fallback;
- a converged non-empty liquid solve;
- zero active Q6 cells and zero direct Q6 correction for the gas;
- exact conservation of the liquid and gas particle populations and their
  separate masses;
- zero inlet/outlet deletion, insertion, reservoir or net-particle counters.

The final report is written to:

```text
runs/0493x0_dam_break_<NX>x<NY>_g<GAMMA>/dam_break_demo_0493x0.csv
```

It records the final populations and masses by species, sampled wall-hit
counters, Q6 liquid coverage and the applied-divergence ratio.

Filtered field recording is disabled by default because a full field sequence
can become large. It can be enabled explicitly with
`FILTERED_RECORDING_ENABLE=1` and a suitable `FILTER_SAMPLE_EVERY`.

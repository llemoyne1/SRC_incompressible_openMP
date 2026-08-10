# 0493x7i — physical qualification of run_ok SRC / Q6 / Q6-g-f

## Purpose

`0493x7i` turns four already successful `run_ok` demonstrations into a focused
physical comparison of:

```text
src          historical compressible SRC/MPCD
src-q6       previous Q6 path
src-q6-g-f   current Q6-g-f path
```

No C++ or CUDA equation is changed.  The simulation stage only manages state
dumps.  All physical measurements are performed afterwards in MATLAB.

The post-processor reuses the existing MATLAB primitives supplied with the
project:

- `read_smpcd_state.m`;
- `bin_smpcd_state.m`;
- `list_smpcd_dumps.m`;
- `parse_smpcd_kv.m`;
- `analyze_poiseuille_profile.m`.

Filtered field recording and LiveVis are disabled by the x7i launcher so that
the qualification data source is unambiguously the particle-state dumps.

## Four discriminating cases

### 1. Forced Taylor--Green

`run_ok_tg.sh` is used with its continuous divergence-free `(1,1)` forcing.
The analyzer checks that forcing is actually enabled and has positive amplitude.

The four vortex centers are

```text
(Lx/4,Ly/4), (3Lx/4,Ly/4), (Lx/4,3Ly/4), (3Lx/4,3Ly/4).
```

For every dump the analyzer computes the population averaged over a circular
core of radius `tgCoreRadiusCells` and reports

```text
coreRelDelta = (Ncore - <N>domain) / <N>domain
```

plus the nearest-center-cell population and the global relative population RMS.
The default tail average uses the last 50% of dumps.

This directly measures the compressibility-induced population defect/excess at
the vortex cores rather than relying only on global `stdN`.

### 2. Poiseuille

The existing `analyze_poiseuille_profile.m` is reused.  For each mode x7i
reports:

- quadratic-fit `R2`;
- effective viscosity estimate `nuEff`;
- mean velocity;
- `Umax/<Ux>` and `Ucenter/<Ux>`;
- wall velocities normalized by `<Ux>`;
- L2 and Linf difference of `Ux(y)/<Ux>` relative to SRC.

The normalized profile comparison separates profile-shape preservation from a
possible change of effective transport coefficient.

### 3. Bend pipe

This is a controlled startup qualification.  By default x7i overrides only the
initial velocity mode to `zero`; the historical `U0` remains the inlet target.
The three modes also use

```text
RUN_OK_DARCY_COMMON_FILLED_STATE=1
```

so they start from the same filled Brinkman fictitious domain.  This avoids
confounding projection response with the historical solid-cell deactivation.
Set `X7I_BEND_START_FROM_REST=0` to recover the historical `uniform_x` initial
velocity, or `X7I_BEND_COMMON_FILLED_STATE=0` for the historical SRC/Q6 Darcy
initialization.

The MATLAB analyzer masks the Darcy solid using the stored float32 chi field
(`chi >= 0.5` by default).  Before startup-speed metrics it applies a
geometry-aware spatial box average (radius 3 cells by default) to `Ux,Uy`; this
suppresses stochastic cell-mean thermal noise without mixing Darcy-solid cells
into the fluid signal.  It then measures:

- coherent cell-speed RMS `UcohRms`;
- mean cell speed;
- fractions of the fluid geometry above 0.10 and 0.25 inlet speed;
- mean speed in the far-right quarter of the fluid geometry;
- t50 and t90 relative to the late-time response level for global and far-field
  speed;
- first crossing times of fixed physical levels 0.10 and 0.25 of inlet speed,
  for both global coherent RMS and far-field mean speed.  A missing crossing is
  reported as `NaN`, which is intentionally more discriminating than normalizing
  each mode by its own possibly-small late response.

### 4. Same-face IO box

The same startup diagnostics are applied to `run_ok_io_box_same_face.sh`.
The far-right-quarter signal is especially useful here because inlet and outlet
are both on the left face: it directly tests how rapidly the remote part of the
box participates in the motion.

## Default dump plan

The default plan intentionally uses fewer dumps for the large `300x300`
same-face box:

```text
TG           : 10000 steps, dump every 500
Poiseuille   : 10000 steps, dump every 500
Bend pipe    :  1000 steps, dump every 25, starts from rest
Same-face IO :   500 steps, dump every 50
```

All dumps use `dumpRoleFilter=fluid`.  The full four-case campaign can still
occupy several GB; each cadence and run length is independently overridable.

## Run

Full qualification:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x7i_q6_g_f_physical_qualification.sh
```

Preflight only:

```bash
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 \
bash scripts/run_0493x7i_q6_g_f_physical_qualification.sh
```

Target a subset:

```bash
CASES="tg poiseuille" LIVE_PROGRESS=1 \
bash scripts/run_0493x7i_q6_g_f_physical_qualification.sh
```

Useful overrides include:

```text
X7I_TG_STEPS, X7I_TG_DUMP_EVERY
X7I_POISEUILLE_STEPS, X7I_POISEUILLE_DUMP_EVERY
X7I_BEND_STEPS, X7I_BEND_DUMP_EVERY
X7I_IO_BOX_STEPS, X7I_IO_BOX_DUMP_EVERY
QUAL_MODES
RUN_ROOT

MATLAB option `startupSmoothRadiusCells` controls the post-processing spatial
average; setting it to zero uses unsmoothed cell means.
```

## Offline MATLAB analysis

From the repository root:

```matlab
addpath('matlab');
out = analyze_0493x7i_q6_g_f_qualification( ...
    'runs/0493x7i_q6_g_f_physical_qualification');
```

The analyzer writes under `RUN_ROOT/analysis`:

```text
0493x7i_tg_vortex_core_metrics.csv
0493x7i_tg_vortex_core_summary.csv
0493x7i_poiseuille_summary.csv
0493x7i_poiseuille_profiles.csv
0493x7i_bend_pipe_startup_metrics.csv
0493x7i_bend_pipe_startup_summary.csv
0493x7i_io_box_startup_metrics.csv
0493x7i_io_box_startup_summary.csv
```

and, by default, PNG plots for TG core population, normalized Poiseuille
profiles, and global/far-field startup response for bend-pipe and same-face IO.

## Interpretation

The campaign is intentionally diagnostic, not threshold-driven.  No arbitrary
PASS/FAIL tolerance is imposed on the physical differences before seeing the
three curves.  The intended questions are:

1. Does Q6-g-f suppress the structured TG core population defect relative to
   SRC and previous Q6 without destroying the forced vortex?
2. Does Q6-g-f preserve the normalized Poiseuille profile while changing, or
   not changing, the effective transport amplitude?
3. Do the projected paths transmit the inlet-driven motion through the bend
   and same-face box substantially faster than compressible SRC?
4. Is the previous Q6 response intermediate, equivalent to Q6-g-f, or
   qualitatively different?

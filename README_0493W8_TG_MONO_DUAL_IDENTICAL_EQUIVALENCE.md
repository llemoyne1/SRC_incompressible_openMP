# 0493w8 — Taylor–Green mono/dual-identical Q6 qualification

## Purpose

This qualification reuses the historical 0493k Taylor–Green transport setup,
but removes every resampling branch and targets the new
`speciesQ6Mode=independent_masked` operator.

It answers three separate questions:

1. Does enabling the species registry change a monoespecies SRC run?
2. On a full periodic support, does independent masked Q6 reproduce the legacy
   monoespecies Q6 transport?
3. If one physical fluid is split into two particle type labels, do two
   independent Q6 projections preserve the same effective Taylor–Green fluid?

## Physically identical states

The generator writes two states:

```text
tg_mono_identical_0493w8.smpcd
tg_dual_identical_0493w8.smpcd
```

Their positions, velocities, masses and roles are byte-identical. Only the
active-particle type array differs.

Particles are generated in opposite peculiar-velocity pairs. Complete pairs
are assigned to one type in the dual state, with half the pairs assigned to
type 1 and half to type 2 in every cell. Consequently, at step zero:

- both types have equal particle count and mass in every cell;
- each type has the requested Taylor–Green barycentric velocity;
- each type has zero cell peculiar momentum;
- the total physical state is exactly the mono state.

The default `gamma=32` gives 16 particles of each type per cell. This limits
accidental loss of one type from a cell while remaining comparable in cost to
the historical 0493k matrix.

## Matrix

Three scenarios are run with `src` and `src-q6`:

```text
mono_legacy
mono_independent
dual_identical
```

`mono_legacy` disables the species registry and uses the historical Q6 path.

`mono_independent` registers one type and uses:

```text
speciesQ6Mode = independent_masked
speciesQ6MinOccupancyFraction = 0.0
```

`dual_identical` registers types 1 and 2 with identical physical metadata,
identical particle masses, equal reference cell masses and Q6 strength 1 for
both types.

All resampling controls are disabled. The projection momentum correction is
disabled in both legacy and independent Q6 branches, because the independent
operator deliberately does not apply the legacy uniform momentum patch. SRC
therefore retains a strict absolute momentum-conservation check. For Q6, the
absolute mean-flow drift remains visible and is protected only by a broad
pathology guard (`1e-2 U0` by default). Mono non-regression is qualified by the
direct legacy/independent drift difference on each seed, rather than by an
arbitrary absolute threshold on a residual shared by both operators.

## Qualification levels

### Strict SRC neutrality

The analyzer compares every state dump particle by particle. Dump names are
resolved by their numeric step, including the zero-padded names written by the
production state recorder:

```text
mono_legacy/src       vs mono_independent/src
mono_independent/src  vs dual_identical/src
```

For the second comparison, type identifiers are ignored. Positions, velocities,
masses and roles must otherwise agree to the strict configured tolerance.

### Mono Q6 non-regression

The full-domain comparison is:

```text
mono_legacy/src-q6 vs mono_independent/src-q6
```

It checks effective viscosity, the complete normalized TG-amplitude curve,
the RMS velocity difference of the particle states and the difference between
the normalized mean-flow drifts. The absolute Q6 drift remains reported for
each run, but only the direct legacy/independent difference is a mono
non-regression gate.

### Dual-identical effective-fluid agreement

The comparison is:

```text
mono_independent/src-q6 vs dual_identical/src-q6
```

It is not required to be bitwise identical. After SRC collisions, the two
finite particle subsets develop their own barycentric fluctuations and are
projected independently. The analyzer therefore checks:

- Taylor–Green effective viscosity;
- complete amplitude-decay curve;
- RMS particle-velocity difference, reported as a microscopic diagnostic only;
- final type-to-type barycentric slip;
- minimum active-support coverage for each projected type;
- convergence of every independent Q6 solve.

The particle-index velocity difference is not a PASS/FAIL gate in the dual Q6
comparison. Independent projections act on distinct finite-population velocity
fields, so microscopic trajectories may decorrelate even when the barycentric
TG transport, divergence response and type-to-type slip remain qualified.

The analyzer also applies a broad `src` versus `src-q6` TG transport check. A
later calibrator matrix will refine viscosity, self-diffusion and longitudinal
response; no acoustic sound-speed fit is attempted for Q6.

## Run

Rebuild is not required because this patch adds qualification scripts only.

```bash
LIVE_PROGRESS=1 \
bash scripts/run_0493w8_tg_mono_dual_equivalence.sh
```

Default size:

```text
grid    = 24 x 24
gamma   = 32
steps   = 300
dt      = 0.002
dumps    = every 10 steps
matrix  = 3 scenarios x 2 modes x 1 seed
```

The main outputs are:

```text
runs/0493w8_tg_mono_dual_equivalence/tg_0493w8_summary.csv
runs/0493w8_tg_mono_dual_equivalence/tg_0493w8_comparisons.csv
runs/0493w8_tg_mono_dual_equivalence/physics_0493w8_checks.csv
runs/0493w8_tg_mono_dual_equivalence/physics_0493w8.json
runs/0493w8_tg_mono_dual_equivalence/physics_0493w8.md
```

## Interpretation

A PASS establishes that:

- species registration and type duplication are neutral under SRC;
- independent masked Q6 has no material monoespecies TG regression relative to
  legacy Q6 on a full periodic support;
- two independently projected labels with identical physical properties retain
  the same effective Taylor–Green transport within the declared tolerances.

It does not calibrate a liquid/gas interface, resampling, sound speed under Q6,
or open-boundary behavior. Those are separate qualifications.

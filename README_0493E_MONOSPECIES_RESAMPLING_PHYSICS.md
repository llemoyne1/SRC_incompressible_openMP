# 0493e — mono-species resampling physics smoke

This is a validation-only patch. It does not modify `src/` or `include/`.

## Purpose

Before extending or further optimizing multi-species resampling, verify the
physical contract of the current CUDA-resident parallel path in its simplest
one-species specialization.

The test uses a periodic 16×8 grid with gamma=10 and a symmetric checkerboard
of 8/12 particles per cell. All fluid particles have type 1, unit mass, a
uniform mean velocity and paired zero-mean thermal perturbations.

Two runs start from the same state:

- `00_no_resampling`: one control step with mode `src`;
- `01_resampling_on`: ten steps with mode `src-resampling`, `speciesCount=1`
  and the production CUDA-resident species path.

Collision rotation is zero, the thermostat and grid shift are disabled, and
`dt=1e-7`, so the control case must retain the designed cell pattern. The
resampling run is then checked after step 1 and after step 10.

## Blocking checks

- total mass;
- total momentum and mean velocity;
- global relative kinetic energy;
- single fluid type only;
- reduction of cell population and mass variance after one step;
- reduction of cells outside the gamma±1 band;
- no variance blow-up over ten steps;
- nonzero 0490k/0490m activity;
- zero invalid operations and disabled-species mutations;
- zero donor-type group underfills for this balanced construction;
- species mass closure residual;
- active/inactive pool integrity.

The test is statistical/macroscopic. It deliberately does not require two
runs to follow the same particle trajectory bit-for-bit.

## Run

```bash
bash scripts/run_0493e_monospecies_resampling_physics_smoke.sh
```

Outputs are written to:

```text
runs/0493e_monospecies_resampling_physics/
```

Useful overrides:

```bash
SHORT_STEPS=10 LIVE_PROGRESS=1 THREADS=8 \
  bash scripts/run_0493e_monospecies_resampling_physics_smoke.sh
```

No rebuild is required.

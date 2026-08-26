# 0493h — periodic shear-wave physical qualification

## Purpose

0493e and 0493g validated the elementary mono- and two-species conservation
contracts of resident CUDA resampling. 0493h is the first dynamic transport
smoke test. It compares the same periodic mono-species shear wave with:

- `src`;
- `src-resampling` using the corrected 0493g population-guard moment restore.

The imposed initial mode is

```text
u_x(y,0) = U_mean + A0 sin(2 pi m y / Ly),   u_y = 0.
```

For viscous decay without forcing,

```text
A(t) = A0 exp(-nu_eff k^2 t),   k = 2 pi m / Ly.
```

The analyzer projects every dumped microscopic state onto the sine/cosine mode,
fits `log(A/A0)` and compares the effective viscosity and complete normalized
amplitude curve between the two methods. Exact trajectory identity is neither
expected nor required.

## Scope

Default campaign:

- periodic `32 x 32` grid;
- gamma `20`;
- 300 steps, `dt=0.002`;
- two collision RNG seeds;
- Q6, Darcy, walls, forcing and thermostat disabled;
- random SRC rotation sign and shifted collision grid enabled;
- one registered fluid species;
- paired zero-mean thermal perturbations;
- identical initial state for `src` and `src-resampling`.

This is intentionally a smoke test, not a precision viscosity measurement.
Thresholds are statistical and can be overridden through analyzer arguments.

## Blocking checks

For every seed and method:

- mass and total momentum conservation;
- total kinetic-energy conservation;
- positive shear decay with an acceptable logarithmic fit;
- expected initial Fourier amplitude.

For each paired comparison:

- normalized amplitude-curve RMS difference;
- endpoint-amplitude difference;
- effective-viscosity difference;
- phase difference.

For resampling:

- nonzero guard/transfer activity;
- no invalid operations or donor/type underfills;
- species mass closure;
- CUDA pool integrity.

## Files

Added only; no source modification and no rebuild:

- `scripts/run_0493h_periodic_shear_wave_physics.sh`
- `scripts/analyze_0493h_periodic_shear_wave_physics.py`
- `README_0493H_PERIODIC_SHEAR_WAVE_PHYSICS.md`

## Install

```bash
python3 /path/to/SRC_GPU_SURF_PATCH_0493H_PERIODIC_SHEAR_WAVE_PHYSICS/apply_patch_0493h.py .
```

## Run

```bash
LIVE_PROGRESS=1 \
bash scripts/run_0493h_periodic_shear_wave_physics.sh
```

For a one-seed preliminary run:

```bash
SEEDS="493081" LIVE_PROGRESS=1 \
bash scripts/run_0493h_periodic_shear_wave_physics.sh
```

Outputs are written under `runs/0493h_periodic_shear_wave_physics/`, including:

- `shear_wave_0493h_timeseries.csv`;
- `shear_wave_0493h_summary.csv`;
- `physics_0493h_checks.csv`;
- `physics_0493h.json`;
- `physics_0493h.md`.

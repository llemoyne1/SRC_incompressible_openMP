# Taylor--Green validation for filtered Q9

This validation compares the periodic high-SNR Taylor--Green case in three
modes:

- `classic`: baseline compressible SRC/MPCD,
- `q6`: velocity projection using the generic elliptic core,
- `q9`: Q6 followed by the filtered mass-flux projection.

The Q9 run uses the MATLAB-like elliptic low-pass target filter and does not use
a velocity-kick limiter.

## Scope

This is a periodic-box validation of the Q9 adapter. It deliberately avoids
walls, immersed solids, moving domains, virial closure and surface tension.

The purpose is to check that filtered Q9:

- keeps the Taylor--Green coherent mode measurable,
- does not introduce a catastrophic damping of the vortex amplitude,
- keeps Q6 divergence diagnostics at elliptic-solver accuracy,
- applies a weak filtered mass-flux correction,
- keeps temperature and global momentum stable.

## Initial state

Run from the `matlab/` directory:

```matlab
addpath('.')
generate_taylor_green_high_snr_short_state();
```

This writes, in the repository root:

```text
initial_state_tg_64x64_g80_u0p08_kbt0p01.smpcd
```

The deterministic Taylor--Green field is

```text
Ux = U0 sin(2*pi*x) cos(2*pi*y)
Uy = -U0 cos(2*pi*x) sin(2*pi*y)
```

with `U0 = 0.08`, `gamma = 80`, `kBT = 0.01`.

## Runs

Run from the repository root:

```bash
./build/src_mpcd_base examples/params_taylor_green_high_snr_classic_64x64_g80_short.kv
./build/src_mpcd_base examples/params_taylor_green_high_snr_q6_64x64_g80_short.kv
./build/src_mpcd_base examples/params_taylor_green_high_snr_q9_filtered_64x64_g80_short.kv
```

The Q9 parameters are intentionally close to the MATLAB reference strategy:

```text
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
```

## Analysis

Run from the `matlab/` directory:

```matlab
addpath('.')
out = validate_taylor_green_q9_filtered_short('makePlots', true, 'plotFinalFields', true);
```

Default run directories use `../runs/...`, assuming the script is launched from
`matlab/`.

The summary table reports, for each method:

- Taylor--Green modal amplitude and amplitude ratio,
- final correlation with the analytic TG pattern,
- divergence and vorticity reconstructed from dumps,
- runtime Q6 diagnostics,
- runtime Q9 residual, filter ratio and correction-velocity diagnostics,
- runtime `stdN` and `kBT`.

## Expected behavior

A healthy first Q9 validation should show:

- Q9 amplitude and correlation close to Q6,
- no temperature blow-up,
- Q9 residual near the requested elliptic tolerance,
- small Q9 correction velocities,
- filtered target ratio well below one.

This validation checks the Q9 adapter in a periodic setting only. The next
validation step is a channel/Poiseuille run with filtered Q9.

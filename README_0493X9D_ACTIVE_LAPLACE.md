# 0493x9d — first active Q6-G-F Laplace surface tension

This patch is incremental on top of 0493x9c + x9b-audit2.

## Physics added

A single physical parameter is added to `SimulationParams`:

```text
surfaceTensionSigma = 0.0
```

`0` is an exact production no-op.  Positive sigma is accepted only on the qualified CUDA `free_surface_masked + prestream_single_fused` Q6-G-F path.

The selected curvature is x9c **p3**:

```text
alpha_x6c
  -> binomial 3x3 pass 1
  -> binomial 3x3 pass 2
  -> binomial 3x3 pass 3
  -> Scharr normal
  -> Scharr div(normal) = kappa_p3
```

`alpha_x6c` itself is unchanged and still defines the x6f alpha=0.5 interface.

At each x6f physical crossing the same subcell theta is used to interpolate `kappa_p3`, then

```text
phiGamma_cap = dt / rhoLiquidRef * sigma * kappaGamma_p3
```

is added to the existing x6g Dirichlet potential.  With gas pressure active this is exactly the intended composition

```text
p_liquid - p_reference = (p_gas - p_reference) + sigma*kappa
```

No CSF/body-force term and no particle capillary kick are added.

## LiveVis

`curvature` and `kappa` now display the selected p3 field.  Historical p1 remains available as:

```text
curvature_x9b
kappa_x9b
curvature_p1
kappa_p1
```

Additional p3 aliases are `curvature_x9c`, `kappa_x9c`, `curvature_p3`, `kappa_p3`.

The resident field is copied/resampled directly on CUDA; there is no particle redeposit.

## First runner

`scripts/run_0493x9d_static_drop.sh` defaults to:

```text
400 x 400
gamma = 20
R/h = 40
sigma = 256
steps = 20
Q6-G-F density tau = 0.25
x6g gas EOS coupling = ON
LiveVis = ON, field=curvature (p3)
filtered recording = OFF
```

For the calibrated `a=1/256`, `kBT=0.125` setup, sigma=256 and R/h=40 give

```text
Delta p_Laplace = sigma/R = 1638.4
p_thermal = gamma*kBT/a^2 = 163840
Delta p_Laplace / p_thermal = 1%
```

This is deliberately conservative for the first active test.

The capillary boundary audit is written to:

```text
output/cuda_surface_tension_0493x9d.csv
```

It reports the p3 interface curvature and the capillary contribution `sigma*kappa` / `phiGamma_cap`.  The first x9d analyzer also reports liquid COM drift from the existing species diagnostics.  It does **not** yet claim a full static-drop pressure-field/spurious-current qualification; that is the next step after this active smoke.

## Apply and build

From the repository root:

```bash
python3 tools/apply_0493x9d_surface_tension.py
git diff --check
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

The apply script is idempotent and has no working-tree/Git cleanliness guard.

## Preflight

```bash
PREFLIGHT_ONLY=1 \
LIVE_VIS_ENABLE=0 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9d_static_drop.sh
```

## Optional sigma=0 no-op smoke

```bash
SIGMA=0 \
STEPS=1 \
LIVE_VIS_ENABLE=1 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9d_static_drop.sh
```

For sigma=0 the runner enables only passive p3 diagnostics so LiveVis can still show curvature; no capillary production branch is entered.

## First active run

```bash
SIGMA=256 \
R_CELLS=40 \
STEPS=20 \
LIVE_VIS_ENABLE=1 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9d_static_drop.sh
```

For inspection after the run:

```bash
RUN=runs/0493x9d_static_drop_400x400_g20_rc40_sigma256
head -n 2 "$RUN/output/cuda_surface_tension_0493x9d.csv"
tail -n 2 "$RUN/output/cuda_surface_tension_0493x9d.csv"
tail -n 4 "$RUN/output/species_runtime_0493x9d.csv"
cat "$RUN/static_drop_0493x9d.json"
```

## Current validation performed while generating the bundle

- semantic apply tested from a reconstructed x9c tree;
- apply is idempotent;
- generated x9d source matches the development tree byte-for-byte;
- `g++ -std=c++17 -Iinclude -fsyntax-only src/params_io_base.cpp`: PASS;
- `bash -n` on runner: PASS;
- Python analyzer/apply scripts: `py_compile` PASS;
- analyzer exercised on a synthetic Laplace audit/species CSV: PASS;
- whitespace diff check: PASS.

CUDA compilation cannot be run in the generation environment because CUDA/nvcc is not installed there.

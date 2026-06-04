# 0184 — Q6/elliptic GPU backend scaffold for `SRC_GPU`

This patch is intentionally conservative.  It does **not** add a GPU numerical
kernel yet.  It introduces the runtime and validation scaffolding needed before
moving the Q6/elliptic projection solver to a device backend.

Target working copy:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
git branch --show-current   # expected: SRC_GPU
```

The baseline remains `clean/openmp-light`; `clean/openmp-production-stripped` is
not touched by this GPU prototype.

## Why this patch is small

The audit identified the Q6/elliptic projection solve as the safest first GPU
candidate because it operates on regular cell/face arrays and can be compared
through existing physical diagnostics.  The particle deposit, SRC collision,
thermostat, resampling, and capacity/virial steps remain CPU OpenMP paths.

Patch 0184 only adds a backend selector around the Q6 projection path so later
patches can replace the hot elliptic kernels without perturbing the validated
CPU execution path.

## New runtime parameter

```text
projectionBackend = cpu
```

Accepted values are:

| value | behaviour in patch 0184 |
|---|---|
| `cpu` | default; use the existing validated OpenMP CPU path |
| `auto` | use a compiled GPU backend when one exists; in 0184, warn once and fall back to CPU |
| `openmp_target` | reserved for an OpenMP-target implementation; in 0184, fail explicitly |
| `cuda` | reserved for a CUDA implementation; in 0184, fail explicitly |

Aliases accepted by the parser:

```text
q6ProjectionBackend = ...
gpuProjectionBackend = ...
```

Hyphens are normalized to underscores, so `openmp-target` is accepted as
`openmp_target`.

## Safety rule

A requested GPU backend must not silently run as CPU.  Therefore:

- `projectionBackend=cpu` is the reference path;
- `projectionBackend=auto` is allowed to fall back to CPU, but emits a one-time
  message;
- `projectionBackend=openmp_target` and `projectionBackend=cuda` currently stop
  with an explicit error until the corresponding kernels exist.

This prevents false CPU/GPU validation.

## Smoke/validation script

A new helper runs a scaffold validation:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
bash scripts/run_gpu_projection_backend_scaffold_0184.sh
```

Default settings are deliberately short:

```text
NX=32, NY=32, GAMMA=12, STEPS=20, THREADS=4
CASE_LIST="tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full"
```

The script performs three checks:

1. run the four validation cases with `projectionBackend=cpu`;
2. run the same cases with `projectionBackend=auto`, which falls back to CPU in
   this scaffold;
3. compare `cpu` vs `auto` using `compare_validation_mono_config_0162.py`;
4. verify that `projectionBackend=openmp_target` fails explicitly while the
   backend is not implemented.

Outputs:

```text
runs/gpu_projection_backend_scaffold_0184_cpu/
runs/gpu_projection_backend_scaffold_0184_auto/
runs/gpu_projection_backend_scaffold_0184_openmp_target_requested/
validation_compare_gpu_backend_scaffold_0184.csv
validation_compare_gpu_backend_scaffold_summary_0184.csv
```

## Existing validation script extension

`scripts/run_validation_mono_config_0162.sh` now accepts:

```bash
PROJECTION_BACKEND=cpu|auto|openmp_target|cuda
```

It writes the selected value into generated `.kv` files as `projectionBackend`.
The default is `cpu`, so existing calls keep the validated CPU behaviour.

## Next patch direction

The next code-bearing GPU patch should still avoid particle mutation.  The first
real backend should target only the elliptic hot loop and reductions:

- `build_elliptic_operator_plan` stays CPU initially;
- `apply_elliptic_operator_plan_and_dot` becomes the first device candidate;
- CG vector updates and dot products are the second device candidate;
- face correction construction is considered only after the solver loop is
  validated.

Validation order:

1. `build/validate_elliptic_projection` CPU vs backend-specific executable or
   backend mode;
2. short `run_gpu_projection_backend_scaffold_0184.sh` equivalent with the new
   backend enabled;
3. full four-case validation at the 0162/0182 settings;
4. Von Kármán only after the four discriminant cases are stable.

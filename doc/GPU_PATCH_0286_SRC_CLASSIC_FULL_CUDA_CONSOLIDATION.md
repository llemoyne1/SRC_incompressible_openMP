# GPU patch 0286 — SRC classic full CUDA consolidation

Patch 0286 finalizes the current CUDA milestone of the `SRC_GPU` branch.

## Scope

The patch consolidates the **SRC classic** CUDA path:

```text
advection / streaming
+ random grid shift
+ SRC rotation / collision
+ cell-relative thermostat
```

It does **not** migrate the liquid closure to CUDA.  The liquid closure remains a separate layer:

```text
SRC classic + Q6 + weighted resampling + virial/capacity response
```

Q6, resampling and virial must therefore not be routed through classic-only fused fast paths.

## Files

```text
README.md
scripts/build_src_mpcd_cuda_0286.sh
scripts/run_cuda_src_classic_full_consolidated_0286.sh
scripts/run_demo_src_classic_cuda_all_0283.sh
scripts/run_demo_src_classic_cuda_all_0286.sh
doc/GPU_PATCH_0286_SRC_CLASSIC_FULL_CUDA_CONSOLIDATION.md
doc/GPU_SRC_CLASSIC_CUDA_STATUS_0286.md
doc/rapport_mpcd_incompressible_complete_0286_cuda_circle.tex
```

## Validation covered by 0286

The consolidated runner calls the already validated discriminant suites with the 0286 binary:

```text
0281 — wall / rectangle / piston / IO full-face / IO segmented thermostat consolidation
0284 — periodic immersed circle
0285 — immersed circle + full-face inlet/outlet
```

Run:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_src_classic_full_consolidated_0286.sh
```

Expected summary:

```text
result=PASS
errors=none
```

## Demonstrations

Run all animation-oriented demonstrations:

```bash
bash scripts/run_demo_src_classic_cuda_all_0286.sh
```

The Von Karman cylinder demonstration now uses the 0285 path:

```text
full-face inlet/outlet resident CUDA
+ circular immersed solid CUDA
+ persistent CUDA SRC collision
+ fused CUDA thermostat
```

## Architecture note

The key thermostat invariant remains:

```text
SRC collision mean     = real particles + wall/solid virtual particles when needed
thermostat mean        = real post-collision particles only
```

For classic-only CUDA paths, the fused order is valid:

```text
CUDA boundary/streaming -> CUDA SRC collision -> CUDA thermostat
```

For runs with Q6, resampling, virial or capacity response between collision and thermostat, the fused path must be disabled and the post-CPU CUDA thermostat path must be used instead.

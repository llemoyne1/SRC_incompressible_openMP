# GPU patch 0291b — `thermostatEnable` gates CPU and CUDA thermostats

## Purpose

Patch 0291 introduced explicit outlet regimes (`neumann`, `equilibrium_flux`,
`forced_flux`).  During tests of the same-face inlet/outlet demo, it became clear
that CUDA thermostat environment flags could still request the persistent fused
SRC+thermostat backend even when the physical parameter file did not explicitly
control the thermostat.

Patch 0291b makes the rule explicit:

```text
thermostatEnable = true   -> CPU or CUDA thermostat may run, depending on backend flags
thermostatEnable = false  -> no thermostat is applied, neither CPU nor CUDA
```

CUDA environment variables now only select the accelerated backend.  They no
longer override the physical `thermostatEnable` parameter.

## Code changes

- `src/src_collision.cpp`
  - `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1` is interpreted as a backend
    request only when `params.thermostatEnable=true`.
  - The shared 0251 -> 0260 fused thermostat consumer is also gated by the
    actual per-step thermostat application condition.
  - Therefore, `thermostatEnable=false` cannot trigger the persistent CUDA
    thermostat or the stale shared-state fatal error in the thermostat branch.

- `scripts/src_gpu_demo_common_0283.sh`
  - adds `THERMOSTAT_ENABLE`, default `1`;
  - writes the matching `thermostatEnable = true|false` field into generated
    `.kv` files;
  - gates `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE` and
    `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260` consistently.

- `scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh`
  - exposes `THERMOSTAT_ENABLE` for the same-face inlet/outlet demo.

## Build

```bash
bash scripts/build_src_mpcd_cuda_0291b.sh
```

This creates by default:

```text
build/src_mpcd_base_cuda_0291b
```

## Examples

Isothermal forced extraction:

```bash
THERMOSTAT_ENABLE=1 \
OUTLET_MODE=forced_flux \
OUTLET_FORCED_PARTICLES_PER_STEP=200 \
OUTLET_FORCED_LAYER_CELLS=3 \
BIN=build/src_mpcd_base_cuda_0291b \
UIN=0.0 STEPS=15000 DUMP_STATE_EVERY=100 SUMMARY_EVERY=100 \
bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

Free or adiabatic-like forced extraction without thermostat:

```bash
THERMOSTAT_ENABLE=0 \
OUTLET_MODE=forced_flux \
OUTLET_FORCED_PARTICLES_PER_STEP=200 \
OUTLET_FORCED_LAYER_CELLS=3 \
BIN=build/src_mpcd_base_cuda_0291b \
UIN=0.0 STEPS=15000 DUMP_STATE_EVERY=100 SUMMARY_EVERY=100 \
bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

## Scope

The patch does not modify Q6, resampling, virial/capacity response or the outlet
extraction algorithm.  It only enforces a consistent thermostat switch across CPU
and CUDA execution paths.

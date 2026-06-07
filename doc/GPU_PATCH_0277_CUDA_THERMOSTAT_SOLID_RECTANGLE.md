# GPU patch 0277 — CUDA thermostat for static rectangular immersed solids

## Scope

Patch 0277 opens the second validation step of the wall/solid/piston/inlet-outlet
aware CUDA thermostat campaign. It targets the static rectangular immersed-solid
case used by the previous classic SRC resident validation 0262.

The patch deliberately does not change the CUDA thermostat kernels. The physical
correction introduced by 0276 is already the required one for a static solid:
after CUDA SRC collision, thermostat cell moments are rebuilt from real particles
only, excluding virtual wall/solid contributions used by the collision operator.

## Files

- `scripts/build_src_mpcd_cuda_0277.sh`
- `scripts/run_cuda_persistent_src_thermostat_solid_0277.sh`
- `scripts/run_cuda_persistent_src_thermostat_wall_0276.sh`

The 0276 runner is included only to fix the CSV formatting issue where the
`compareSummary` field was emitted on a continuation line.

## Validation design

The validator compares:

1. CPU streaming/reflection + CPU classic SRC + CPU thermostat;
2. CUDA periodic streaming + CUDA static rectangle reflection + CUDA persistent
   classic SRC + CUDA persistent thermostat.

Q6, resampling and virial are disabled in this validator only. The persistent
thermostat path still rejects projection/capacity/virial interleavings so that
future CPU Q6/OpenMP, resampling CUDA/CPU and Q6 CUDA can be reactivated without
being silently bypassed.

`MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=1` is set in the CUDA validation mode
as a compatibility switch required by the existing 0245/0247 periodic+rectangle
streaming kernels. The old 0262 monolithic classic-only resident shortcut remains
inactive because `THERMOSTAT_ENABLE=true`.

## Suggested runs

Smoke:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o SRC_GPU_0277_cuda_thermostat_solid_rectangle_files_only.zip
bash scripts/build_src_mpcd_cuda_0277.sh

GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_solid_0277.sh
```

Extended short validation:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_solid_0277.sh
```

Expected CSV:

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_solid_0277/cuda_persistent_src_thermostat_solid_0277.csv
```

Expected criteria:

- `verdict=PASS`
- `failed_metrics=0`
- `thermostatGpuAppliedFraction=1`
- `thermostatKBTAfterMean` close to the thermostat target
- no continuation row after each validation row

## Next steps

If 0277 passes, the same pattern can be extended to:

1. piston/mobile wall;
2. inlet/outlet full-face;
3. inlet/outlet segmented;
4. finally, a consolidated wall/solid/piston/IO thermostat validator.

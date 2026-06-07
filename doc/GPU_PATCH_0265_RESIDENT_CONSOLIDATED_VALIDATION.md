# GPU patch 0265 — consolidated short validation for CUDA resident classic SRC

## Scope

Patch 0265 adds a short consolidated validation runner for the CUDA resident
classic SRC stack. It does not change the physical kernels or boundary-condition
logic. The objective is to replay the validated resident families with modest
run lengths and to produce one global manifest CSV.

The suite covers:

- 0260 periodic resident classic SRC;
- 0261 wall-simple resident classic SRC;
- 0262 immersed rectangle / solid resident classic SRC;
- 0255 piston/mobile-wall legacy resident collision check;
- 0263d full-face inlet/outlet resident classic SRC;
- 0264 segmented inlet/outlet resident classic SRC.

## Files

- `scripts/build_src_mpcd_cuda_0265.sh`
- `scripts/run_cuda_classic_src_resident_consolidated_0265.sh`
- `doc/GPU_PATCH_0265_RESIDENT_CONSOLIDATED_VALIDATION.md`

## Default run lengths

The default consolidated pass uses:

```bash
SHORT_GRID_CASES="64:64:180"
PISTON_GRID_CASES="64:64:120"
```

These defaults are intended to be short enough for frequent terminal validation
while still exercising the distinct boundary-condition families.

For a stronger pass without modifying the script, override the grids, for
example:

```bash
SHORT_GRID_CASES="64:64:220 128:128:120" \
PISTON_GRID_CASES="64:64:160" \
bash scripts/run_cuda_classic_src_resident_consolidated_0265.sh
```

## Usage

```bash
bash scripts/run_cuda_classic_src_resident_consolidated_0265.sh
```

The global manifest is written to:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_0265/cuda_classic_src_resident_consolidated_0265.csv
```

Each family keeps its own detailed CSV and logs under the same artifact root.

## Architectural constraints preserved

The 0260--0264 validators remain classic-only by design: Q6, resampling, virial
and thermostat paths are disabled for those validation runs. This is not an
architectural lock. Future reactivation of CPU Q6 and resampling must remain
possible through explicit host/GPU synchronization points.

The CUDA thermostat remains a separate future chantier. The periodic fused
thermostat validated earlier must not be generalized blindly to wall, solid,
piston or inlet/outlet configurations.

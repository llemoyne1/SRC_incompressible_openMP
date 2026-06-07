# GPU patch 0281 — consolidated CUDA thermostat validation

## Scope

Patch 0281 consolidates the CUDA thermostat work package opened after 0259. It adds no new CUDA kernel and no Q6 CUDA implementation. It provides a single validation wrapper and an updated state document for the physical SRC classic CUDA thermostat paths.

Expected base: branch `SRC_GPU` after patches 0276, 0277, 0278 and 0280c.

## Validated thermostat paths

| Patch | Case family | Physical order | Status |
|---|---|---|---|
| 0276 | wall-simple / Poiseuille | CUDA wall streaming + CUDA SRC + fused CUDA thermostat | validated |
| 0277 | immersed solid rectangle | CUDA solid/wall handling + CUDA SRC + fused CUDA thermostat | validated |
| 0278 | piston / mobile wall | CUDA SRC, then CPU Q6/resampling/virial/capacity, then CUDA post-CPU thermostat | validated |
| 0279b | full-face inlet/outlet | resident CUDA full-face IO + CUDA SRC + fused CUDA thermostat | validated after 0280c guard fix |
| 0280c | segmented inlet/outlet | resident CUDA segmented IO + CUDA SRC + fused CUDA thermostat | validated |

## Design invariant

The thermostat must use real-particle post-collision moments. Collision means may include virtual wall/solid particles; thermostat means must not. This is the key fix introduced in 0276 and reused by the wall and solid cases.

For classic-only resident cases, the fused CUDA path is valid:

```text
CUDA boundary/streaming -> CUDA SRC collision -> CUDA thermostat
```

For cases where CPU stages may change velocities or masses after collision, the fused path is intentionally not used:

```text
CUDA SRC collision -> CPU Q6/resampling/virial/capacity -> CUDA post-CPU thermostat
```

This preserves future reactivation of Q6 CPU/OpenMP, resampling CUDA/CPU, virial response, and later Q6 CUDA.

## Consolidated run

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
bash scripts/build_src_mpcd_cuda_0281.sh

GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_consolidated_0281.sh
```

Outputs:

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_consolidated_0281/cuda_persistent_src_thermostat_consolidated_0281.csv
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_consolidated_0281/cuda_persistent_src_thermostat_consolidated_0281_summary.txt
```

## Expected discriminants

All rows must satisfy:

- `verdict=PASS`;
- `failed_metrics=0`;
- `compared_metrics>0`;
- wall/solid/full-face/segmented: `thermostatGpuAppliedFraction=1`;
- piston: `fusedSrcThermostatUse=0`, `postCpuThermostatPersistent0258=1`, `thermostatActiveCalls>0`;
- full-face: `ioFullfaceResidentFlag=1`, `fusedSrcThermostatUse=1`;
- segmented: `ioSegmentedResidentFlag=1`, `fusedSrcThermostatUse=1`;
- `thermostatKBTAfterMean` at target.

## Notes

This patch intentionally avoids changing the architecture around Q6/resampling/virial. It validates the full CUDA SRC classic thermostat coverage and leaves the later Q6 CUDA migration as a separate major work package.

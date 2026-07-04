# 0455 — CUDA resampling device-carrier apply path

0455 removes the compact host operation vector from the particle-edit carrier used by the experimental CUDA apply backend.

The guarded path is enabled with:

```bash
MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1
```

The intended validation stack is:

```text
0451 upstream apply-gate
+ 0455 device materialization of donor-particle passive operations
+ 0455 direct device-carrier extraction/insertion apply
+ 0448 remap + thermal CUDA apply backend
```

The host still receives a diagnostic mirror of the compact operation list so that the CPU/GPU operation gate remains strict.  This mirror is no longer the carrier consumed by the extraction/insertion apply kernels.  Therefore 0455 is a transition patch: it removes the host compact vector from the mutating carrier but does not remove all host diagnostics or global orchestration.

Initial scope is deliberately restricted to periodic, wall-free, no-solid, nonzero-plan cases.

## Smoke

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0455 \
BASE_DEVICE_CARRIER_ROOT=runs/0455_device_carrier_smoke \
STEPS=20 \
SUMMARY_EVERY=1 \
RUN_MODES="src-resampling src-q6-resampling" \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0455_device_carrier_smoke.sh
```

Expected report:

```bash
cat runs/0455_device_carrier_smoke/device_carrier_report_0455.md
```

Pass criteria:

```text
PASS-like modes = 2/2
cpuOps = gpuOps > 0
extractionApplied = insertionApplied = gpuOps
invalidMaterializeOps = 0
invalidApplyOps = 0
opMismatch = 0
duplicateParticleMismatch = 0
mass/Px/Py/KE operation deltas at roundoff
CPU baseline vs CUDA device-carrier final summary delta <= 1e-9
```

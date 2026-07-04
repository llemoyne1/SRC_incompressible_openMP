# 0463 CUDA/CPU scaling probe for sparse-gate resampling

This runner benchmarks the 0461 sparse device-carrier gate and 0460 Thrust stable cell-list materializer against the CPU baseline across grid/particle scales.

The runner wraps `scripts/run_0462_sparse_gate_stress.sh` for multiple `(Nx, Ny, gamma)` cases. It passes both uppercase and mixed-case `NX/Nx`, `NY/Ny`, and `GAMMA/gamma` variables to remain compatible with the existing 0446 nonzero-plan generator.

Default scale cases:

```bash
SCALE_CASES="64x64x40 96x96x40 128x128x40"
```

The output report is:

```bash
runs/0463_scaling_cuda_vs_cpu/scaling_cuda_vs_cpu_report_0463.md
```

The key metric is `CPU/CUDA speedup`, computed from the last `wallTime` in the CPU and CUDA `summary_runtime.csv` files.

For a quick exploratory pass:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0461a \
BASE_SCALE_ROOT=runs/0463_scaling_cuda_vs_cpu \
SCALE_CASES="64x64x40 96x96x40 128x128x40" \
STEPS=200 \
SUMMARY_EVERY=50 \
DEVICE_GATE_EVERY=50 \
SEEDS="1628638" \
LIVE_PROGRESS=1 \
RUN_MODES="src-resampling src-q6-resampling" \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0463_scaling_cuda_vs_cpu.sh
```

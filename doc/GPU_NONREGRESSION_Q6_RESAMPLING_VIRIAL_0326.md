# GPU SRC/MPCD 0326 — non-regression Q6/resampling/virial smoke harness

This patch is script-only.  It does not modify C++/CUDA solver sources and does not build by default.

Purpose after the validated 0318b–0322 performance work and the rejected 0325 rollback:

- verify that Q6 still runs;
- verify that resampling still runs;
- verify that the hybrid CUDA classic SRC + Q6 + resampling path still runs;
- verify that piston closed-capacity + virial still runs;
- verify that rejected 0325 code is absent from the working tree.

Default smoke targets:

```text
q6_only_tg
resampling_only_tg
hybrid_cuda_q6_resampling_tg
hybrid_cuda_piston_virial
```

Default size is deliberately small: `NX=32 NY=32 STEPS=80 GAMMA=20`.

Main command:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
SRC_BUILD=0 VKKH_BUILD=0 \
NX=32 NY=32 STEPS=80 REPEATS=1 INACTIVE_SLOTS=100000 \
bash scripts/run_gpu_nonregression_q6_resampling_virial_0326.sh
```

If the current binary is missing, build once with:

```bash
SRC_BUILD=1 bash scripts/run_gpu_nonregression_q6_resampling_virial_0326.sh
```

Important outputs:

```text
dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326/gpu_nonregression_q6_resampling_virial_0326_manifest.csv
dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326/gpu_nonregression_q6_resampling_virial_0326_summary.csv
dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326/working_tree_0325_grep.txt
```

Expected 0325 check:

```text
working tree OK: no 0325
```

Expected summary criterion: all rows should have `verdict=PASS`.

# GPU non-regression Q6 / resampling / virial — 0326b

0326b is a script-only correction to the 0326 non-regression harness. It does not modify the solver.

The 0326 failures were guard failures caused by an invalid smoke configuration, not by the physics modules themselves:

- Q6/resampling with CUDA persistent SRC+thermostat is unsupported because Q6 modifies velocities on the CPU between collision and thermostat.
- The piston/closed-capacity case needs `MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255=1` when using CUDA persistent collision.

0326b therefore tests the intended hybrid architecture:

```text
CUDA persistent collision only -> CPU Q6/resampling/virial -> CPU thermostat
```

For piston/closed-capacity virial, 0326b also enables the resident piston collision subset 0255.

## Usage

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o /path/to/gpu_nonregression_q6_resampling_virial_0326b_files_only.zip -d .

SRC_BUILD=0 \
NX=32 NY=32 STEPS=80 GAMMA=20 INACTIVE_SLOTS=100000 \
bash scripts/run_gpu_nonregression_q6_resampling_virial_0326b.sh
```

## Expected outputs

```text
dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326b/gpu_nonregression_q6_resampling_virial_0326b_manifest.csv
dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326b/gpu_nonregression_q6_resampling_virial_0326b_summary.csv
dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326b/working_tree_0325_grep.txt
```

Expected verdict: all four rows PASS, and `working tree OK: no 0325`.

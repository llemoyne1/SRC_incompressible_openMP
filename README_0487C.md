# 0487c run_ok livevis default binary only

Minimal fix from the scripts supplied by the user: only replace the default run_ok binary from
`build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484` to
`build/src_mpcd_base_cuda_q6_resident_livevis_0486`.

No run parameters, modes, livevis options, recording options, topology settings, CUDA flags,
or case-generator logic are changed.

Apply:

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-INTEG
unzip -o /path/to/SRC_GPU_0487C_RUN_OK_LIVEVIS_BINARY_ONLY.zip -d .
git apply patches/0487c_run_ok_livevis_default_binary_only.diff
bash -n scripts/src_mpcd_run_common_0434.sh
for f in scripts/run_ok*.sh; do bash -n "$f"; done
git diff --check
```

Test:

```bash
unset BIN SRC_MPCD_DEFAULT_BIN_0434
bash scripts/run_ok_injection_type1_into_type2_empty.sh
```

The command should use `build/src_mpcd_base_cuda_q6_resident_livevis_0486` by default and open livevis,
assuming that binary has already been built.

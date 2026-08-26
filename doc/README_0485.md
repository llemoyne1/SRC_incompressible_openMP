# 0485 — run_ok latest-code wiring

Scope: update the eight `scripts/run_ok_*.sh` launchers and their common dependency
`scripts/src_mpcd_run_common_0434.sh` so they target the current 0484 production
resident binary and expose a reliable single-mode override.

Changes:

- default binary moves from
  `build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0477`
  to
  `build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484`;
- the default can be globally changed with
  `SRC_MPCD_DEFAULT_BIN_0434=build/<other-binary>`;
- `MODES="..."` is accepted as an alias for `RUN_MODES="..."` for ad-hoc targeted
  runs;
- all eight run_ok scripts iterate through `suite_mode_list_0434`, avoiding local
  mode parsing drift;
- environment dumps now record `MODES` and `SRC_MPCD_DEFAULT_BIN_0434`.

The patch assumes 0484 production-strip changes are already applied.

Apply:

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-INTEG
unzip -o /path/to/SRC_GPU_0485_RUN_OK_LATEST_CODE_DIFF.zip -d .
git apply patches/0485_run_ok_latest_code.diff

bash -n scripts/src_mpcd_run_common_0434.sh
for f in scripts/run_ok*.sh; do bash -n "$f"; done

git diff --check
```

Minimal no-surprise smoke after the 0484 binary already exists:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484 \
AUTO_BUILD=0 BUILD_IF_STALE=0 FORCE_BUILD=0 \
LIVE_VIS_ENABLE=0 FILTERED_RECORDING_ENABLE=0 \
MODES='src-resampling' \
NX=64 NY=64 GAMMA=40 STEPS=20 SUMMARY_EVERY=20 LIVE_PROGRESS=1 \
bash scripts/run_ok_tg.sh
```

Expected solver count for this smoke: exactly 1 run.

Commit:

```bash
git add scripts/run_ok_bend_pipe.sh \
        scripts/run_ok_injection_type1_into_type2_empty.sh \
        scripts/run_ok_io_box_same_face.sh \
        scripts/run_ok_naca.sh \
        scripts/run_ok_poiseuille.sh \
        scripts/run_ok_step.sh \
        scripts/run_ok_tg.sh \
        scripts/run_ok_vk.sh \
        scripts/src_mpcd_run_common_0434.sh

git commit -m "0485: wire run_ok scripts to latest resident code"
```

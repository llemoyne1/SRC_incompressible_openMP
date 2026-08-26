# SRC_GPU 0486 livevis builder

Files:

- `scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh`
- `scripts/run_0486_livevis_tg_smoke.sh`
- `doc/RESIDENT_LIVEVIS_BUILD_0486.md`

Usage:

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-INTEG
unzip -o /chemin/vers/SRC_GPU_0486_LIVEVIS_BUILDER.zip -d .
chmod +x scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh \
         scripts/run_0486_livevis_tg_smoke.sh

CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

BIN=build/src_mpcd_base_cuda_q6_resident_livevis_0486 \
RUN_MODES='src-resampling' \
LIVE_VIS_ENABLE=1 \
bash scripts/run_0486_livevis_tg_smoke.sh
```

Commit after successful build/smoke:

```bash
git add scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh \
        scripts/run_0486_livevis_tg_smoke.sh \
        doc/RESIDENT_LIVEVIS_BUILD_0486.md

git commit -m "0486: add livevis resident CUDA builder"
```

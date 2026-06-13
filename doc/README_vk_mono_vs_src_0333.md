# 0333 — VK full-periodic monolithic vs SRC_GPU benchmark

Purpose: compare the current generic `SRC_GPU` CUDA path against the specialized monolithic `mpcd_vkkh_play` code on a matched VK periodic cylinder case.

The benchmark is intentionally full-periodic (`bcLeft/right/bottom/top = periodic`) because the monolithic `streaming_wrap_kernel` wraps both coordinates when `--xInletInject 0` is used. Heavy outputs are disabled on both sides.

## Files

- `external_benchmarks/mpcd_vkkh_play_timed_0333.cu`
  - copy of the supplied monolithic code with an internal timer around the main time loop.
  - prints `BENCH_STEPS`, `BENCH_LOOP_SECONDS`, `BENCH_MS_PER_STEP`.
- `scripts/run_vk_full_periodic_mono_vs_src_0333.sh`
  - builds/runs the monolithic code and runs matched SRC cases.
- `scripts/analyze_vk_full_periodic_mono_vs_src_0333.py`
  - parses timing outputs and writes summary/ratio tables.

## Default matched parameters

```text
Lx=1.5 Ly=0.4 Nx=360 Ny=19 gamma=20
steps=5000 dt=0.0005 alpha=90deg/pi/2
U0=0.051 kBT=5 thermostat=1 keepMeanFlow=false
cylinder: xc=0.25 yc=0.205 Rc=0.04
seed=1628505
```

The SRC initializer creates exactly `round(gamma*Nx*Ny)` active fluid particles outside the cylinder, matching the monolithic initialization strategy more closely than a per-active-cell generator.

## Cases

- `MONO_ANALYTIC_SPECULAR`: monolithic, `--xInletInject 0 --solid 0 --bbEn 1 --bbEt 1`.
- `SRC_CLASSIC_NINACT0`: generic SRC classic CUDA, no inactive reservoir.
- `SRC_CLASSIC_NINACT750000`: generic SRC classic CUDA with inactive reservoir only.
- `SRC_RESAMPLING_NINACT750000`: generic SRC classic CUDA plus CUDA post-SRC resampling flags.

Optional historical monolithic solid-particle benchmark:

```bash
RUN_MONO_SOLID_DEFAULT=1 bash scripts/run_vk_full_periodic_mono_vs_src_0333.sh
```

## Typical command

```bash
OUT=build/src_mpcd_base_cuda_vkbench_0333 bash scripts/build_src_mpcd_cuda_0315b.sh

SRC_BIN=build/src_mpcd_base_cuda_vkbench_0333 \
AUTO_BUILD_SRC=0 \
AUTO_BUILD_MONO=1 \
REPS=3 \
STEPS=5000 \
INACTIVE_SLOTS_RESAMPLING=750000 \
bash scripts/run_vk_full_periodic_mono_vs_src_0333.sh
```

## Outputs

The artifact directory contains:

- `manifest.txt`
- `mono_runs_0333.tsv`
- `src_runs_0333.tsv`
- `vk_mono_vs_src_0333_summary.tsv`
- `vk_mono_vs_src_0333_ratios.tsv`
- `analyze_vk_full_periodic_mono_vs_src_0333.stdout.txt`
- individual stdout/time files for each run.

The decisive ratio is `ms_per_step_internal_mean` for each SRC case divided by the monolithic `MONO_ANALYTIC_SPECULAR` internal `BENCH_MS_PER_STEP`.

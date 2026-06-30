# README_0425_IO_ABLATION — Backward-step fullface/segmented ablation

## Purpose

This bundle adds two cross-tests to isolate the backward-step performance gap:

1. **Darcy + full-face IO**
   Uses the Darcy/chi model but replaces segmented inlet/outlet by full-face `bcLeft=inlet`, `bcRight=outlet`.

2. **Solid + segmented IO**
   Uses the immersed rectangle solid treatment but replaces full-face IO by segmented inlet/outlet.

Together with the existing scripts, this gives four cases:

```text
solid_fullface     = current solid script, full-face IO + immersed rectangle
solid_segmented    = new script, segmented IO + immersed rectangle
darcy_segmented    = current Darcy script, segmented IO + chi/Darcy
darcy_fullface     = new script, full-face IO + chi/Darcy
```

The uploaded/current solid script uses full-face inlet/outlet and an immersed rectangle by default; the uploaded/current Darcy script uses segmented inlet/outlet and `mean_outward_bath + chiVP`. This bundle starts from those two scripts.

## Files

```text
scripts/run_src_classic_cuda_darcy_chi_backward_step_fullface_0425.sh
scripts/run_portable_backward_step_solid_segmented_0425.sh
scripts/run_backward_step_io_ablation_0425.sh
doc/README_0425_IO_ABLATION.md
```

## Recommended run

Use a short 1000-step performance ablation first:

```bash
STEPS=1000 LIVE_VIS_ENABLE=0 bash scripts/run_backward_step_io_ablation_0425.sh
```

The launcher writes:

```text
runs/backward_step_io_ablation_0425/backward_step_io_ablation_manifest_0425.csv
```

Default model for Darcy cases:

```bash
DARCY_BRINKMAN_FORCING_MODE=mean_outward_bath
DARCY_CHI_COLLISION_VP_ENABLE=true
DARCY_CHI_COLLISION_VP_STRENGTH=0.25
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.05
TOPO_BENCHMARK_ENABLE=false
DARCY_COST_EVERY=1000000
```

## Interpretation

Expected diagnostic logic:

```text
If solid_segmented becomes slow:
    segmented IO is the main culprit.

If darcy_fullface remains slow:
    Darcy/chi itself is the main culprit.

If darcy_fullface becomes close to solid_fullface:
    segmented IO + Darcy interaction is likely the bottleneck.

If both solid_segmented and darcy_fullface are intermediate:
    the total slowdown is split between IO path and Darcy/chi path.
```

## Notes

The Darcy full-face script is an intentional performance ablation. It is not the cleanest physical inlet for a backward step because full-face injection includes the lower-left region that is solid in the chi field. Use it to isolate runtime, not to validate final physics.


## 0425b-fixed1

Fix in `run_portable_backward_step_solid_segmented_0425.sh`:

```text
run_mode_0315 now calls portable_cuda_io_segmented_rect_0425
instead of portable_cuda_io_fullface_rect_0315.
```

This ensures that the `solid_segmented` ablation actually uses the segmented IO path.

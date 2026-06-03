# 0136B — Backward-step MATLAB analysis call fix

This small follow-up patch fixes the MATLAB post-processing call to `bin_smpcd_state` in `analyze_backward_step_resampling_0136.m`.

`bin_smpcd_state` uses name-value arguments:

```matlab
bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny, ...)
```

The original 0136 analyzer called it with positional grid arguments:

```matlab
bin_smpcd_state(state, opt.Lx, opt.Ly, opt.Nx, opt.Ny, 'fluidOnly', true)
```

which triggers:

```text
Expected a string scalar or character vector for the parameter name.
```

The fixed call also sets

```matlab
'periodicX', false, 'periodicY', false
```

which is appropriate for the backward-facing step open-channel analysis.

## Usage

From the repository root:

```bash
mkdir -p /tmp/openmp_patch_0136b
unzip /path/to/openmp_resampling_backward_step_analysis_fix_0136b_files_only.zip -d /tmp/openmp_patch_0136b
rsync -av /tmp/openmp_patch_0136b/openmp_resampling_backward_step_analysis_fix_0136b_files_only/ ./
```

Then from MATLAB, typically from the `matlab/` directory:

```matlab
analyze_backward_step_resampling_0136('../runs/backward_step_resampling_0136');
```

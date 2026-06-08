# 0305 geometry diagnostics runner fix

This small follow-up fixes the geometry diagnostics runner so that stdout/stderr
redirection paths are created before launching each demo case.

The previous runner wrote logs such as
`dev_history/artifacts/gpu_cuda_resampling_geometry_diagnostics_0305/backward_step/classic_flag.stdout.log`
before creating the parent directory `.../backward_step`.  Bash therefore failed
at redirection time, before the demo script could create its own `RUN_ROOT`
subdirectories.

No C++ code or CUDA kernel is changed.  The diagnostic algorithm, outputs and
case selection remain unchanged.

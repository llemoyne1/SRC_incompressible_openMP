# CUDA thermostat status after 0280c / 0281

## Summary

The CUDA thermostat is now physically validated across the SRC classic CUDA boundary families that were previously missing after 0259:

- periodic/TG: already validated in 0259/0260;
- wall-simple: validated in 0276;
- immersed rectangle / solid obstacle: validated in 0277;
- piston / mobile wall: validated in 0278 using the post-CPU thermostat path;
- full-face inlet/outlet: validated in 0279b after the 0280c resident guard fix;
- segmented inlet/outlet: validated in 0280c.

## Important implementation distinction

The fused CUDA SRC+thermostat path is valid only when no CPU stage modifies the particle velocities or masses between SRC collision and thermostat application.

For classic-only cases:

```text
boundary/streaming CUDA -> SRC CUDA -> thermostat CUDA
```

For Q6/resampling/virial/capacity cases:

```text
SRC CUDA -> CPU correction stage(s) -> thermostat CUDA post-CPU
```

This separation is required for piston and must also be preserved when Q6/resampling/virial are reactivated in more complex inlet/outlet or obstacle cases.

## Guards to preserve

Do not relax the classic-only fused guards to bypass Q6/resampling/virial. If those stages are active, the correct target is the post-CPU persistent thermostat path, not the fused collision thermostat path.

Do not remove the possibility of future Q6 CUDA. The present work only finalizes physical SRC classic CUDA thermostat coverage.

## Consolidated validator

Use:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_consolidated_0281.sh
```

The wrapper runs the existing 0276, 0277, 0278, 0279b and 0280c validators and emits a normalized CSV summary.

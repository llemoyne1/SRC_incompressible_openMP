# GPU patch 0259 wall guard — classic SRC CUDA mode

This runner-only fix keeps the durable `srcClassicCudaModeEnable=true` path but restricts the fused collision+thermostat validation to the periodic TG case by default.

Observed failure: `0259_classic_cuda_fused_thermostat` passed `tg_periodic_full` but failed `poiseuille_wall_full` with 10/76 metric failures, while `0257_classic_cuda_collision_cpu_thermostat` passed the same wall case.

Interpretation: the Q6/virial short-circuit is correct. The too-broad piece is the fused thermostat path on wall/boundary cases. Until a wall-aware fused thermostat is implemented and validated, non-periodic cases should use CUDA collision with the existing deterministic CPU thermostat.

Default runner behavior after this fix:

- `tg_periodic_full`: runs both `0257_classic_cuda_collision_cpu_thermostat` and `0259_classic_cuda_fused_thermostat`.
- `poiseuille_wall_full`, `open_rect_obstacle_full`, `piston_virial_full`: run `0257_classic_cuda_collision_cpu_thermostat` only.

Experimental override:

```bash
RUN_FUSED_THERMOSTAT_ALL=1 \
  bash scripts/run_cuda_classic_src_mode_0259.sh
```

Use the override only for debugging; failures on wall/solid/piston cases are expected until the fused thermostat is extended to those boundary models.

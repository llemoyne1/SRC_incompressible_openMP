# 0131B — Poiseuille wallVP projection operator fix

This small follow-up patch fixes the Poiseuille wallVP validation script introduced in 0131.

The current SRC/Q6 baseline accepts the projection operators:

```text
periodic_fv_cg
channel_fv_cg
auto_fv_cg
elliptic_fv_cg
```

The 0131 script was writing the obsolete operator name:

```text
periodic_x_wall_y_fv_cg
```

For the periodic-x / solid-y Poiseuille channel, the correct default is now:

```text
projectionOperator = channel_fv_cg
```

The script also exposes an override:

```bash
POIS_PROJECTION_OPERATOR=auto_fv_cg ./scripts/run_poiseuille_wallvp_resampling_validation_0131.sh
```

The recommended default remains `channel_fv_cg`.

## Quick run

Generate the initial state from MATLAB if needed, then from the repository root:

```bash
./scripts/build_src_mpcd_base.sh

POIS_BODY_ACCEL=0.05 \
POIS_STEPS=5000 \
POIS_DUMP_EVERY=250 \
POIS_THREADS=8 \
./scripts/run_poiseuille_wallvp_resampling_validation_0131.sh
```

Note the variable name is `POIS_BODY_ACCEL`, not `OIS_BODY_ACCEL`.

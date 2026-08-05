# 0493x4b — CUDA fusion of the Q6-g force projection

## Purpose

0493x4a established that the force-aware incompressible ordering needs only one
Q6 solve per time step:

```text
force kick -> Q6 -> stream -> collision -> thermostat
```

The remaining standalone force-kick kernel still scans and rewrites the active
particle prefix before the Q6 deposit.  0493x4b removes that pass while keeping
0493x4a available as the physical and numerical reference.

## New opt-in mode

```text
q6ForceProjectionMode = prestream_single_fused
```

`legacy`, `prestream`, and `prestream_single` are unchanged.  The default remains
`legacy`.

The fused mode is restricted by the same validation contract as the other
non-legacy force-projection tests: CUDA resident Q6, periodic or static closed
box, `speciesQ6Mode=common`, no resampling, Darcy, open boundary, immersed solid,
or capacity/virial coupling.

## CUDA ordering

The fused resident Q6 call performs:

1. deposit cell mass and the tentative momentum
   `m * (v + a(x) dt)` without first updating particle velocity;
2. solve the existing Q6 pressure projection;
3. update each particle in one CUDA pass, preserving the 0493x4a arithmetic
   order:

   ```text
   v += a(x) dt
   v += delta_u_Q6
   ```

4. stream with body acceleration disabled, then collide and thermostat;
5. omit the post-collision Q6 exactly as in `prestream_single`.

The momentum-correction reduction continues to include only the Q6 correction.
The physical momentum supplied by the body force is not removed.

For common multi-species Q6, the species moment deposit also uses the tentative
velocity and the fused species particle-application kernel applies the same
force plus common Q6 correction.

## Non-regression matrix

```bash
LIVE_PROGRESS=1 PREFLIGHT_ONLY=1 \
bash scripts/run_0493x4b_q6_force_fusion_tg.sh

LIVE_PROGRESS=1 \
bash scripts/run_0493x4b_q6_force_fusion_tg.sh
```

The four cases share one initial state:

```text
null_single
null_fused
forced_single
forced_fused
```

The analyzer reports null-force particle neutrality, Taylor--Green modal and
particle differences, and the elapsed-time ratio of fused to separate-kick
one-solve paths.  Only null-force neutrality is a hard criterion in this first
fusion test.

## Closed-box liquid control

```bash
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=0 \
LIVE_VIS_HOLD_ON_EXIT=0 \
STEPS=1000 \
DUMP_STATE_EVERY=100 \
bash scripts/run_0493x4b_liquid_only_q6_force_fused.sh
```

The acceptance criteria remain those of 0493x4a: all 40,000 cells occupied,
centre of mass near `y=0.5`, no systematic top/bottom population transfer, and
Q6 convergence below the configured tolerance.

## Files

- `include/cuda_q6_resident_0400.h`
- `include/simulation_params.h`
- `src/cuda_q6_resident_0400.cu`
- `src/params_io_base.cpp`
- `src/src_mpcd_base.cpp`
- `scripts/run_0493x3_liquid_only_q6_force_prestream.sh`
- `scripts/run_0493x4b_q6_force_fusion_tg.sh`
- `scripts/analyze_0493x4b_q6_force_fusion_tg.py`
- `scripts/run_0493x4b_liquid_only_q6_force_fused.sh`

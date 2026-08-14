# 0493x7y — controlled x7q-off VK ablation

## Purpose

Isolate the **x7q exact particle-level periodic B1 momentum closure** while
retaining B1 RT0 reconstruction and the preceding `0493x7d-v2-fix2`
periodic projected-species k=0 correction.

New environment flag:

```text
MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y
```

Default: **ON**. Ordinary production runs therefore remain unchanged.

With the flag set to `0`, full-domain periodic B1 uses the retained historical
B1 kernel. That kernel still receives the `periodicMomentumAccum0493x7dv2fix2`
accumulator, so the pre-x7q x7d-v2-fix2 correction remains active. Only the
x7q exact particle-level residual reduction and second closure pass are
bypassed.

## Dedicated VK runner

```text
scripts/run_0493x7y_vk_x7qoff.sh
```

It is mechanically derived from the current `scripts/run_ok_vk.sh`, runs only
`src-q6-g-f`, keeps B1=1, and forces x7qExact=0.

For the causal comparison, use the same div0 settings as the existing
div0-B1on runs:

```text
RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME=0.0
RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=0
RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN=0.0
```

Comparison:

```text
div0 + B1 ON + x7q ON   existing reference
div0 + B1 ON + x7q OFF  0493x7y
```

This isolates the incremental x7q exact residual closure, not all periodic
k=0 handling.

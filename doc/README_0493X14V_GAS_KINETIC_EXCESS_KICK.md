# 0493x14v — aggregated gas kinetic excess kick

## Scope

Preimage inspected: `snap_020926.zip`.

Only `src/cuda_q6_resident_0400.cu` is modified by the tool.  The patch is
behind the default-OFF gate:

```text
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
```

The qualified liquid laws x10u/x10v/x12a and x6g itself are not changed.
There are no new diagnostics/counters, no new resident buffer, no host/device
transfer, and no new O(Nparticle) pass.

Preimage SHA256 (`src/cuda_q6_resident_0400.cu`):

```text
a79f615aeec83a0fe0087db1148a83a3e34deed9954175ea48bda0e88142b770
```

Reference patched-source SHA256 when applied to this preimage:

```text
ac2408ac1db3d4e51c1277bb887bfd482eef4e3b1345b58865f130fb822ebf40
```

## Physics

x14t qualified the thermodynamic normal pressure already represented by x6g.
x14u showed that the directed momentum removed from gas particles by x14l
specular reflection is not transferred instantaneously to phase A.

x14v transfers only the missing part:

```text
J_excess = J_reflection(actual) - J_thermodynamic(already represented by x6g)
```

For every x10n/Q2 owner branch, gas reflections are aggregated from the exact
already-computed specular impulse.  The x6g pressure represented at the nearby
Q6 gas-side trace is reconstructed using the current x6g mode, including the
x14s accessible-volume correction when active.  The corresponding pressure
traction is subtracted before any liquid kick is applied.

The oriented x10n segment has liquid->gas right normal.  With mid-step tangent
`(dxs,dys)`, the thermodynamic gas impulse on the liquid is

```text
J_eq = p_g dt (-dys, +dxs)
```

which integrates the normal-vector times segment length exactly for linearly
moving segment endpoints.

## Cost architecture

### Raw gas impulse

The x14l collision kernel already computes the reflection impulse.  x14v adds
only two FP64 atomics per gas hit and aggregates by existing x10n owner:

```text
kineticRefPx0493x9t -> raw owner Jx
kineticRefPy0493x9t -> raw owner Jy
```

These fields are already allocated and are dead on the x10o simple-wall path.

### Exact post-x10u liquid CIC mass without a second particle deposit

The raw kinetic CIC mass already exists before filtering.  The existing CIC
filter writes its dimensional raw mass into the otherwise-unused x10m `wallVn`
scratch:

```text
kineticMovingWallVn0493x10m -> M_liquid^CIC
```

If x10u moves a liquid particle, the continuous-interface kernel applies only
signed CIC deltas

```text
-M(old position) + M(new position)
```

for that relocated particle.  Since x10v changes velocity only, this yields the
exact post-x10u CIC mass without another O(Nparticle) mass-deposit pass.

### Equilibrium subtraction and scatter

When x14v is enabled, one cell kernel replaces the two x10v candidate-sentinel
memsets.  It simultaneously:

1. resets the two existing x10v candidate buffers;
2. reconstructs the x6g pressure already represented;
3. subtracts the associated segment traction;
4. scatters `J_excess` only to CIC nodes carrying positive liquid mass.

Existing dead x9t scratch is reused:

```text
kineticTxPx0493x9t -> liquid kick Jx grid
kineticTxPy0493x9t -> liquid kick Jy grid
```

No new O(Ncell) allocation is added.

### Liquid kick

The ordinary post-kinetic particle moment redeposit already traverses every
particle.  Under x14v it is replaced by a fused variant that first applies

```text
dv_i = sum_a w_ia J_excess,a / M_liquid,a^CIC
```

then performs the same cell-moment redeposit.  Hence x14v adds no new particle
traversal.

For supported CIC nodes the construction is exactly momentum conservative up
to floating-point atomic roundoff:

```text
sum_i m_i dv_i = sum_a J_excess,a
```

A radius <=2 cell-only fallback is provided if a thermally offset segment has
no positive liquid mass among its four immediate CIC nodes.  There is no
particle-neighbor search or relocalization.

## Runtime guards

The gate deliberately requires the current production architecture:

- x10o thermal interface;
- kinetic CIC;
- Q2;
- x10u;
- x10v;
- bilateral x14k geometry;
- x14l gas specular reflection;
- x6g gas pressure enabled;
- phase A is the unique projected liquid type.

This prevents accidental use on an unqualified architecture.

## Apply

From repository root:

```bash
python3 tools/apply_0493x14v_gas_kinetic_excess_kick.py
```

The tool is idempotent and performs static postcondition checks.

## Build

```bash
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

A successful x14v run must print once:

```text
[0493x14v-gas-kinetic-excess] enabled=1 raw=gas-specular-owner-aggregate subtract=x6g-thermodynamic-traction transfer=collective-liquid-CIC storage=reused-x9t/x10m newParticlePass=0 liquidLaws=UNCHANGED
```

## Validation sequence

### 1. Primary isolation: x14u constant pressure

Do this first.  x6g carries only the already-known thermodynamic reference
pressure; the directed kinetic excess must now be transmitted immediately.

```bash
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1 \
X6G_MODES="constant" \
CASES="static bottom_impact top_impact" \
STEPS=60 \
SUMMARY_EVERY=1 \
DUMP_STATE_EVERY=0 \
LIVE_VIS_ENABLE=0 \
bash scripts/run_ok_0493x14u_normal_kinetic_impact.sh
```

Primary targets:

```text
G_acc -> 1
G_mom -> 1 over the early window
static liquid Vy remains small
```

Return:

```text
runs/0493x14u_normal_kinetic_impact/0493x14u_normal_kinetic_impact_compact.tar.gz
```

### 2. Production x6g comparison

Only after the constant-mode isolation is satisfactory:

```bash
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1 \
X6G_MODES="eos_accessible_volume" \
CASES="static bottom_impact top_impact" \
STEPS=60 \
SUMMARY_EVERY=1 \
DUMP_STATE_EVERY=0 \
LIVE_VIS_ENABLE=0 \
bash scripts/run_ok_0493x14u_normal_kinetic_impact.sh
```

### 3. Static-drop non-regression

Then re-run x14s with the gate enabled.  Start with sigma=2560 because it gives
the cleanest shape baseline, then sigma=256 if needed.

```bash
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1 \
SURFACE_TENSION_SIGMA=2560 \
STEPS=1000 \
DUMP_STATE_EVERY=100 \
SUMMARY_EVERY=100 \
bash scripts/run_ok_0493x14s_x6g_accessible_volume_drop.sh
```

The decisive non-regression questions are shape stability, liquid bulk speed,
curvature/Laplace balance and absence of renewed gas/liquid interpenetration.

## Validation performed while packaging

- Python patch script: `py_compile` PASS.
- Apply against `snap_020926`: PASS.
- Idempotent re-apply/static validation: PASS.
- Review diff generated from the exact snapshot preimage.
- Algebraic CIC conservation identity checked independently with randomized
  particle positions; residual was at floating-point roundoff.
- Pre-CIC-mass + signed relocation delta was checked against a full post-move
  CIC redeposit; max discrepancy was at floating-point roundoff.

CUDA compilation was not executed in the packaging container because `nvcc`
is not installed there; compile with the repository build script above.

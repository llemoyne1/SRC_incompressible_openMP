# 0493x4a — Q6 force projection with one solve per forced step

## Purpose

0493x3 validated the experimental ordering

```
force kick -> Q6 -> streaming -> SRC collision -> Q6 -> thermostat
```

for a periodic solenoidal Taylor--Green force and for uniform gravity in a
closed liquid box.  The two Q6 solves made the hypothesis easy to isolate, but
added a large runtime cost.

0493x4a adds the opt-in mode:

```
q6ForceProjectionMode = prestream_single
```

Its forced-step ordering is:

```
force kick -> Q6 -> streaming -> SRC collision -> thermostat
```

The collision and relative thermostat do not move particles.  The velocity
produced after collision is therefore projected at the beginning of the next
step, before it can be used by streaming.  Only the transport velocity is
required to be projected at every step.

`legacy` remains the default.  The 0493x3 two-solve `prestream` mode is kept as
a reference.

## Deliberate restrictions

The one-solve test inherits the 0493x3 guardrails:

- CUDA Q6 projection;
- periodic box or static closed box;
- `speciesQ6Mode=common` when species Q6 is enabled;
- no resampling;
- no Darcy or immersed solid;
- no inlet/outlet;
- no closed-capacity or virial closure;
- static fluid domain.

The post-collision Q6 is skipped only when a non-zero force caused the
pre-stream Q6 to run.  With zero force, `prestream_single` follows the normal
single post-collision Q6 path and must be numerically neutral relative to
`legacy`.

## Taylor--Green non-regression matrix

```
LIVE_PROGRESS=1 PREFLIGHT_ONLY=1 \
  bash scripts/run_0493x4a_q6_force_single_tg.sh

LIVE_PROGRESS=1 \
  bash scripts/run_0493x4a_q6_force_single_tg.sh
```

The matrix runs:

- `null_legacy`;
- `null_prestream`;
- `null_prestream_single`;
- `forced_legacy`;
- `forced_prestream`;
- `forced_prestream_single`.

The analyzer checks null-force numerical neutrality at a configurable machine
precision tolerance and reports:

- modal Taylor--Green differences;
- particle position and velocity differences;
- elapsed-time ratios for legacy, two-solve and one-solve forced runs.

No physical acceptance threshold is imposed on the forced comparisons in this
first patch.

## Closed liquid control

```
LIVE_PROGRESS=1 PREFLIGHT_ONLY=1 \
  bash scripts/run_0493x4a_liquid_only_q6_force_single.sh

LIVE_PROGRESS=1 \
  bash scripts/run_0493x4a_liquid_only_q6_force_single.sh
```

This wrapper reuses the validated 0493x3 liquid-only runner and selects
`prestream_single`.  Visualization and dumps remain the qualification tools;
no new runtime diagnostic is introduced.

## Expected performance result

The forced one-solve path should approach the cost of `legacy`, because it
retains one Q6 solve per step.  The separate force-kick particle kernel remains
in 0493x4a; fusing the force into Q6 deposit/apply is deferred to a later patch
after physical equivalence is established.

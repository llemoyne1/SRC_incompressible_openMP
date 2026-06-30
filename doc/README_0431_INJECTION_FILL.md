# Injection/fill 0431 scripts

This bundle updates the uploaded `run_injection_fill_resampling_validation_0342a_livevis.sh`
and adds a dedicated type-injection demo.

## Files

```text
scripts/run_injection_fill_resampling_validation_0342a_livevis.sh
scripts/run_injection_type1_into_type2_segmented_0431_livevis.sh
doc/README_0431_INJECTION_FILL.md
```

## 1. Updated injection/fill validation

The filename is preserved for compatibility, but the internal logic is upgraded to
the same integration-path style as the current lr_segmented/Darcy scripts:

```bash
RUN_CASES="src src-resampling src-q6 src-q6-resampling"
```

Aliases are accepted:

```text
classic -> src
classic_resampling -> src-resampling
q6 -> src-q6
q6_resampling -> src-q6-resampling
```

The script is portable: if the previous MATLAB-generated initial pool state is
missing, it generates an inactive-pool `.smpcd` file inline.

Short smoke test:

```bash
FILL_STEPS=100 RUN_CASES=src LIVE_VIS_ENABLE=0 \
  bash scripts/run_injection_fill_resampling_validation_0342a_livevis.sh
```

Run all four current paths:

```bash
LIVE_VIS_HOLD_ON_EXIT=0 \
  bash scripts/run_injection_fill_resampling_validation_0342a_livevis.sh
```

Optional right full-height segmented outlet for the fill case:

```bash
FILL_OUTLET_ENABLE=1 \
  bash scripts/run_injection_fill_resampling_validation_0342a_livevis.sh
```

## 2. Type-1 injection into a type-2 homogeneous medium

The new script generates a homogeneous active medium:

```text
type = 2
mass = 1
role = fluid
```

and injects through the left segmented inlet:

```text
type = 1
mass = 1
```

Default right boundary is a full-height segmented outlet, which is the recommended
resident segmented IO path.

Short run:

```bash
STEPS=500 LIVE_VIS_ENABLE=0 \
  bash scripts/run_injection_type1_into_type2_segmented_0431_livevis.sh
```

Q6 run:

```bash
INTEG_PATH=src-q6 STEPS=500 LIVE_VIS_ENABLE=0 \
  bash scripts/run_injection_type1_into_type2_segmented_0431_livevis.sh
```

Q6 + resampling run:

```bash
INTEG_PATH=src-q6-resampling STEPS=500 LIVE_VIS_ENABLE=0 \
  bash scripts/run_injection_type1_into_type2_segmented_0431_livevis.sh
```

To test a mixed full-face right outlet instead of the default full-height segment:

```bash
RIGHT_OUTLET_STYLE=fullface \
  bash scripts/run_injection_type1_into_type2_segmented_0431_livevis.sh
```

The default `RIGHT_OUTLET_STYLE=segmented` is safer because it stays within the
validated resident segmented IO model.

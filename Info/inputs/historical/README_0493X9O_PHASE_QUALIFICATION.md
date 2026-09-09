# 0493x9o — tangential grid-phase qualification of x9m

Purpose: quantify the residual sub-cell phase sensitivity of the already-built
0493x9m off-support contact-curvature closure.  This patch changes **no C++ or
CUDA source** and requires **no rebuild**.

It reruns only the two x9n geometries that were near/over the 10% relative
threshold:

- circle `R/h=80`, `theta=120 deg`, exact `kappa=2.5`;
- tall ellipse `(a/h,b/h)=(40,56)`, `theta=90 deg`, exact local
  `kappa=2.551020408...`.

For each geometry the whole shape is translated tangentially by
`0, 0.25h, 0.50h, 0.75h`.  The physical wall remains exactly at `y=0`, so this
isolates the horizontal sub-cell phase of the contact geometry.

## Gates

Each individual phase must retain the qualified contact angle, `std(kappa)<=0.5`
and remain in the x9n absolute low-curvature envelope `|kappa-kappa_exact|<=0.5`.
For each four-phase family:

- phase-mean relative bias <= 10%;
- half-range across phase <= 0.5;
- maximum absolute error across phase <= 0.5.

This deliberately tests the decision criterion discussed after x9n: a phase-0
15% relative error at `kappa=2.5` is acceptable only if phase variation reveals
it as a grid-phase effect and the four-phase mean remains accurate.  If all
phases retain a systematic >10% mean bias, x9m should not yet be frozen.

## Install

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o 0493x9o_phase_qualification_bundle.zip
python3 x9o_bundle/tools/apply_0493x9o_phase_qualification.py
```

Expected installer tail:

```text
[0493x9o-install] ... sourceChanges=0 buildRequired=0
[0493x9o-install] status=PASS
```

## Static checks

```bash
bash -n scripts/run_0493x9o_phase_qualification.sh
python3 -m py_compile \
  scripts/check_0493x9o_phase_geometry.py \
  scripts/analyze_0493x9o_phase_qualification.py
python3 scripts/check_0493x9o_phase_geometry.py
```

No compilation is required.

## Run

```bash
LIVE_VIS_ENABLE=1 \
LIVE_VIS_HOLD_ON_EXIT=0 \
LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9o_phase_qualification.sh
```

Eight one-step runs are produced below
`runs/0493x9o_phase_qualification/`.

Relevant final lines are `[0493x9o-check]`, `[0493x9o-phase]`,
`[0493x9o-family]`, and the final status.  A CSV summary is written to
`runs/0493x9o_phase_qualification/x9o_phase_summary.csv`.

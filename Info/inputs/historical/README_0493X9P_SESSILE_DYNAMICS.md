# 0493x9p — dynamic sessile-drop qualification of x9m

This is a **qualification-only bundle**: no C++/CUDA or production physics is changed and no rebuild is required. It consumes the qualified x9m off-support contact-curvature closure and existing x9e/x9f diagnostics.

## Why the measured angle is not the x9m audit angle

The x9m contact-angle audit reports the Young normal imposed at the wall, so it is unsuitable as a dynamic convergence observable. x9p instead reconstructs the *physical global cap angle* in two independent ways from the evolving liquid distribution:

1. `thetaCOM`: for a 2-D circular cap of conserved liquid area `A`, invert the exact relation between `yCM/sqrt(A)` and contact angle;
2. `thetaMOM`: invert the exact covariance-ratio relation `Mxx/Myy(theta)` for a circular cap.

Agreement between the two is a circular-cap consistency test. The conserved mass-area comes from x9f liquid mass; x9e `alphaArea` is retained as an independent volume/geometry drift check.

For a cap of radius `R` and contact angle `theta` (radians):

`A = R^2 [theta - sin(theta) cos(theta)]`.

Hence an initial 90° cap can relax at constant area to a different equilibrium radius for a 60° or 120° Young angle.

## Default campaign

Grid 320x200, gamma=20, `R0/h=50`, `dt=0.002`, `kBT=0.125`, 2000 steps, summary/livevis cadence 20.

Active surface tension defaults to `sigma=5120`, chosen to give a clear capillary response on a practical run horizon while remaining in the regime already used successfully in the free-drop characterization.

Six cases:

- `hold60`: 60 -> 60, sigma active
- `hold90`: 90 -> 90, sigma active
- `hold120`: 120 -> 120, sigma active
- `wet90to60`: 90 -> 60, sigma active
- `dewet90to120`: 90 -> 120, sigma active
- `control90`: the exact same 90° initial state with sigma=0 and contact closure disabled

The three 90° cases point to the same deterministic input-state file.

## Main gates

- alpha-area drift <= 3%
- horizontal COM drift <= 0.01
- tail agreement `|thetaCOM-thetaMOM| <= 8 deg`
- active target error <= 10 deg
- transition moves by at least 5 deg in the correct direction
- tail angle std <= 5 deg and slope <= 5 deg / simulation-time unit
- x9m tail contact curvature within 20% of the target equilibrium circular-cap curvature
- active wetting/dewetting final angles each separate from the sigma=0 control by at least 10 deg

If integrity and direction pass but the run has not settled/closed the target yet, the analyzer reports `EXTEND_OR_REVIEW` rather than misclassifying it as a wrong-direction physics failure.

## Install

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o 0493x9p_sessile_dynamics_bundle.zip
python3 x9p_bundle/tools/apply_0493x9p_sessile_dynamics.py
bash -n scripts/run_0493x9p_sessile_dynamics.sh
python3 -m py_compile scripts/analyze_0493x9p_sessile_dynamics.py scripts/check_0493x9p_cap_geometry.py
python3 scripts/check_0493x9p_cap_geometry.py
```

No build is required.

## Full run

```bash
LIVE_VIS_ENABLE=1 \
LIVE_VIS_HOLD_ON_EXIT=0 \
LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
  bash scripts/run_0493x9p_sessile_dynamics.sh
```

Outputs are under `runs/0493x9p_sessile_dynamics/`; the final compact summary is `x9p_dynamic_summary.csv`.

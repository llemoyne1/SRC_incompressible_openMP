# 0493x9q — dripping-jet potential test

Purpose: push the existing x9/Q6-G-F capillary mechanism into a more realistic,
strongly time-dependent topology without trying to calibrate the result yet.

The box initially contains homogeneous gas.  A narrow **top segmented inlet**
injects liquid slowly downward.  Gravity pulls downward.  All four external
faces remain wall-like, except that the top segment is an inlet.  The intended
visual sequence is:

1. a pendant liquid tongue / jet grows below the inlet;
2. the neck either remains continuous or pinches;
3. a detached liquid body falls under gravity;
4. it impacts the bottom wall and spreads/rebounds/coalesces according to the
   present, still imperfect, wall-capillarity closure.

This is explicitly a **potentiality** test.  It has no hard physical PASS/FAIL
criteria for breakup time, drop size, contact angle or impact dynamics.

## Defaults

- `Lx=1`, `Ly=1.5`, `NX=200`, `NY=300` (square cells, h=0.005)
- `gamma=20`, `dt=0.002`, `steps=4000`, `kBT=0.125`
- liquid/gas particle mass ratio = 10 (moderate contrast only; not the future
  1e3 density-ratio qualification)
- top inlet width = 12 cells, `Uin=0.04` downward
- `gravityY=-0.25`
- capillary case: `surfaceTensionSigma=25600`, x9m contact closure at 90°
- control: identical run with `sigma=0`
- resampling and virial density kick remain off
- LiveVis defaults to liquid-filtered `density`
- filtered field recording stays off

The value sigma=25600 is intentionally exploratory.  With liquid particle mass
10, the `sigma/rho_l` response is weaker than the mass-1 x9p tests; the chosen
value restores a strong but not maximal capillary action while leaving room for
gravity/feed to produce necking.  Tune only after looking at the first run.

## Install

```bash
unzip -o 0493x9q_dripping_jet_potential_bundle.zip
python3 x9q_bundle/tools/apply_0493x9q_dripping_jet_potential.py
bash -n scripts/run_0493x9q_dripping_jet_potential.sh
python3 -m py_compile scripts/generate_0493x9q_gas_box_state.py scripts/analyze_0493x9q_dripping_jet.py
```

No source change and no rebuild are required.

## Run

Recommended paired run:

```bash
LIVE_VIS_ENABLE=1 \
LIVE_VIS_HOLD_ON_EXIT=0 \
LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9q_dripping_jet_potential.sh
```

For a first visual pass of the active case only:

```bash
CASES="capillary" STEPS=4000 \
LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=0 LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9q_dripping_jet_potential.sh
```

An optional `capillary_contactoff` case is available to isolate bulk capillarity
from x9m wall closure:

```bash
CASES="capillary capillary_contactoff sigma0" bash scripts/run_0493x9q_dripping_jet_potential.sh
```

## What to report

The primary evidence is visual.  Capture approximate steps/times for:

- first visible neck;
- first clean pinch-off, if any;
- first detached drop;
- first bottom impact;
- qualitative bottom response (spread, rebound, sticking, fragmentation);
- any obvious numerical pathology.

The final analyzer prints inventory/COM/moment/interface diagnostics but returns
`status=COMPLETE_VISUAL_REVIEW_REQUIRED` rather than pretending these data alone
prove breakup physics.

## Useful tuning if nothing happens

Change one control at a time.

- stronger gravity: `GRAVITY_Y=-0.4`
- larger feed: `UIN=0.06`
- weaker capillarity: `SIGMA_ACTIVE=12800`
- stronger capillarity/cohesion: `SIGMA_ACTIVE=51200`
- narrower/wider inlet: `INLET_WIDTH_CELLS=8` or `16`
- longer observation: `STEPS=6000`

Do not jump to the 1e3 mass ratio in this test: first establish whether the
current Q6-G-F capillary mechanism can sustain a jet, necking, topology change,
free fall and wall impact at all.

# 0347-topo: diagonal channel `chi_file` case

This patch adds a geometry inspired by the provided RANS/topology reference image:
a straight descending conduit from the left boundary (inlet side) to the bottom
boundary (outlet side) inside a square design box.

Scope in 0347:
- external `chi_file` generation only;
- CUDA-VIZ SRC classic + pure Brinkman path already validated in 0343–0346;
- visual validation and first observables through `darcy_cost_0343.csv`.

The generator mode is:
- `--mode diagonal_channel`

Main geometric parameters:
- `--inlet-y`: center of the inlet attachment on the left boundary;
- `--outlet-x`: center of the outlet attachment on the bottom boundary;
- `--pipe-width`: channel width;
- `--interface-width`: smoothing thickness.

Key scripts:
- `scripts/run_topo_darcy_diagonal_channel_0347.sh`
- `scripts/run_topo_darcy_diagonal_channel_sweep_0347.sh`

Example visualization workflow:
1. set `field = chi` in `livevis_control.kv`;
2. run `run_topo_darcy_diagonal_channel_0347.sh`;
3. switch to `alpha`, `ux`, and `darcy_power` during the run.

This 0347 case is geometry-oriented and keeps the current periodic runner.  A
later benchmark patch can reuse the same `chi_file` to define a true inlet/outlet
comparison against the RANS reference.

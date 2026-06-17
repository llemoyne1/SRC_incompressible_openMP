# 0346 — First bend-pipe case through external `chi_file`

## Scope

This patch adds a first bend-pipe validation case on top of the 0345 external
`chi` field path.  It does not change the CUDA Darcy/Brinkman kernel.

The goal is to validate that a non-analytic topology can be generated outside
the solver, read as `darcyChiMode=file`, transferred once to the GPU and used in
CUDA-VIZ without adding new per-step host/device transfers.

## Scripts

Single visual bend-pipe run:

```bash
bash scripts/run_topo_darcy_bend_pipe_0346.sh
```

Geometry sweep over pipe width:

```bash
WIDTHS="0.06 0.08 0.10 0.12 0.15" \
LIVE_VIS_ENABLE=0 \
bash scripts/run_topo_darcy_bend_pipe_sweep_0346.sh
```

## Default geometry

The generator uses the `bend_pipe` mode of
`scripts/generate_topo_chi_field_0345.py`:

```text
Lx = 1.5
Ly = 0.4
Nx = 360
Ny = 96
bend center = (0.45, 0.10)
bend radius = 0.18
pipe width = 0.10
interface width = 0.01
```

The result is a first L-bend/quarter-bend fluid channel:

```text
chi = 1 inside the bend-pipe channel
chi = 0 outside the channel
```

## Limitations

This is not yet a full pressure-drop benchmark:

- boundaries are still inherited from the current periodic SRC classic topo
  runner;
- Q6 and resampling remain disabled;
- pressure drop should not yet be interpreted as a calibrated inlet/outlet
  loss.

The intended 0346 validation quantities are therefore qualitative and energetic:

```text
meanChi
meanAlpha
darcyPower
solidLeakRms
meanSpeedRms
livevis chi / alpha / ux / darcy_power
```

The full bend-pipe benchmark with inlet/outlet sections and pressure/flux
observables should be the next step after this field-path validation.

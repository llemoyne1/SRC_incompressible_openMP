# 0350-topo: NACA polar-proxy postprocessing

This patch adds a specialized postprocessor for NACA incidence sweeps.  It does
not modify the CUDA solver.

## Inputs

The script reads the 0349 sweep summary:

```text
runs/topo_darcy_naca_sweep_0349/naca_sweep_0349_summary.csv
```

or any compatible summary with columns:

```text
naca,aoaDeg,chiFile,benchmarkCsv,windowStatsCsv
```

Each `windowStatsCsv` must be an output of the 0348b window-statistics
postprocessor.

## Output

The compact polar-proxy CSV contains one row per angle:

```text
naca_polar_proxy_0350.csv
```

Main columns:

```text
aoaDeg
dragProxy_mean
liftProxy_mean
liftOverDragProxy
absLiftOverAbsDrag
darcyPower_mean
solidLeakOverSpeed_mean
meanChi_mean
meanAlpha_mean
```

## Sign convention

The 0349 NACA runs showed that positive geometric incidence currently gives a
negative raw `liftProxy_mean`.  Therefore the wrapper defaults to:

```text
LIFT_SIGN=-1
```

so that positive AoA maps to positive lift in the compact polar-proxy file.  To
inspect raw signs, use:

```bash
LIFT_SIGN=1 RUN_FIRST=0 SUMMARY=... bash scripts/run_topo_darcy_naca_polar_proxy_0350.sh
```

## Usage

Run a new sweep and analyze it:

```bash
BIN=build/src_mpcd_base_cuda_topo_0348a \
AOAS="-8 -4 0 4 8" \
NACA_CODE=0012 \
STEPS=1800 \
LIVE_VIS_ENABLE=0 \
bash scripts/run_topo_darcy_naca_polar_proxy_0350.sh
```

Analyze an existing 0349 sweep:

```bash
RUN_FIRST=0 \
SUMMARY=runs/topo_darcy_naca_sweep_0349/naca_sweep_0349_summary.csv \
OUT=runs/topo_darcy_naca_sweep_0349/naca_polar_proxy_0350.csv \
bash scripts/run_topo_darcy_naca_polar_proxy_0350.sh
```

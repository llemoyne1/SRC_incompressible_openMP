# 0348b-topo: final-window statistics for benchmark observables

This patch is post-processing only.  It adds no CUDA kernels and does not modify
the solver.

## Motivation

The instantaneous force and drag/lift proxies introduced in 0348a contain a
strong transient at the beginning of a run.  This patch computes reproducible
window averages from `topo_benchmark_0348.csv`, typically over the final 50% of
saved benchmark rows.

## Scripts

```bash
scripts/analyze_topo_benchmark_window_0348b.py
scripts/run_topo_darcy_diagonal_benchmark_window_0348b.sh
```

The analyzer reads:

```text
output/topo_benchmark_0348.csv
```

and writes a one-line CSV:

```text
topo_benchmark_window_stats_0348b.csv
```

The wrapper runs the 0348a diagonal benchmark first unless `RUN_FIRST=0`.

## Default window

By default:

```text
TAIL_FRACTION=0.5
```

so the final half of saved benchmark rows is used.  Alternatively, set:

```text
STEP_MIN=...
TIME_MIN=...
```

to define the averaging window explicitly.

## Derived quantities

The analyzer reports mean/std/min/max/last for the main benchmark columns and
also derives:

```text
absLiftOverAbsDrag_mean
solidLeakOverSpeed_mean
powerOverDragAbs_mean
```

These values are intended for qualitative comparisons between topology fields
(coude, cylinder, ellipse, NACA) before a full inlet/outlet pressure benchmark is
introduced.

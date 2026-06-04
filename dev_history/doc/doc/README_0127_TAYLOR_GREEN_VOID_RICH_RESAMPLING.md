# 0127 — Taylor--Green void/rich resampling validation

This validation follows the project workflow used for the OpenMP SRC/MPCD code:

1. MATLAB prepares the input `.smpcd` state.
2. Bash writes `.kv` parameter files and runs the OpenMP executable.
3. MATLAB post-processes and visualizes output files.

The C++ executable does not generate the initial particle state.

## Directory convention

From the repository root:

```text
init/taylor_green_void_rich_resampling_0127/   # MATLAB-generated input states
runs/taylor_green_void_rich_resampling_0127/   # OpenMP run directories and output dumps
matlab/                                        # preparation and analysis scripts
scripts/                                       # bash launchers
```

When MATLAB is launched from the `matlab/` directory, use:

```matlab
../init/**   % generated input states
../runs/**   % post-processing input/output
```

When bash is launched from the repository root, it uses:

```bash
init/**
runs/**
```

## 1. Prepare the initial state with MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_taylor_green_void_rich_resampling_0127( ...
    'output', '../init/taylor_green_void_rich_resampling_0127/initial_state_tg_void_rich_0127.smpcd', ...
    'Nx', 32, ...
    'Ny', 32, ...
    'gamma', 20, ...
    'flowAmplitude', 0.08, ...
    'kBT', 0.001, ...
    'seed', 1270127);
```

The generator also writes:

```text
../init/taylor_green_void_rich_resampling_0127/initial_void_rich_layout_0127.csv
```

The state contains a periodic Taylor--Green velocity field, an empty fluid block, and an overloaded rich block.

## 2. Run OpenMP from bash

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

TG_STEPS=200 \
TG_DUMP_EVERY=50 \
TG_SUMMARY_EVERY=1 \
TG_THREADS=4 \
./scripts/run_taylor_green_void_rich_resampling_validation_0127.sh
```

The bash script looks for:

```text
init/taylor_green_void_rich_resampling_0127/initial_state_tg_void_rich_0127.smpcd
```

and writes:

```text
runs/taylor_green_void_rich_resampling_0127/classic/
runs/taylor_green_void_rich_resampling_0127/q6/
runs/taylor_green_void_rich_resampling_0127/q6_resampling/
```

## 3. Post-process with MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
analyze_taylor_green_void_rich_resampling_0127('../runs/taylor_green_void_rich_resampling_0127');
```

This writes the trigger summary to:

```text
../runs/taylor_green_void_rich_resampling_0127/analysis/tg_void_rich_trigger_summary_0127.csv
```

## Notes

The case is periodic in both directions, so it isolates the resampling behavior from wall, inlet/outlet, and immersed-solid boundary effects.

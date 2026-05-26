# MATLAB post-processing for SRC/MPCD base runs

The C++ executable intentionally writes primitive data only:

- `summary_runtime.csv` for light control diagnostics;
- `.smpcd` particle dumps for restart/inspection/post-processing;
- `params_used.kv` for reproducibility.

Physical diagnostics, plots and derived fields are handled in MATLAB.

## Main workflow

From MATLAB, add the repository `matlab/` directory to the path:

```matlab
addpath('matlab')
```

Then post-process a run directory:

```matlab
out = postprocess_smpcd_run('runs/periodic_base', ...
    'field', 'rho', ...
    'frameStride', 1, ...
    'particleDecimation', 20, ...
    'showParticles', false, ...
    'showVelocityVectors', false, ...
    'makeSummaryPlots', true, ...
    'playFrames', true);
```

The returned struct contains:

```text
out.params        parsed params_used.kv
out.grid          Lx, Ly, Nx, Ny
out.summaryTable  runtime diagnostics table
out.frameTable    list of available .smpcd dumps with step/time
out.fieldTables   optional binned field tables
out.lastFields    last binned field struct
```

## Available frame fields

The sequential viewer accepts:

```text
particles
N
rho
Ux
Uy
speed
omega
type
```

Examples:

```matlab
postprocess_smpcd_run('runs/channel_y_bounceback', 'field', 'omega');
postprocess_smpcd_run('runs/channel_y_bounceback', 'field', 'speed', 'showVelocityVectors', true);
postprocess_smpcd_run('runs/periodic_base', 'field', 'particles', 'particleDecimation', 10);
```

## Runtime diagnostics only

```matlab
summary = plot_smpcd_summary('runs/channel_y_bounceback');
```

This plots, when present:

- temperature proxy `kBT`;
- total momentum `Px`, `Py`;
- total mass;
- `stdN`;
- wall-hit counts by face;
- wall time.

## Sequential dump playback only

```matlab
out = play_smpcd_dumps('runs/periodic_base', ...
    'field', 'rho', ...
    'frameStride', 1, ...
    'pauseTime', 0.05);
```

## Binning one state manually

```matlab
state = read_smpcd_state('runs/periodic_base/state_step_00001000.smpcd');
fields = bin_smpcd_state(state, 'Lx', 1.0, 'Ly', 1.0, 'Nx', 32, 'Ny', 32);
T = smpcd_fields_to_table(fields, 'step', 1000, 'time', 1.0);
plot_smpcd_frame(state, fields, 'field', 'omega', 'showParticles', true);
```

The binned field matrices are stored as `Ny`-by-`Nx` arrays. Rows correspond
 to y-cells and columns to x-cells.

## Saving field tables

For compact runs, selected binned frames can be saved as one MATLAB table:

```matlab
out = postprocess_smpcd_run('runs/periodic_base', ...
    'playFrames', false, ...
    'frameStride', 1, ...
    'maxFramesToTable', 10, ...
    'saveFieldTables', true);
```

This writes `runs/periodic_base/binned_fields_table.mat` with:

```text
combinedFieldTable
frameTable
summaryTable
params
```

For large runs, keep `maxFramesToTable` small or increase `frameStride` to avoid
building very large MATLAB tables.

## Notes

- `.smpcd` files contain particle states only; domain/grid metadata are read
  from `params_used.kv` or passed explicitly.
- Vorticity is computed from binned cell velocities as `omega_z=dUy/dx-dUx/dy`.
- Particle `type` visualization uses the dominant type per cell.
- Diagnostics remain post-processing side by design: the C++ core stays small
  and case-independent.

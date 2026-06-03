# 0093 — Q9 limiter spatial diagnostics

## Purpose

This note documents the diagnostic extension added after the inlet/outlet 0092
Neumann-mode patch.  The objective is to make Q9 safeguard activity visible in
space for delicate open-boundary runs, especially segmented inlet/outlet or
slit/nozzle configurations where imposed density gradients can locally drive
large Q9 mass-flux corrections.

The patch is diagnostic-only.  It does not change the Q9 projection, the
velocity correction, the low-mass policy, the limiter formula, the virial kick,
the classic compressible mode, or the generic elliptic projection core.

## New parameters

```text
q9DiagnosticFieldDumpEnable = false
q9DiagnosticFieldDumpEvery = 0
```

`q9DiagnosticFieldDumpEnable=true` writes a cell-wise sidecar at diagnostic
dump steps.  In patch 0094 the default format became compact binary; the CSV
format remains available with `q9DiagnosticFieldDumpFormat=csv`.

`q9DiagnosticFieldDumpEvery=0` means that sidecars are written at the same cadence
as `.smpcd` state dumps, i.e. `dumpStateEvery`.  A positive value gives an
independent cadence.  For direct MATLAB visualization with the particle dumps,
keep the default value `0`.

## Output files

The solver writes files next to the state dumps:

```text
q9_diagnostics_step_XXXXXXXX.q9bin
q9_diagnostics_step_XXXXXXXX.csv   # optional legacy format
```

Each row is one grid cell.  The columns are:

```text
ix, iy, cellIndex, cellMass,
q9CorrectionRawDUx, q9CorrectionRawDUy,
q9CorrectionAppliedDUx, q9CorrectionAppliedDUy,
q9CorrectionRawMag, q9CorrectionAppliedMag,
q9CorrectionLimiterRatio, q9LimiterActive,
q9LowMassSuppressed, q9LowMassRamped, q9MassFloorApplied, q9SafetyActive
```

Definitions:

- `q9CorrectionRawMag` is the magnitude of the local Q9 velocity correction
  before the velocity limiter.
- `q9CorrectionAppliedMag` is the magnitude after low-mass treatment and velocity
  limiting.
- `q9CorrectionLimiterRatio = q9CorrectionRawMag / q9CorrectionVelocityLimiter`
  when the limiter threshold is positive; otherwise it is zero.
- `q9LimiterActive = 1` when the raw correction exceeds the nominal limiter
  threshold.  This matches the interpretation of the runtime counter
  `q9VelocityLimitedCells`.
- `q9LowMassSuppressed = 1` marks geometrically active cells where Q9 was skipped
  because cell mass was too low.
- `q9LowMassRamped = 1` marks cells inside the low-mass ramp interval.
- `q9MassFloorApplied = 1` marks cells where the mass floor was used in the
  flux-to-velocity conversion.
- `q9SafetyActive = 1` marks cells active in the Q9 safeguard pass after the
  projection mask.

In `thermal_soft` mode the tanh compression is mathematically smooth for any
non-zero correction.  The binary `q9LimiterActive` intentionally marks the
stronger condition `rawMag > limit`, so that it remains consistent with
`q9VelocityLimitedCells` and identifies cells exceeding the nominal thermal
velocity scale.

## MATLAB visualization

The MATLAB filtered animation helper can now read the sidecars and display:

```matlab
play_smpcd_filtered_animation('../runs/<run>/<case>', ...
    'field','q9LimiterRatio', ...
    'filterType','none', ...
    'clim',[0 2]);

play_smpcd_filtered_animation('../runs/<run>/<case>', ...
    'field','q9LimiterActive', ...
    'filterType','none', ...
    'clim',[0 1]);

play_smpcd_filtered_animation('../runs/<run>/<case>', ...
    'field','q9CorrectionRawMag', ...
    'filterType','none');

play_smpcd_filtered_animation('../runs/<run>/<case>', ...
    'field','q9CorrectionAppliedMag', ...
    'filterType','none');
```

Recommended first inspection for open-channel jet/slit cases:

1. `N` or `rho` to locate density pockets;
2. `q9LowMassSuppressed` to locate population-triggered Q9 neutralization;
3. `q9LimiterRatio` to identify zones close to or above the limiter threshold;
4. `q9LimiterActive` to see the binary activation mask;
5. `Ux`, `Uy`, `omega` to correlate limiter activation with flow structures.

## Updated segmented inlet/outlet runner

`scripts/run_open_channel_jet.sh` now enables the sidecar dump by default:

```bash
Q9_DIAGNOSTIC_FIELD_DUMP_ENABLE=true
Q9_DIAGNOSTIC_FIELD_DUMP_EVERY=0
```

Override from the shell if needed:

```bash
Q9_DIAGNOSTIC_FIELD_DUMP_ENABLE=false bash scripts/run_open_channel_jet.sh
```

or choose an independent cadence:

```bash
Q9_DIAGNOSTIC_FIELD_DUMP_EVERY=1000 bash scripts/run_open_channel_jet.sh
```

For visualization synchronized with `.smpcd` frames, prefer
`Q9_DIAGNOSTIC_FIELD_DUMP_EVERY=0` and set `DUMP_STATE_EVERY` to the desired
frame cadence.

## Validation expectation

The sidecar counters should be consistent with the runtime summary:

```text
sum(q9LimiterActive)       ~= q9VelocityLimitedCells
sum(q9LowMassSuppressed)   ~= q9LowMassSuppressedCells
sum(q9LowMassRamped)       ~= q9LowMassRampedCells
sum(q9MassFloorApplied)    ~= q9MassFloorAppliedCells
```

Minor differences should not occur for a given step; if they do, treat it as a
bug in the diagnostic dump rather than a physical result.

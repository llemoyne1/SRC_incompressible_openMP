# 0094 — Compact Q9 spatial diagnostic dump

## Why this change was needed

Patch 0093 introduced spatial Q9 limiter diagnostics as CSV sidecars.  This was
safe because it did not change the `.smpcd` particle-state format, but it made
long diagnostic runs unnecessarily bulky: every dump repeated one ASCII row per
cell and many decimal columns.

The 0094 update keeps the same diagnostic content and the same MATLAB field
names, but changes the default field-dump format to a compact binary sidecar.
This preserves the stable `.smpcd` particle dump while avoiding large CSV files.

## Parameters

```text
q9DiagnosticFieldDumpEnable = false
q9DiagnosticFieldDumpEvery = 0
q9DiagnosticFieldDumpFormat = binary
```

Allowed formats are:

```text
binary
csv
```

`q9DiagnosticFieldDumpEvery=0` keeps the diagnostic sidecar cadence synchronized
with `dumpStateEvery`, which is the recommended setting for
`play_smpcd_filtered_animation`.

## Output files

Default compact output:

```text
q9_diagnostics_step_XXXXXXXX.q9bin
```

Optional legacy CSV output:

```text
q9_diagnostics_step_XXXXXXXX.csv
```

The binary file contains the same grid fields as the 0093 CSV output, in fixed
row-major cell order:

```text
cellMass
q9CorrectionRawDUx
q9CorrectionRawDUy
q9CorrectionAppliedDUx
q9CorrectionAppliedDUy
q9CorrectionRawMag
q9CorrectionAppliedMag
q9CorrectionLimiterRatio
q9LimiterActive
q9LowMassSuppressed
q9LowMassRamped
q9MassFloorApplied
q9SafetyActive
```

The floating-point fields are stored as `float32`; the flag fields are stored as
`uint8`.  For a 96 x 24 grid this reduces a representative diagnostic sidecar
from about 414 kB as CSV to about 84 kB as binary.

## Why not put this in `.smpcd` or `summary_runtime.csv`?

`summary_runtime.csv` is intentionally scalar and time-series oriented.  It is
appropriate for global counters such as `q9VelocityLimitedCells`, but not for a
full spatial field.

The `.smpcd` file is the stable microscopic particle-state format.  Adding
cell-centered diagnostic arrays to it would change the format contract and would
require all readers, validators and old runs to handle optional non-particle
blocks.  Keeping Q9 diagnostics in a synchronized sidecar is therefore the least
intrusive option.  The binary sidecar is the compromise adopted here: compact,
optional, MATLAB-readable, and dynamically neutral.

## MATLAB usage

`play_smpcd_filtered_animation.m` now reads `.q9bin` first and falls back to the
legacy `.csv` sidecar if present.  Existing field names are unchanged:

```matlab
play_smpcd_filtered_animation('../runs/<run>/<case>', ...
    'field','q9LimiterRatio', ...
    'filterType','none', ...
    'clim',[0 2]);

play_smpcd_filtered_animation('../runs/<run>/<case>', ...
    'field','q9LimiterActive', ...
    'filterType','none', ...
    'clim',[0 1]);
```

Additional sidecar flags are also exposed:

```matlab
'field','q9LowMassRamped'
'field','q9MassFloorApplied'
'field','q9SafetyActive'
```

## Runner default

`scripts/run_open_channel_jet.sh` now sets:

```bash
Q9_DIAGNOSTIC_FIELD_DUMP_FORMAT=${Q9_DIAGNOSTIC_FIELD_DUMP_FORMAT:-binary}
```

To recover the old CSV format for manual inspection:

```bash
Q9_DIAGNOSTIC_FIELD_DUMP_FORMAT=csv bash scripts/run_open_channel_jet.sh
```

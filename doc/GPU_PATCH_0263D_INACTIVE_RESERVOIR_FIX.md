# GPU patch 0263d — resident full-face inlet/outlet inactive reservoir slack

## Context

Patch 0263 introduced the first full-face inlet/outlet resident CUDA path for the
classic SRC mode.  The hard-cell inlet reservoir is intentionally implemented
without GPU-side particle append in this milestone: deleted reservoir/outlet
particles are reused as inactive slots, and any true growth of the particle
array remains outside the 0263 scope.

The first 0263 runtime failure occurred before a validation summary row was
written.  The stderr aggregate only reported that `validation_summary_0162.csv`
was empty.  This is consistent with the binary stopping inside the case before
`run_validation_mono_config_0162.sh` could append its compact validation row.

## Fix

The validation state generator now supports:

```bash
--inactive-slots N
```

These additional particles are finite V2 payload entries with role `Inactive`.
They are ignored by the physics until a hard-cell inlet reservoir activates them.

The 0263 runner now passes a default inactive-slot budget to both the CPU
baseline and the CUDA resident run:

```bash
VALIDATION_INACTIVE_SLOTS=${VALIDATION_INACTIVE_SLOTS:-$((GAMMA * NY * 8))}
```

For the default `64x64, gamma=20` case this creates 10240 inactive slots, which
is deliberately larger than the three-cell inlet reservoir target population
(`3 * 64 * 20 = 3840`).  The baseline and resident runs therefore start from the
same state and can be compared deterministically while avoiding CPU append vs GPU
no-append asymmetry.

## Additional diagnostics

If the resident hard reservoir still exhausts inactive slots, the 0263 CUDA path
now reports the reservoir cell count, target particle count, reservoir deletion
count, outlet deletion count, and number of insertions completed before overflow.

The main host-side resident synchronization helper also recognizes:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263
```

so dumps and host summaries cannot accidentally read a stale host particle state
when the 0263 resident mode is active.

## Scope intentionally unchanged

- Q6 remains CPU and disabled in this classic SRC validation.
- Resampling and virial remain disabled.
- Thermostat remains disabled for 0263; the wall/solid/piston/inlet-outlet-aware
  CUDA thermostat remains a later dedicated chantier.
- GPU-side append/reallocation is still intentionally not implemented in 0263.

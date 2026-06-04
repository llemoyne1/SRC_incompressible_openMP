# Patch 0129 — resampling cadence and top-level switch

This patch fixes the operational vocabulary used by the OpenMP weighted-resampling branch.

## Definitions

The implementation now separates three mechanisms.

```text
Discrete resampling, every step when enabled:
  Fluid    -> Inactive    extraction from rich cells
  Inactive -> Fluid       insertion into poor cells
  Latent   -> Fluid       optional wet/dry activation

Mass renormalisation, every K steps:
  local mass remap M_c -> M_target
  bounded mass guard m_min <= m_p <= m_max

Thermal renormalisation, every step when enabled:
  local relative-velocity rescaling to preserve the thermal energy reference
```

## Parameters

```text
resamplingEnable = false
```

Top-level mutating-resampling switch.  If false, no role-changing operation and no mass/thermal renormalisation is applied, even when individual sub-switches are left true in a parameter file.  This gives a clean way to return to classic SRC/Q6 behaviour while keeping diagnostic columns active.

```text
resamplingMassRenormalizationPeriod = 1
```

Cadence for mass remap and mass guard:

```text
K = 1  : historical behaviour; mass renormalisation every step
K > 1  : mass renormalisation only on steps where step % K == 0
K = 0  : disable mass remap/mass guard stages
```

The existing sub-switches are kept:

```text
resamplingExtractionEnable = true/false
resamplingInsertionEnable = true/false
resamplingLatentActivationEnable = true/false
resamplingRemapEnable = true/false
resamplingMassGuardEnable = true/false
resamplingThermalRenormalizationEnable = true/false
```

The intended production-style configuration is now:

```text
resamplingEnable = true
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingLatentActivationEnable = false  # unless a wet/dry latent population is used
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = K
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
```

## Execution order

At each step the code still builds the real-fluid weighted deposit and diagnostics.  If `resamplingEnable=false`, execution stops there.

If `resamplingEnable=true`, the code performs, in order:

1. capture a pre-edit thermal-energy reference when thermal renormalisation is enabled;
2. optional latent activation;
3. optional donor extraction and receiver insertion;
4. redeposit real fluid if roles/positions changed;
5. if this is a mass-renormalisation step, apply mass remap and mass guard;
6. otherwise, still apply thermal renormalisation from the pre-edit reference;
7. redeposit and export diagnostics.

## Smoke test

```bash
./scripts/run_resampling_cadence_smoke_0129.sh
```

The smoke has two cases:

- `disabled`: all individual sub-switches are true, but `resamplingEnable=false`; no extraction, insertion, remap, thermal renormalisation or mass guard is attempted.
- `cadence`: `resamplingEnable=true`, `resamplingMassRenormalizationPeriod=2`; extraction/insertion can occur at step 1, thermal renormalisation is attempted every step, and mass remap/mass guard are attempted only at step 2.

Expected final message:

```text
[0129 resampling cadence smoke] OK
```

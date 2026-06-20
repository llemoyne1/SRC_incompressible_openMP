# Validation 0365 - resampling + empty refill on four physical cases

Date: 2026-06-20

Binary: `build/src_mpcd_base_cuda_topo_0343_fix0251`
SHA256: `86f388130dd071bf970b508ca0d1a9a12c2f9552d66d0cde4e0d1460f68ea7a7`

Summary files:

- `runs/validation_4cases_empty_refill_f0p1_summary.csv`
- `runs/validation_4cases_empty_refill_f0p1_summary.json`

## Script harmonization

The TG script already exposed `EMPTY_REFILL_ENABLE`. The Poiseuille, backward-step, and segmented-box scripts still wrote `cudaResamplingEmptyRefillEnable = false` literally. They were aligned to write:

```text
cudaResamplingEmptyRefillEnable = $(portable_bool_kv_0315 "${EMPTY_REFILL_ENABLE:-0}")
```

and now include the same small `portable_bool_kv_0315()` helper. Their environment snapshots also include `EMPTY_REFILL_*`.

## Rejected preliminary setting

A first full suite used:

```text
EMPTY_REFILL_ENABLE=1
EMPTY_REFILL_REFERENCE=nTarget
EMPTY_REFILL_TARGET_FRACTION=0.5
```

This did activate refill, but TG became too intrusive: 1800 refill particles, large transient per-cell mass/momentum residuals, and final `kBTEstimate` about 60 percent above the classic witness. This setting is not retained as validated.

## Retained validation setting

The retained suite used:

```text
EMPTY_REFILL_ENABLE=1
EMPTY_REFILL_REFERENCE=nTarget
EMPTY_REFILL_TARGET_FRACTION=0.1
EMPTY_REFILL_MEMORY_MAX_AGE=1000
STEPS=1000
RUN_MODES="classic resampling"
```

Run roots:

- TG: `runs/validation_4cases_18jun_tg_1000_empty_refill_f0p1`
- Poiseuille: `runs/validation_4cases_18jun_poiseuille_1000_empty_refill_f0p1`
- Step: `runs/validation_4cases_18jun_step_1000_empty_refill_f0p1`
- Box: `runs/validation_4cases_18jun_box_1000_empty_refill_f0p1`

## Result

All four cases have:

- `cudaResamplingEmptyRefillEnable = true` in params
- 0297 rows: 200
- 0297 handled: 200
- 0297 `skippedBecauseStateNotFresh`: 0
- 0296 handled: 200
- 0296 `skippedBecauseStateNotFresh`: 0

Refill activity:

| Case | split | merge | refill candidates | refill cells | refill particles | note |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| TG | 781 | 95 | 4135 | 36 | 72 | actual empty-refill exercise |
| Poiseuille | 198 | 9 | 0 | 0 | 0 | no empty-cell demand in this geometry |
| Step | 7 | 6 | 0 | 0 | 0 | no empty-cell demand in this geometry |
| Box | 515 | 719 | 0 | 0 | 0 | no empty-cell demand in this geometry |

Final global conservation/physical drift versus classic witness:

| Case | dNfluid | dMass rel. | dKBT rel. |
| --- | ---: | ---: | ---: |
| TG | +758 | 3.41e-15 | 2.13e-3 |
| Poiseuille | +189 | -5.05e-15 | -6.11e-4 |
| Step | +6 | 9.25e-5 | 1.47e-3 |
| Box | -365 | -1.52e-5 | 9.58e-4 |

The retained interpretation is therefore: resampling + empty-refill plumbing is validated on the four-case suite with the conservative `targetFraction=0.1`; the empty-refill branch is physically exercised by TG. The stronger `targetFraction=0.5` is rejected for TG because it is too invasive.

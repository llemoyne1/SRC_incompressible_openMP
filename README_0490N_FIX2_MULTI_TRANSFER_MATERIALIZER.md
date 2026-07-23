# 0490n-fix2 — discrete multi-transfer materializer coverage

## Failure found by the 10 000-step campaign

The first 10 000-step attempt stopped inside the 0490m non-regression run at
step 1595.  The resident 0490k planner produced six valid species-constrained
continuous transfer entries.  The direct 0490m materializer selected eight
whole particles, with selected mass larger than the total planned mass, but
marked one transfer entry invalid because that individual entry was underfilled.

This is not a malformed plan.  Transfer-plan masses are continuous, while
particle slots are indivisible.  An earlier entry for the same donor cell and
particle type can consume a whole particle and overshoot its own target.  A
later entry in that same donor/type group can consequently be underfilled even
though the group as a whole has selected enough mass.  The historical CPU
selection path already treats this as a valid discrete overshoot/coverage case.

## Correction

The direct CUDA materializer now distinguishes:

- `entryMassShortfalls`: individual continuous plan entries not reached by the
  selected whole-particle mass.  This is diagnostic and non-fatal;
- `donorTypeGroupUnderfills`: aggregate underfill for a unique
  `(donorCell, particleType)` group.  This remains fatal;
- structural errors such as plan overflow or operation-buffer overflow.  These
  remain fatal.

The kernel records the original donor cell for each selected particle, then
checks aggregate selected mass against aggregate planned mass for every
species-constrained donor group.  Overshoot by another species or another donor
cannot hide a real underfill.

Additional 0490m CSV columns report:

```text
entryMassShortfalls
 donorTypeGroupUnderfills
plannedMass
selectedMass
selectedMassCoverageFraction
```

No CPU fallback, plan-array round trip, operation-array round trip, or full-state
copy is reintroduced.

## Targeted validation

After rebuilding, run:

```bash
LIVE_PROGRESS=1 \
BIN=build/src_mpcd_base_cuda_q6_resident_0490n \
STEPS=1700 \
bash scripts/run_0490n_fix2_multi_transfer_materializer_validation.sh
```

The default seed reproduces the multi-entry event previously seen near step
1595.  The test requires at least one individual entry shortfall, zero
 donor/type group underfills, zero structural invalid operations, and a passing
fast path.

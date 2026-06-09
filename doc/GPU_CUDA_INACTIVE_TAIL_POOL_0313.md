# 0313 — bounded inactive-tail pool fast path

This patch targets the avoidable cost of very large inactive slot reservoirs.
It does not change the physical SRC step, Q6, thermostat, or resampling
conservation rules.

## Problem

Several validated CUDA paths need inactive particle slots:

- full-face hard inlet reservoir (`0268` pool path),
- segmented hard inlet reservoir (`0269` pool path),
- CUDA population guard split insertion (`0297`).

Before 0313, these paths rebuilt the inactive slot list by scanning the whole
particle capacity.  With large `INACTIVE_SLOTS`, this makes the step cost scale
with storage capacity even when most inactive slots are only reserve memory.

## Change

0313 adds a bounded inactive-tail collector.  It scans only a bounded window at
the end of the particle array, where appended reserve slots normally live, and
uses those indices as the inactive pool.  If that window does not contain enough
slots, the code falls back to the previous exact full scan unless fallback is
explicitly disabled.

This is a fast path, not a new physics mode.

## Environment controls

Enabled by default.  To disable:

```bash
MPCD_CUDA_INACTIVE_TAIL_POOL_0313=0
```

Tuning controls:

```bash
MPCD_CUDA_INACTIVE_TAIL_POOL_MIN_SCAN_0313=8192
MPCD_CUDA_INACTIVE_TAIL_POOL_MAX_SCAN_0313=262144
MPCD_CUDA_INACTIVE_TAIL_POOL_SCAN_MULT_0313=4
MPCD_CUDA_INACTIVE_TAIL_POOL_NO_FALLBACK_0313=0
```

The default scan window is:

```text
scan = clamp(max(minScan, need * scanMult + 1024), 0, maxScan)
```

where `need` is the estimated number of inactive slots required by the current
operation.

## Expected effect

The fast path removes large O(Np_total) inactive-pool scans from inlet refill
and population-guard split insertion when a large appended inactive reserve is
present.  It does not yet remove all O(Np_total) scans from streaming,
boundaries, collision, thermostat, or diagnostics.  A future active-index or
logical-active-span architecture would be needed for that deeper optimization.

## Validation recommendation

Compare with and without the fast path on the independent inactive-slot audit:

```bash
MPCD_CUDA_INACTIVE_TAIL_POOL_0313=0 bash scripts/run_cuda_inactive_slots_independent_audit_0312.sh
MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1 bash scripts/run_cuda_inactive_slots_independent_audit_0312.sh
```

For correctness fallback testing:

```bash
MPCD_CUDA_INACTIVE_TAIL_POOL_MAX_SCAN_0313=128 \
MPCD_CUDA_INACTIVE_TAIL_POOL_NO_FALLBACK_0313=0 \
  bash scripts/run_cuda_inactive_slots_independent_audit_0312.sh
```

The fallback should preserve successful execution even if the bounded tail
window is too small.

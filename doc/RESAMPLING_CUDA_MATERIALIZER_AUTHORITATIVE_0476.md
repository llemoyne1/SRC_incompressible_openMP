# 0476 - Materializer-authoritative scaling and phase attribution

## Purpose

0475b validated a shared-state cell-list materializer, but its output was only
copied into the host workspace. The downstream 0460 device carrier then built
the operation list again from the transfer plan. Therefore 0475b was applied,
but it was not the unique materializer used by the mutating carrier.

0476 removes this double materialization for the validation path:

1. 0475b builds and strictly validates the operation vector from the shared
   `CudaParticleState`;
2. the accepted vector replaces the host workspace operation vector;
3. the 0458 compact carrier uploads that accepted vector into the carrier
   buffers;
4. the carrier applies it without running the 0460 materializer again.

This makes 0475b authoritative in the functional sense. It is not yet a fully
resident implementation because the compact vector still crosses
device-to-host in 0475b and host-to-device in 0458.

## Validation

Command:

```bash
bash scripts/run_0476_materializer_authoritative_phase_attribution.sh
```

Configuration:

```text
grid = 128x128
gamma = 40
steps = 200
seed = 1628638
modes = src-resampling src-q6-resampling
summaryEvery = 50
deviceGateEvery = 50
upstreamGateEvery = 50
```

Result: `PASS-like rows: 2/2`.

| mode | CPU wall s | CUDA wall s | CPU/CUDA | max summary delta | materializer total s |
| --- | ---: | ---: | ---: | ---: | ---: |
| src-resampling | 19.495 | 22.570 | 0.864 | 1.164e-10 | 1.882e-2 |
| src-q6-resampling | 24.037 | 26.369 | 0.912 | 2.501e-12 | 1.900e-2 |

Authority evidence for each mode:

```text
materializer apply/shared/uploadSkipped/compactDownload = 1/1/1/1
carrier cpuOp/thrust/sharedUploadSkipped/hostPatchback = 1/0/1/1
upstream pass/shared/uploadSkipped = 8/4/4
```

The `carrier cpuOp/thrust = 1/0` pair is the discriminating observation: the
carrier consumed the accepted 0475b operation vector through the compact 0458
bridge and did not independently execute the 0460 materializer.

## Phase attribution

Dominant CUDA-run phases:

```text
src-resampling:
  resampling_remap          22.794 ms/step
  force_stream               9.453 ms/step
  resampling_deposit_initial 8.996 ms/step

src-q6-resampling:
  q6_projection             29.264 ms/step
  resampling_remap          17.103 ms/step
  thermostat                13.486 ms/step
```

The materializer is no longer the dominant measured phase. This experiment
does not demonstrate a CUDA speedup: both CUDA variants remain slower than the
CPU baseline on this case. The next performance patch should target
`resampling_remap` first and preserve the current strict equivalence checks.
For the Q6 combination, projection optimization remains a separate dominant
problem.

## Scope limits

This validation uses a periodic, wall-free, no-solid synthetic transfer case.
It does not establish correctness or performance for complex boundary
conditions. The eventual resident implementation must keep the transfer-plan
and operation-buffer interfaces compatible with non-periodic boundaries and
Darcy-Brinkman immersed solids; those extensions require dedicated physical
validation rather than extrapolation from this benchmark.

Outputs:

```text
runs/0476_materializer_authoritative_phase_attribution/materializer_authoritative_report_0476.md
runs/0476_materializer_authoritative_phase_attribution/materializer_authoritative_summary_0476.csv
```

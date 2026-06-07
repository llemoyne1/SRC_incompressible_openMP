# GPU patch 0283c — same-face closed-box demo inactive-pool fix

Patch 0283c fixes the `box_same_face_io` demonstration script introduced in the
SRC classic CUDA demo set.

## Symptom

The demo could stop during the initial transient with an error similar to:

```text
cuda_classic_src_io_resident_0263: segmented hard reservoir needs more inactive slots;
GPU append is intentionally disabled in 0264
```

This is not a CUDA collision/thermostat failure.  It is an inactive-pool sizing
issue in a closed-box recirculation demo where inlet and outlet segments are on
the same face.  Early in the run, the hard inlet reservoir can insert particles
before the upper outlet segment has established enough deletion flux.  Since the
segmented resident CUDA path intentionally forbids dynamic GPU append, insertion
must draw from preallocated `Inactive` slots.

## Change

The default inactive pool for
`scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh` is increased from

```bash
GAMMA * NY * 8
```

to

```bash
GAMMA * NX * NY
```

For the default `96 x 96`, `gamma=20` demo, this gives 184320 inactive slots,
which is appropriate for a long animation-oriented transient.  Users can still
override the value explicitly:

```bash
INACTIVE_SLOTS=250000 bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

## Scope

Only the demonstration runner is changed.  The numerical kernels, Q6/resampling
and virial architecture are untouched.  The demo remains SRC classic only:

```text
advection/streaming + random shift + SRC rotation/collision + thermostat
```

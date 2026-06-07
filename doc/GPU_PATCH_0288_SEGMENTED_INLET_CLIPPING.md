# GPU patch 0288 — segmented inlet reservoir clipping

## Motivation

The same-face box demo revealed a density spike at the upper end of the left
segmented inlet. The effect appears very early and is strongly localized at the
upper segment endpoint, which is not consistent with a purely macroscopic shear
interpretation.

The root cause is the geometric discretisation used by the hard segmented inlet
reservoir. Cells were selected by their centre coordinate, but particles were
then inserted over the full cell area. When a segment endpoint cuts through a
cell, the selected endpoint cell may inject particles outside the actual segment.
Those particles are not removed by the next reservoir deletion pass because the
deletion predicate uses the exact point-in-segment test. They therefore survive
in the nominally solid part of the boundary strip and create a persistent local
density excess.

For the default box demo, `openBoundarySegment0 = left inlet 0.10 0.35 ...` on a
96-cell vertical grid cuts through the top endpoint cell. The lower endpoint is
not affected in the same way because the centre-based selection skips the lower
partial cell. This explains the observed asymmetry.

## Change

Patch 0288 makes the CUDA hard segmented inlet reservoir segment-aware at the
cell-boundary level:

- reservoir cells are selected when their interval overlaps the segment, not
  only when their centre lies inside the segment;
- endpoint cells are clipped to the exact segment interval before particle
  positions are generated;
- the number of particles inserted in a clipped endpoint cell is scaled by the
  overlapped cell fraction;
- particle positions are sampled only inside the clipped sub-cell.

This keeps full cells unchanged while preventing injection outside the inlet
segment.

## Scope

The patch affects only the CUDA resident inlet/outlet hard reservoir path:

- full SRC classic CUDA remains the target;
- Q6, resampling and virial/capacity closure remain disabled in the demo and are
  not modified;
- the existing exact point-in-segment deletion predicate is preserved.

## Suggested test

Build:

```bash
bash scripts/build_src_mpcd_cuda_0288.sh
```

Short visual check of the problematic demo:

```bash
UIN=0.02 STEPS=300 DUMP_STATE_EVERY=100 SUMMARY_EVERY=100 \
BIN=build/src_mpcd_base_cuda_0288 \
bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

Then repeat the longer animation run:

```bash
UIN=0.02 STEPS=3000 DUMP_STATE_EVERY=100 SUMMARY_EVERY=100 \
BIN=build/src_mpcd_base_cuda_0288 \
bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

Expected qualitative effect: the artificial density spike at the upper inlet
endpoint should disappear or be strongly reduced. The demo can still show a
compressible jet/shear layer, because this is SRC classic without Q6/resampling
or virial closure, but the endpoint over-injection artefact should no longer be
present.

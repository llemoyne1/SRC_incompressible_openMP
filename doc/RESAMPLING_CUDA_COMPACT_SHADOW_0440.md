# 0440 — CUDA poor/rich cell compaction shadow validator

This step continues the resident CUDA resampling path after 0439.

0439 validated that CUDA deposit/classification reproduces the CPU weighted-resampling deposit on periodic wall-free synthetic cases. 0440 adds a standalone shadow validator for the next primitive: compacting poor and rich cells into device-side lists.

Scope:

- standalone validator only;
- no production solver mutation;
- no new public solver parameter;
- periodic wall-free/no-solid synthetic cases, using the same local periodic/no-solid hooks as 0439;
- CPU reference: `deposit_weighted_real_fluid()` receiver/donor lists;
- GPU candidate: CUDA compaction from deposited cell masses into poor/rich lists;
- lists are sorted before comparison because atomic insertion order is intentionally not specified.

Validated invariants:

- poor/rich counts match CPU;
- sorted poor/rich cell lists match CPU;
- deposit cell ids/counts/mass/momentum remain consistent with 0439 tolerances.

This is still a shadow primitive. It does not yet replace the CPU transfer planner in `src_mpcd_base.cpp`.

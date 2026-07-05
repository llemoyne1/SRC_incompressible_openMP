# 0475B — shared-state cell-list operation materializer

0475A proved that the 0453 materializer can be triggered on real transfer plans and can consume the shared CUDA particle state, but it exposed the old serial materializer kernel: the kernel scans all active particles for every transfer-plan entry and reached ~21 s at 128x128x40.

0475B keeps the 0475A on-plan trigger, but routes the shared-state materializer through a 0460-style stable cell-list path:

- build cell ids for the active prefix on device;
- stable-sort particle indices by cell id;
- compute donor-cell lower/upper bounds;
- materialize operations from donor-cell slices;
- download only the compact nOps payload.

Flags:

- `MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=1`
- `MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=1`
- `MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1`
- `MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460=1`

Expected effect: `mat_apply > 0`, `mat_shared > 0`, `mat_upload_skipped > 0`, `mat_compact_dl > 0`, and `mat_max_total_s`/`kernelSeconds` should drop from ~21 s to the millisecond or sub-second range.

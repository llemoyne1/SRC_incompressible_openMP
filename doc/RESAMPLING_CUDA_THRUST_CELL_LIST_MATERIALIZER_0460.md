# 0460B — Thrust stable GPU cell-list materializer

Adds `MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460=1`.

This probe is intended to apply directly on the committed 0459 donor-slice materializer state. It builds a GPU cell list using `(cellId, particleIndex)` pairs, `thrust::stable_sort_by_key`, and device lower/upper bounds for donor-cell slices. The existing 0459 donor-slice materialization kernel is reused, and the strict CPU operation gate remains active.

The purpose is to test whether a fully GPU-built donor cell list can replace the host-built donor slices of 0459B without losing bit-level operation equivalence.

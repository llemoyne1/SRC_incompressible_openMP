# 0459B CUDA donor-slice materializer

0459B is a transitional materializer probe for the periodic nonzero-plan resampling path.

It adds the environment flag:

```bash
MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459=1
```

The 0458 CPU-op carrier is disabled in the runner. The passive operation vector is no longer used as a carrier. Instead, the code builds compact candidate particle slices for donor cells and lets CUDA materialize the extraction/insertion operation buffers from those slices.

This is not yet the final host-free materializer: donor slices are currently built from host-side particle state. The purpose is to test the algorithmic step that replaces the full `planEntries × Nactive` scan by short donor-cell slice scans while preserving strict CPU/GPU operation equivalence.

Validation criteria:

- `donorSliceMaterializer0459 > 0` in `cuda_resampling_device_carrier_0455.csv`;
- CPU/GPU operation count equality;
- no invalid materialization or apply operations;
- no operation or duplicate-particle mismatch;
- final summary deltas within roundoff tolerance.

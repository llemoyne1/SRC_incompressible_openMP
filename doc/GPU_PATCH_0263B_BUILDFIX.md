# GPU patch 0263b — build fix for inlet/outlet full-face resident mode

This differential archive fixes the CUDA compilation error in patch 0263:

```text
calling a __host__ function("face_tag_0263") from a __device__ function("insert_reservoir_cell_device_0263") is not allowed
```

## Change

`face_tag_0263` is now declared as:

```cpp
__host__ __device__ inline std::uint64_t face_tag_0263(const int face)
```

The function is used while constructing the deterministic reservoir RNG seed inside the device-side hard-cell reservoir insertion path. The fix does not change the numerical or physical logic of patch 0263.

## Validation target

After applying this archive over patch 0263, rerun:

```bash
bash scripts/run_cuda_classic_src_io_fullface_resident_0263.sh
```

Expected target remains:

```text
verdict=PASS
failed_metrics=0
```

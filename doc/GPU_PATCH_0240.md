# Patch 0240 — CUDA resampling persistent active path

## Rationale

Patch 0239 validated the low-level extraction/insertion edit operations on a
persistent `CudaParticleState`: the next useful step is not another isolated
micro-kernel but the replacement of the host-wrapper edit stage inside the active
resampling loop.

Patch 0240 therefore installs a narrow hook around the existing CPU
`apply_resampling_extraction_operations(...)` / `apply_resampling_insertion_operations(...)`
block.  The hook is disabled unless explicitly requested with an environment
variable and it falls back to the historical CPU path unless the CUDA bridge
returns `handled=true`.

## Files installed/modified

Added:

- `include/cuda_resampling_persistent_active_path_0240.h`
- `src/cuda_resampling_persistent_active_path_0240.cpp`
- `scripts/run_cuda_resampling_persistent_active_path_0240.sh`
- `doc/GPU_PATCH_0240.md`

Modified:

- `src/src_mpcd_base.cpp`
- relevant `scripts/build*.sh` files, if a safe insertion point is found

## Activation

```bash
export MPCD_CUDA_RESAMPLING_PERSISTENT_0240=1
export MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES=0
```

Then run the existing CUDA resampling validation or:

```bash
bash scripts/run_cuda_resampling_persistent_active_path_0240.sh
```

## Important integration note

The installed `.cpp` bridge is intentionally CPU-safe and currently returns
`handled=false`.  This keeps the repository buildable and preserves the validated
CPU behavior.  To make 0240 fully GPU-active, connect the function
`try_apply_cuda_resampling_persistent_active_path_0240(...)` to the concrete 0239
backend that applies the already-built extraction/insertion operations on the
persistent `CudaParticleState`.

The desired final behavior is:

```text
host plan build -> persistent CudaParticleState edit -> one final host sync only when required
```

not:

```text
host plan build -> upload/download wrapper for every extraction/insertion phase
```

## Validation criteria

A successful fully connected 0240 run should preserve the 0239 invariants:

- extraction/insertion counts equal to the CPU reference,
- zero mismatch on x/y/vx/vy/mass/type/role after the edit phase,
- `allocationCalls=1` over the persistent-state run,
- no regression in the active resampling loop summaries.

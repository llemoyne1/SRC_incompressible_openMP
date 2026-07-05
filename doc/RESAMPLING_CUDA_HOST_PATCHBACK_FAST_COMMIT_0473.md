# 0473 — CUDA resampling host-patchback fast commit

This patch combines a performance optimization with a scaling validation probe.

## Motivation

0472 proved that the resampling carrier can use the process-local shared `CudaParticleState` and skip the expensive host-to-device refresh when the shared state is already fresh. It also reduced the final synchronization from `download_all` to `download_active_prefix`.

The remaining final synchronization is still larger than the actual set of changed particles. In the current passive resampling carrier, the final changed slots are exactly the compact operation particles materialized by the CUDA carrier. Therefore the host mirror can be updated by downloading the compact operation payload and patching only the affected `ParticleState` entries.

## New mode

Enable with:

```bash
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1
```

Recommended performance stack:

```bash
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1
MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472=0
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1
```

## Behavior

For each accepted CUDA resampling carrier call:

1. The caller uses the shared `CudaParticleState` when fresh, avoiding the upload.
2. The resident CUDA core materializes and applies the operation payload on device.
3. If the gate/apply status passes, the core downloads only the compact operation payload: particle indices, receiver cells, type, mass and momenta.
4. The caller patches the host `ParticleState` at the changed indices.
5. The shared CUDA state is marked fresh again.

This avoids both:

- the per-step host-to-device upload when the shared state is fresh;
- the active-prefix/full-state download after every accepted resampling apply.

## Validation

The runner `scripts/run_0473_host_patchback_fast_commit_probe.sh` performs a scaling comparison and reports:

- CPU wall time;
- CUDA wall time;
- CPU/CUDA speedup;
- final summary delta;
- shared-state rows;
- upload-skipped rows;
- active-prefix download rows;
- host-patchback rows;
- compact patch operation count;
- upload/state-download/patchback timings.

A successful run should show:

- PASS-like rows for all cases;
- `max upload s = 0` on the CUDA carrier rows;
- `max state dl s = 0` when host patchback is active;
- `host patchback rows = CSV rows`;
- final summary deltas below the usual tolerance.

## Limitations

The CPU upstream remains authoritative. This patch accelerates the commit synchronization of the CUDA resampling carrier, but it is not yet a fully GPU-owned multi-step resampling pipeline.

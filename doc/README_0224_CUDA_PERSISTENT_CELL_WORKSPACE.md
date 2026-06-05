# 0224 — Persistent CUDA cell workspace bridge

This patch introduces a shared CUDA cell workspace for the persistent SRC/MPCD GPU path.

## Goal

Previous persistent patches introduced `CudaParticleState`, then wired deposit → SRC collision → thermostat to use the shared particle buffers. However, the persistent substep still allocated transient cell arrays every call:

- `cellId`
- `cellCount`
- `cellMass`
- `cellPx`, `cellPy`
- `cellUx`, `cellUy`
- `cosA`, `sinA`
- `cellKinetic`, `cellScale`
- diagnostic counters

Patch 0224 adds `CudaCellWorkspace`, a reusable device owner for these buffers. The initial integration is a standalone bridge/validator, not yet a change to the default simulation path.

## New files

- `include/cuda_cell_workspace.h`
- `src/cuda_cell_workspace.cu`
- `src/main_validate_cuda_persistent_cell_workspace_bridge_0224.cpp`
- `scripts/build_cuda_persistent_cell_workspace_bridge_0224.sh`
- `scripts/run_cuda_persistent_cell_workspace_bridge_smoke_0224.sh`

## Modified files

- `include/cuda_persistent_mpcd_step.h`
- `src/cuda_persistent_mpcd_step.cu`

The new overload is:

```cpp
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut = nullptr);
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
CYCLES=5 \
bash scripts/run_cuda_persistent_cell_workspace_bridge_smoke_0224.sh
```

Expected output:

```text
CUDA_PERSISTENT_CELL_WORKSPACE_BRIDGE_0224 PASS
```

The validator compares three paths:

1. CPU reference.
2. Legacy CUDA persistent substep with internal transient cell allocations.
3. Shared `CudaParticleState` + shared `CudaCellWorkspace` substep.

Expected criteria:

- `cpuVelocityMismatches = 0`
- `legacyVelocityMismatches = 0`
- `cellWorkspaceVelocityMismatches = 0`
- `cellWorkspaceCellIdMismatches = 0`
- `cellWorkspaceCountMismatches = 0`
- `cellWorkspaceAllocationCalls = 1`
- `cellWorkspaceReusedAllocation = 1` after the second ensure call

## Scope

This patch is architectural and local. It prepares the real simulation path to reuse both particle and cell GPU buffers without repeatedly allocating transient cell storage. It does not yet make `CudaCellWorkspace` thread-local inside `src_collision_step`; that should be the next patch once this bridge is validated.

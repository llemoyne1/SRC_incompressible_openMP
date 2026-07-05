#!/usr/bin/env python3
from pathlib import Path

src = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
if not src.exists():
    raise SystemExit('missing src/cuda_resampling_pipeline_shadow_0445.cu')
text = src.read_text()

if 'cuda_resampling_materializer_cell_list_0475b_requested' not in text:
    anchor = '''bool cuda_resampling_materializer_shared_state_0475_requested() {\n    return env_truthy_0445("MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475");\n}\n'''
    repl = anchor + '''\nbool cuda_resampling_materializer_cell_list_0475b_requested() {\n    return env_truthy_0445("MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B");\n}\n'''
    if anchor not in text:
        raise SystemExit('anchor not found for 0475b env helper')
    text = text.replace(anchor, repl, 1)

helper = r'''

GpuMaterializedOps0453 materialize_ops_gpu_shared_state_cell_list_0475b(
    CudaParticleState& gpuState,
    const ParticleState& state,
    const CellGrid& grid,
    const SimulationParams& params,
    const WeightedRealFluidDepositWorkspace& ws) {
    GpuMaterializedOps0453 out{};
    out.sharedState0475 = 1u;
    out.compactDownload0475 = 1u;
    if (ws.transferPlan.empty()) return out;
    const std::size_t nActive = static_cast<std::size_t>(state.NactiveFluid);
    if (nActive == 0u) return out;

    const CudaParticleDeviceView view = gpuState.device_view();
    if (view.n < state.Np || view.nActiveFluid < state.NactiveFluid || view.x == nullptr || view.role == nullptr) {
        throw std::runtime_error("0475b materializer shared state is not allocated/fresh enough");
    }

    const auto t0 = std::chrono::steady_clock::now();
    const auto upload0 = std::chrono::steady_clock::now();

    std::vector<int> planDonor, planReceiver;
    std::vector<double> planMass;
    planDonor.reserve(ws.transferPlan.size());
    planReceiver.reserve(ws.transferPlan.size());
    planMass.reserve(ws.transferPlan.size());
    for (const auto& e : ws.transferPlan) {
        planDonor.push_back(e.donorCell);
        planReceiver.push_back(e.receiverCell);
        planMass.push_back(e.plannedMass);
    }

    std::vector<int> donorCells;
    donorCells.reserve(planDonor.size());
    constexpr double eps0475b = 1.0e-14;
    for (std::size_t e = 0; e < planDonor.size(); ++e) {
        if (planDonor[e] < 0 || planReceiver[e] < 0 || !(planMass[e] > eps0475b)) continue;
        bool seen = false;
        for (int c : donorCells) {
            if (c == planDonor[e]) { seen = true; break; }
        }
        if (!seen) donorCells.push_back(planDonor[e]);
    }
    if (donorCells.empty()) donorCells.push_back(-1);

    DeviceBuffer0445<int> dPlanDonor(planDonor.size()); dPlanDonor.copy_from_host(planDonor);
    DeviceBuffer0445<int> dPlanReceiver(planReceiver.size()); dPlanReceiver.copy_from_host(planReceiver);
    DeviceBuffer0445<double> dPlanMass(planMass.size()); dPlanMass.copy_from_host(planMass);
    DeviceBuffer0445<int> dDonorCells(donorCells.size()); dDonorCells.copy_from_host(donorCells);

    DeviceBuffer0445<int> dCellId(nActive);
    DeviceBuffer0445<unsigned int> dParticleSorted(nActive);
    DeviceBuffer0445<unsigned int> dDonorOffsets(donorCells.size()); dDonorOffsets.memset_zero();
    DeviceBuffer0445<unsigned int> dDonorUpper(donorCells.size()); dDonorUpper.memset_zero();
    DeviceBuffer0445<unsigned int> dDonorCounts(donorCells.size()); dDonorCounts.memset_zero();
    DeviceBuffer0445<std::uint8_t> dSelected(nActive); dSelected.memset_zero();

    const std::size_t maxOps = nActive;
    DeviceBuffer0445<unsigned int> dOutCount(1u); dOutCount.memset_zero();
    DeviceBuffer0445<unsigned int> dInvalid(1u); dInvalid.memset_zero();
    DeviceBuffer0445<unsigned int> dOutParticle(maxOps);
    DeviceBuffer0445<int> dOutDonor(maxOps);
    DeviceBuffer0445<int> dOutReceiver(maxOps);
    DeviceBuffer0445<std::uint32_t> dOutType(maxOps);
    DeviceBuffer0445<double> dOutMass(maxOps);
    DeviceBuffer0445<double> dOutPx(maxOps);
    DeviceBuffer0445<double> dOutPy(maxOps);
    DeviceBuffer0445<double> dOutKe(maxOps);
    DeviceBuffer0445<std::uint8_t> dOutRole(maxOps);

    out.planUploadSeconds0475 = std::chrono::duration<double>(std::chrono::steady_clock::now() - upload0).count();
    out.uploadSeconds = out.planUploadSeconds0475;

    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    CUDA_CHECK_0445(cudaEventRecord(start));

    const int threadsBuild = 256;
    const int blocksBuild = static_cast<int>((nActive + static_cast<std::size_t>(threadsBuild) - 1u) /
                                             static_cast<std::size_t>(threadsBuild));
    const std::uint8_t fluidRole = static_cast<std::uint8_t>(ParticleRole::Fluid);
    const int invalidCell = 2147483647;

    fill_cell_ids_and_particles_kernel_0460b<<<blocksBuild, threadsBuild>>>(
        nActive, view.x, view.y, view.role,
        grid.Nx, grid.Ny, grid.dx, grid.dy,
        is_x_periodic(params) ? 1 : 0, is_y_periodic(params) ? 1 : 0,
        fluidRole, invalidCell, dCellId.ptr, dParticleSorted.ptr);
    CUDA_CHECK_0445(cudaGetLastError());

    thrust::stable_sort_by_key(thrust::device,
        thrust::device_pointer_cast(dCellId.ptr),
        thrust::device_pointer_cast(dCellId.ptr + nActive),
        thrust::device_pointer_cast(dParticleSorted.ptr));
    CUDA_CHECK_0445(cudaGetLastError());

    thrust::lower_bound(thrust::device,
        thrust::device_pointer_cast(dCellId.ptr),
        thrust::device_pointer_cast(dCellId.ptr + nActive),
        thrust::device_pointer_cast(dDonorCells.ptr),
        thrust::device_pointer_cast(dDonorCells.ptr + donorCells.size()),
        thrust::device_pointer_cast(dDonorOffsets.ptr));
    thrust::upper_bound(thrust::device,
        thrust::device_pointer_cast(dCellId.ptr),
        thrust::device_pointer_cast(dCellId.ptr + nActive),
        thrust::device_pointer_cast(dDonorCells.ptr),
        thrust::device_pointer_cast(dDonorCells.ptr + donorCells.size()),
        thrust::device_pointer_cast(dDonorUpper.ptr));
    CUDA_CHECK_0445(cudaGetLastError());

    const int threadsCount = 128;
    const int blocksCount = static_cast<int>((donorCells.size() + static_cast<std::size_t>(threadsCount) - 1u) /
                                             static_cast<std::size_t>(threadsCount));
    compute_donor_counts_from_bounds_kernel_0460b<<<blocksCount, threadsCount>>>(
        static_cast<int>(donorCells.size()), dDonorOffsets.ptr, dDonorUpper.ptr, dDonorCounts.ptr);
    CUDA_CHECK_0445(cudaGetLastError());

    materialize_passive_ops_donor_slices_kernel_0459<<<1,1>>>(
        static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
        static_cast<int>(donorCells.size()), dDonorCells.ptr, dDonorOffsets.ptr, dDonorCounts.ptr,
        dParticleSorted.ptr, view.mass, view.vx, view.vy, view.type, view.role, fluidRole, view.n,
        dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,
        dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,
        dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    CUDA_CHECK_0445(cudaGetLastError());
    float ms = 0.0f;
    CUDA_CHECK_0445(cudaEventElapsedTime(&ms, start, stop));
    CUDA_CHECK_0445(cudaEventDestroy(start));
    CUDA_CHECK_0445(cudaEventDestroy(stop));
    out.kernelSeconds = static_cast<double>(ms) * 1.0e-3;

    const auto download0 = std::chrono::steady_clock::now();
    std::vector<unsigned int> hCount, hInvalid;
    copy_device_prefix_to_host_0473(dOutCount.ptr, 1u, hCount);
    copy_device_prefix_to_host_0473(dInvalid.ptr, 1u, hInvalid);
    const std::size_t nOps = hCount.empty() ? 0u : static_cast<std::size_t>(hCount[0]);
    out.invalidOps = hInvalid.empty() ? 0u : static_cast<std::uint64_t>(hInvalid[0]);
    if (nOps > maxOps) throw std::runtime_error("0475b materializer op count overflow");

    std::vector<unsigned int> hParticle;
    std::vector<int> hDonor, hReceiver;
    std::vector<std::uint32_t> hType;
    std::vector<double> hMass, hPx, hPy, hKe;
    std::vector<std::uint8_t> hRole;
    copy_device_prefix_to_host_0473(dOutParticle.ptr, nOps, hParticle);
    copy_device_prefix_to_host_0473(dOutDonor.ptr, nOps, hDonor);
    copy_device_prefix_to_host_0473(dOutReceiver.ptr, nOps, hReceiver);
    copy_device_prefix_to_host_0473(dOutType.ptr, nOps, hType);
    copy_device_prefix_to_host_0473(dOutMass.ptr, nOps, hMass);
    copy_device_prefix_to_host_0473(dOutPx.ptr, nOps, hPx);
    copy_device_prefix_to_host_0473(dOutPy.ptr, nOps, hPy);
    copy_device_prefix_to_host_0473(dOutKe.ptr, nOps, hKe);
    copy_device_prefix_to_host_0473(dOutRole.ptr, nOps, hRole);

    out.ops.reserve(nOps);
    for (std::size_t i = 0; i < nOps; ++i) {
        out.ops.push_back(ResamplingPassiveExtractionOperation{
            static_cast<std::uint64_t>(hParticle[i]),
            hDonor[i],
            hReceiver[i],
            hType[i],
            hMass[i],
            hPx[i],
            hPy[i],
            hKe[i],
            hRole[i],
            static_cast<std::uint8_t>(ParticleRole::Inactive)});
    }
    out.downloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - download0).count();
    out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return out;
}
'''

if 'materialize_ops_gpu_shared_state_cell_list_0475b' not in text:
    anchor = 'CudaResamplingOperationMaterialize0453Diagnostics try_apply_cuda_resampling_operation_materializer_0453('
    if anchor not in text:
        raise SystemExit('anchor not found for inserting 0475b helper')
    text = text.replace(anchor, helper + '\n\n' + anchor, 1)

old = '''            gpu = materialize_ops_gpu_shared_state_0475(sharedGpuState0475, state, grid, params, operationWorkspace);\n            gpu.uploadSkipped0475 = sharedFresh0475 ? 1u : 0u;\n'''
new = '''            if (cuda_resampling_materializer_cell_list_0475b_requested()) {\n                gpu = materialize_ops_gpu_shared_state_cell_list_0475b(sharedGpuState0475, state, grid, params, operationWorkspace);\n            } else {\n                gpu = materialize_ops_gpu_shared_state_0475(sharedGpuState0475, state, grid, params, operationWorkspace);\n            }\n            gpu.uploadSkipped0475 = sharedFresh0475 ? 1u : 0u;\n'''
if old not in text:
    if new not in text:
        raise SystemExit('anchor not found for replacing 0475 materializer call')
else:
    text = text.replace(old, new, 1)

src.write_text(text)
print('[0475b] patched materializer shared-state cell-list path')

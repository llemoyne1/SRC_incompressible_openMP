#!/usr/bin/env python3
from pathlib import Path

ROOT = Path.cwd()

def read(p: Path) -> str:
    return p.read_text()

def write(p: Path, s: str) -> None:
    p.write_text(s)

def replace_once(s: str, old: str, new: str, label: str) -> str:
    if old not in s:
        raise SystemExit(f"[0475] missing anchor: {label}")
    return s.replace(old, new, 1)

hdr = ROOT / "include" / "cuda_resampling_pipeline_shadow_0445.h"
cu = ROOT / "src" / "cuda_resampling_pipeline_shadow_0445.cu"
if not hdr.exists() or not cu.exists():
    raise SystemExit("[0475] run from repository root: missing include/src files")

h = read(hdr)
if "materializerSharedState0475" not in h:
    h = replace_once(
        h,
        "    double uploadSeconds = 0.0;\n    double kernelSeconds = 0.0;\n    double downloadSeconds = 0.0;\n    double totalSeconds = 0.0;\n};",
        "    // 0475: materializer can consume the process-local shared CudaParticleState.\n"
        "    // This removes the materializer-specific full particle H2D refresh when\n"
        "    // the shared resident state is already fresh, and uses compact nOps D2H.\n"
        "    std::uint64_t materializerSharedState0475 = 0u;\n"
        "    std::uint64_t materializerUploadSkipped0475 = 0u;\n"
        "    std::uint64_t materializerCompactDownload0475 = 0u;\n"
        "    double stateUploadSeconds0475 = 0.0;\n"
        "    double planUploadSeconds0475 = 0.0;\n\n"
        "    double uploadSeconds = 0.0;\n    double kernelSeconds = 0.0;\n    double downloadSeconds = 0.0;\n    double totalSeconds = 0.0;\n};",
        "0475 materializer diagnostics fields",
    )
    write(hdr, h)

s = read(cu)

if "sharedState0475" not in s.split("struct GpuMaterializedOps0453", 1)[1].split("};", 1)[0]:
    s = replace_once(
        s,
        "struct GpuMaterializedOps0453 {\n    std::vector<ResamplingPassiveExtractionOperation> ops;\n    std::uint64_t invalidOps = 0u;\n    double uploadSeconds = 0.0;\n    double kernelSeconds = 0.0;\n    double downloadSeconds = 0.0;\n    double totalSeconds = 0.0;\n};",
        "struct GpuMaterializedOps0453 {\n    std::vector<ResamplingPassiveExtractionOperation> ops;\n    std::uint64_t invalidOps = 0u;\n    std::uint64_t sharedState0475 = 0u;\n    std::uint64_t uploadSkipped0475 = 0u;\n    std::uint64_t compactDownload0475 = 0u;\n    double stateUploadSeconds0475 = 0.0;\n    double planUploadSeconds0475 = 0.0;\n    double uploadSeconds = 0.0;\n    double kernelSeconds = 0.0;\n    double downloadSeconds = 0.0;\n    double totalSeconds = 0.0;\n};",
        "GpuMaterializedOps0453 fields",
    )

if "materialize_ops_gpu_shared_state_0475" not in s:
    marker = "\nbool cuda_resampling_cpu_op_carrier_0458_requested()"
    if marker not in s:
        raise SystemExit("[0475] missing anchor: insert shared-state materializer 0475")
    shared_fn = r'''
GpuMaterializedOps0453 materialize_ops_gpu_shared_state_0475(CudaParticleState& gpuState,
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

    DeviceBuffer0445<int> dPlanDonor(planDonor.size()); dPlanDonor.copy_from_host(planDonor);
    DeviceBuffer0445<int> dPlanReceiver(planReceiver.size()); dPlanReceiver.copy_from_host(planReceiver);
    DeviceBuffer0445<double> dPlanMass(planMass.size()); dPlanMass.copy_from_host(planMass);
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

    const CudaParticleDeviceView pv = gpuState.device_view();
    if (pv.n < state.Np || pv.nActiveFluid < state.NactiveFluid || pv.x == nullptr || pv.role == nullptr) {
        throw std::runtime_error("0475 materializer shared state is not allocated/fresh enough");
    }

    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    CUDA_CHECK_0445(cudaEventRecord(start));
    materialize_passive_ops_serial_kernel_0453<<<1,1>>>(
        nActive, pv.x, pv.y, pv.mass, pv.vx, pv.vy, pv.type, reinterpret_cast<const std::uint8_t*>(pv.role),
        grid.Nx, grid.Ny, grid.dx, grid.dy,
        is_x_periodic(params) ? 1 : 0, is_y_periodic(params) ? 1 : 0,
        static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
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
    if (nOps > maxOps) throw std::runtime_error("0475 materializer op count overflow");
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
    s = s.replace(marker, "\n" + shared_fn + marker, 1)

if "cuda_resampling_materializer_shared_state_0475_requested" not in s:
    s = replace_once(
        s,
        "bool cuda_resampling_upstream_shared_state_0474_requested() {\n    return env_truthy_0445(\"MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474\");\n}\n",
        "bool cuda_resampling_upstream_shared_state_0474_requested() {\n"
        "    return env_truthy_0445(\"MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474\");\n"
        "}\n\n"
        "bool cuda_resampling_materializer_shared_state_0475_requested() {\n"
        "    return env_truthy_0445(\"MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475\");\n"
        "}\n",
        "0475 env function",
    )

if "materializerSharedState0475" not in s.split("append_operation_materialize_csv_0453", 1)[1].split("}\n\nstruct Totals", 1)[0]:
    s = replace_once(
        s,
        "            << \"uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds\\n\";",
        "            << \"materializerSharedState0475,materializerUploadSkipped0475,materializerCompactDownload0475,\"\n"
        "            << \"stateUploadSeconds0475,planUploadSeconds0475,\"\n"
        "            << \"uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds\\n\";",
        "0453 csv header 0475",
    )
    s = replace_once(
        s,
        "        << d.cpuPy << ',' << d.gpuPy << ',' << d.cpuKe << ',' << d.gpuKe << ','\n        << d.uploadSeconds << ',' << d.kernelSeconds << ',' << d.downloadSeconds << ',' << d.totalSeconds << '\\n';",
        "        << d.cpuPy << ',' << d.gpuPy << ',' << d.cpuKe << ',' << d.gpuKe << ','\n"
        "        << d.materializerSharedState0475 << ',' << d.materializerUploadSkipped0475 << ','\n"
        "        << d.materializerCompactDownload0475 << ',' << d.stateUploadSeconds0475 << ','\n"
        "        << d.planUploadSeconds0475 << ','\n"
        "        << d.uploadSeconds << ',' << d.kernelSeconds << ',' << d.downloadSeconds << ',' << d.totalSeconds << '\\n';",
        "0453 csv row 0475",
    )

old = "        const GpuMaterializedOps0453 gpu = materialize_ops_gpu_0453(state, grid, params, operationWorkspace);\n        d.gpuOps = static_cast<std::uint64_t>(gpu.ops.size());\n        d.invalidOps = gpu.invalidOps;\n        d.uploadSeconds = gpu.uploadSeconds;\n        d.kernelSeconds = gpu.kernelSeconds;\n        d.downloadSeconds = gpu.downloadSeconds;\n"
new = "        GpuMaterializedOps0453 gpu{};\n"
new += "        if (cuda_resampling_materializer_shared_state_0475_requested()) {\n"
new += "            CudaParticleStateDiagnostics stateUploadDiag{};\n"
new += "            CudaParticleState& sharedGpuState0475 = cuda_shared_particle_state_0251();\n"
new += "            const bool sharedFresh0475 = cuda_shared_particle_state_0251_is_fresh() &&\n"
new += "                                         sharedGpuState0475.size() == state.Np &&\n"
new += "                                         sharedGpuState0475.active_fluid_size() >= state.NactiveFluid;\n"
new += "            if (sharedFresh0475) {\n"
new += "                gpu.uploadSkipped0475 = 1u;\n"
new += "            } else {\n"
new += "                sharedGpuState0475.upload_all(state, &stateUploadDiag);\n"
new += "                cuda_shared_particle_state_0251_mark_fresh(\"operation_materializer_0475\");\n"
new += "            }\n"
new += "            gpu = materialize_ops_gpu_shared_state_0475(sharedGpuState0475, state, grid, params, operationWorkspace);\n"
new += "            gpu.uploadSkipped0475 = sharedFresh0475 ? 1u : 0u;\n"
new += "            gpu.stateUploadSeconds0475 = stateUploadDiag.uploadSeconds;\n"
new += "            gpu.uploadSeconds += stateUploadDiag.uploadSeconds;\n"
new += "            gpu.totalSeconds += stateUploadDiag.uploadSeconds;\n"
new += "        } else {\n"
new += "            gpu = materialize_ops_gpu_0453(state, grid, params, operationWorkspace);\n"
new += "        }\n"
new += "        d.gpuOps = static_cast<std::uint64_t>(gpu.ops.size());\n"
new += "        d.invalidOps = gpu.invalidOps;\n"
new += "        d.materializerSharedState0475 = gpu.sharedState0475;\n"
new += "        d.materializerUploadSkipped0475 = gpu.uploadSkipped0475;\n"
new += "        d.materializerCompactDownload0475 = gpu.compactDownload0475;\n"
new += "        d.stateUploadSeconds0475 = gpu.stateUploadSeconds0475;\n"
new += "        d.planUploadSeconds0475 = gpu.planUploadSeconds0475;\n"
new += "        d.uploadSeconds = gpu.uploadSeconds;\n"
new += "        d.kernelSeconds = gpu.kernelSeconds;\n"
new += "        d.downloadSeconds = gpu.downloadSeconds;\n"
if old in s:
    s = s.replace(old, new, 1)
elif "materialize_ops_gpu_shared_state_0475" not in s or "MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475" not in s:
    raise SystemExit("[0475] missing anchor: materializer call replacement")

write(cu, s)
print("[0475] patched shared-state materializer and profiler fields")

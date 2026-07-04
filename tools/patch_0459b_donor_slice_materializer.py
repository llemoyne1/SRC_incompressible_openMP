from pathlib import Path

p = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
s = p.read_text()

if 'MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459' in s:
    print('[0459B] donor-slice materializer markers already present; no patch applied')
    raise SystemExit(0)

# 1) env helper after 0458 helper
old = '''bool cuda_resampling_cpu_op_carrier_0458_requested()\n{\n    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458");\n    if (!env) return false;\n    const std::string v(env);\n    return !v.empty() && v != "0" && v != "false" && v != "FALSE" && v != "off" && v != "OFF";\n}\n'''
new = old + '''\nbool cuda_resampling_donor_slice_materializer_0459_requested()\n{\n    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459");\n    if (!env) return false;\n    const std::string v(env);\n    return !v.empty() && v != "0" && v != "false" && v != "FALSE" && v != "off" && v != "OFF";\n}\n'''
if old not in s:
    raise SystemExit('[0459B] missing 0458 env helper insertion point')
s = s.replace(old, new, 1)

# 2) diagnostics field
old = '    std::uint64_t cpuOpCarrier0458 = 0u;\n'
new = old + '    std::uint64_t donorSliceMaterializer0459 = 0u;\n'
if old not in s:
    raise SystemExit('[0459B] missing cpuOpCarrier0458 field')
s = s.replace(old, new, 1)

# 3) add host helper + donor-slice kernel after insertion kernel
anchor = '''__global__ void apply_device_carrier_insertion_kernel_0455(\n'''
idx = s.find(anchor)
if idx < 0:
    raise SystemExit('[0459B] missing insertion kernel anchor')
# find end of insertion kernel by unique tail
end_marker = '''    applied[op] = ok;\n}\n\n  GpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455'''
if end_marker not in s:
    # tolerate two spaces / no double-space variations
    end_marker = '''    applied[op] = ok;\n}\n\nGpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455'''
if end_marker not in s:
    raise SystemExit('[0459B] missing insertion-kernel end marker')
insert = '''    applied[op] = ok;\n}\n\nint cell_id_from_position_host_0459(double x, double y,\n                                    int nx, int ny,\n                                    double dx, double dy,\n                                    bool xPeriodic, bool yPeriodic) {\n    if (nx <= 0 || ny <= 0 || !(dx > 0.0) || !(dy > 0.0)) return -1;\n    int ix = static_cast<int>(floor(x / dx));\n    int iy = static_cast<int>(floor(y / dy));\n    if (xPeriodic) {\n        while (ix < 0) ix += nx;\n        while (ix >= nx) ix -= nx;\n    }\n    if (yPeriodic) {\n        while (iy < 0) iy += ny;\n        while (iy >= ny) iy -= ny;\n    }\n    if (ix < 0 || ix >= nx || iy < 0 || iy >= ny) return -1;\n    return iy * nx + ix;\n}\n\n__global__ void materialize_passive_ops_donor_slices_kernel_0459(\n    int planCount,\n    const int* planDonor,\n    const int* planReceiver,\n    const double* planMass,\n    int donorSliceCount,\n    const int* donorCells,\n    const unsigned int* donorOffsets,\n    const unsigned int* donorCounts,\n    const unsigned int* compactParticles,\n    const double* mass,\n    const double* vx,\n    const double* vy,\n    const std::uint32_t* type,\n    const std::uint8_t* role,\n    std::uint8_t fluidRole,\n    std::uint64_t nParticles,\n    std::uint8_t* selected,\n    int maxOps,\n    unsigned int* outCount,\n    unsigned int* invalidOps,\n    unsigned int* outParticle,\n    int* outDonor,\n    int* outReceiver,\n    std::uint32_t* outType,\n    double* outMass,\n    double* outPx,\n    double* outPy,\n    double* outKe,\n    std::uint8_t* outCurrentRole) {\n    if (blockIdx.x != 0 || threadIdx.x != 0) return;\n    constexpr double eps = 1.0e-14;\n    unsigned int count = 0u;\n    unsigned int invalid = 0u;\n    for (int e = 0; e < planCount; ++e) {\n        const int donorCell = planDonor[e];\n        const int receiverCell = planReceiver[e];\n        const double wanted = planMass[e];\n        if (donorCell < 0 || receiverCell < 0 || !(wanted > eps)) continue;\n\n        int slice = -1;\n        for (int d = 0; d < donorSliceCount; ++d) {\n            if (donorCells[d] == donorCell) { slice = d; break; }\n        }\n        if (slice < 0) { ++invalid; continue; }\n\n        const unsigned int begin = donorOffsets[slice];\n        const unsigned int n = donorCounts[slice];\n        double selectedForEntry = 0.0;\n        for (unsigned int k = 0u; k < n; ++k) {\n            const unsigned int p = compactParticles[begin + k];\n            if (static_cast<std::uint64_t>(p) >= nParticles) continue;\n            if (selected[p]) continue;\n            if (role[p] != fluidRole) continue;\n            const double mp = mass[p];\n            if (!(mp > 0.0) || !isfinite(mp)) continue;\n            if (count >= static_cast<unsigned int>(maxOps)) {\n                ++invalid;\n                break;\n            }\n            selected[p] = 1u;\n            outParticle[count] = p;\n            outDonor[count] = donorCell;\n            outReceiver[count] = receiverCell;\n            outType[count] = type[p];\n            outMass[count] = mp;\n            outPx[count] = mp * vx[p];\n            outPy[count] = mp * vy[p];\n            outKe[count] = 0.5 * mp * (vx[p] * vx[p] + vy[p] * vy[p]);\n            outCurrentRole[count] = role[p];\n            ++count;\n            selectedForEntry += mp;\n            if (selectedForEntry + eps >= wanted) break;\n        }\n        if (selectedForEntry + eps < wanted) {\n            ++invalid;\n        }\n    }\n    *outCount = count;\n    *invalidOps = invalid;\n}\n\nGpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455'''
s = s.replace(end_marker, insert, 1)

# 4) add flag in apply function
old = '''    cudaEvent_t start{}, stop{};\n    const bool cpuOpCarrier0458 = cuda_resampling_cpu_op_carrier_0458_requested();\n    out.cpuOpCarrier0458 = cpuOpCarrier0458 ? 1u : 0u;\n    if (cpuOpCarrier0458) {\n'''
new = '''    cudaEvent_t start{}, stop{};\n    const bool cpuOpCarrier0458 = cuda_resampling_cpu_op_carrier_0458_requested();\n    const bool donorSliceMaterializer0459 = (!cpuOpCarrier0458 && cuda_resampling_donor_slice_materializer_0459_requested());\n    out.cpuOpCarrier0458 = cpuOpCarrier0458 ? 1u : 0u;\n    out.donorSliceMaterializer0459 = donorSliceMaterializer0459 ? 1u : 0u;\n    if (cpuOpCarrier0458) {\n'''
if old not in s:
    raise SystemExit('[0459B] missing materializer flag block')
s = s.replace(old, new, 1)

# 5) insert donor-slice branch before serial fallback
old = '''        out.materializeKernelSeconds = 0.0;\n    } else {\n        CUDA_CHECK_0445(cudaEventCreate(&start));\n'''
branch = '''        out.materializeKernelSeconds = 0.0;\n    } else if (donorSliceMaterializer0459) {\n        // 0459B donor-slice materializer: build a compact, deterministic host-side\n        // list of candidate particles for the donor cells only, then let CUDA\n        // materialize the operation vector by scanning those short donor slices.\n        // This deliberately does not use the CPU passive operation vector as a\n        // carrier; it is a transitional step toward a fully GPU-built cell list.\n        std::vector<int> donorCells0459;\n        donorCells0459.reserve(planDonor.size());\n        constexpr double eps0459 = 1.0e-14;\n        for (std::size_t e = 0; e < planDonor.size(); ++e) {\n            if (planDonor[e] < 0 || planReceiver[e] < 0 || !(planMass[e] > eps0459)) continue;\n            bool seenDonor = false;\n            for (int c : donorCells0459) {\n                if (c == planDonor[e]) { seenDonor = true; break; }\n            }\n            if (!seenDonor) donorCells0459.push_back(planDonor[e]);\n        }\n        std::vector<std::vector<unsigned int>> perDonor0459(donorCells0459.size());\n        const bool xp0459 = is_x_periodic(params);\n        const bool yp0459 = is_y_periodic(params);\n        const std::uint8_t fluidRole0459 = static_cast<std::uint8_t>(ParticleRole::Fluid);\n        for (std::size_t i = 0; i < static_cast<std::size_t>(state.NactiveFluid); ++i) {\n            if (i >= state.role.size() || state.role[i] != fluidRole0459) continue;\n            if (i >= state.x.size() || i >= state.y.size()) continue;\n            const int cid = cell_id_from_position_host_0459(state.x[i], state.y[i],\n                                                            grid.Nx, grid.Ny, grid.dx, grid.dy,\n                                                            xp0459, yp0459);\n            if (cid < 0) continue;\n            for (std::size_t d = 0; d < donorCells0459.size(); ++d) {\n                if (donorCells0459[d] == cid) {\n                    perDonor0459[d].push_back(static_cast<unsigned int>(i));\n                    break;\n                }\n            }\n        }\n        std::vector<unsigned int> donorOffsets0459(donorCells0459.size(), 0u);\n        std::vector<unsigned int> donorCounts0459(donorCells0459.size(), 0u);\n        std::vector<unsigned int> compactParticles0459;\n        for (std::size_t d = 0; d < donorCells0459.size(); ++d) {\n            donorOffsets0459[d] = static_cast<unsigned int>(compactParticles0459.size());\n            donorCounts0459[d] = static_cast<unsigned int>(perDonor0459[d].size());\n            compactParticles0459.insert(compactParticles0459.end(), perDonor0459[d].begin(), perDonor0459[d].end());\n        }\n        if (compactParticles0459.empty()) compactParticles0459.push_back(0u);\n\n        DeviceBuffer0445<int> dDonorCells0459(donorCells0459.size()); dDonorCells0459.copy_from_host(donorCells0459);\n        DeviceBuffer0445<unsigned int> dDonorOffsets0459(donorOffsets0459.size()); dDonorOffsets0459.copy_from_host(donorOffsets0459);\n        DeviceBuffer0445<unsigned int> dDonorCounts0459(donorCounts0459.size()); dDonorCounts0459.copy_from_host(donorCounts0459);\n        DeviceBuffer0445<unsigned int> dCompactParticles0459(compactParticles0459.size()); dCompactParticles0459.copy_from_host(compactParticles0459);\n\n        CUDA_CHECK_0445(cudaEventCreate(&start));\n        CUDA_CHECK_0445(cudaEventCreate(&stop));\n        CUDA_CHECK_0445(cudaEventRecord(start));\n        materialize_passive_ops_donor_slices_kernel_0459<<<1,1>>>(\n            static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,\n            static_cast<int>(donorCells0459.size()), dDonorCells0459.ptr, dDonorOffsets0459.ptr, dDonorCounts0459.ptr,\n            dCompactParticles0459.ptr, view.mass, view.vx, view.vy, view.type, view.role, fluidRole0459, view.n,\n            dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,\n            dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,\n            dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);\n        CUDA_CHECK_0445(cudaEventRecord(stop));\n        CUDA_CHECK_0445(cudaEventSynchronize(stop));\n        CUDA_CHECK_0445(cudaGetLastError());\n        float materializeMs = 0.0f;\n        CUDA_CHECK_0445(cudaEventElapsedTime(&materializeMs, start, stop));\n        CUDA_CHECK_0445(cudaEventDestroy(start));\n        CUDA_CHECK_0445(cudaEventDestroy(stop));\n        out.materializeKernelSeconds = static_cast<double>(materializeMs) * 1.0e-3;\n    } else {\n        CUDA_CHECK_0445(cudaEventCreate(&start));\n'''
if old not in s:
    raise SystemExit('[0459B] missing branch insertion point')
s = s.replace(old, branch, 1)

# 6) CSV header + line
old = '''               "uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";\n'''
new = '''               "uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";\n'''
if old not in s:
    raise SystemExit('[0459B] missing CSV header pattern')
s = s.replace(old, new, 1)
old = '''        << d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.gateDownloadSeconds << ','\n'''
new = '''        << d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.gateDownloadSeconds << ','\n'''
if old not in s:
    raise SystemExit('[0459B] missing CSV output row pattern')
s = s.replace(old, new, 1)

p.write_text(s)
print('[0459B] patched donor-slice materializer into src/cuda_resampling_pipeline_shadow_0445.cu')

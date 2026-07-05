#!/usr/bin/env python3
from pathlib import Path

ROOT = Path.cwd()


def read(path):
    return path.read_text()


def write(path, text):
    path.write_text(text)


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f"[0474] missing anchor: {label}")
    return text.replace(old, new, 1)


hdr = ROOT / "include" / "cuda_resampling_pipeline_shadow_0445.h"
cu = ROOT / "src" / "cuda_resampling_pipeline_shadow_0445.cu"

if not hdr.exists() or not cu.exists():
    raise SystemExit("[0474] run from repository root: missing include/src files")

h = read(hdr)
if "upstreamSharedState0474" not in h:
    h = replace_once(
        h,
        "    std::uint64_t cpuPassiveOps = 0u;\n\n    double depositKernelSeconds = 0.0;",
        "    std::uint64_t cpuPassiveOps = 0u;\n\n"
        "    // 0474: upstream CUDA gate may reuse the process-local shared CudaParticleState.\n"
        "    // This keeps 0450/0451 validation from reintroducing a full H2D upload\n"
        "    // when the resident/shared state is already authoritative.\n"
        "    std::uint64_t upstreamSharedState0474 = 0u;\n"
        "    std::uint64_t upstreamUploadSkipped0474 = 0u;\n"
        "    double uploadSeconds = 0.0;\n\n"
        "    double depositKernelSeconds = 0.0;",
        "diagnostic fields",
    )
    write(hdr, h)

s = read(cu)
if "cuda_resampling_upstream_shared_state_0474_requested" not in s:
    s = replace_once(
        s,
        "bool cuda_resampling_host_patchback_0473_requested() {\n    return env_truthy_0445(\"MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473\");\n}\n",
        "bool cuda_resampling_host_patchback_0473_requested() {\n"
        "    return env_truthy_0445(\"MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473\");\n"
        "}\n\n"
        "bool cuda_resampling_upstream_shared_state_0474_requested() {\n"
        "    return env_truthy_0445(\"MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474\");\n"
        "}\n",
        "0474 env function",
    )

if "upstreamSharedState0474" not in s:
    s = replace_once(
        s,
        "            << \"cpuTransferPairs,gpuTransferPairs,planMismatch,maxPlanMassAbs,maxPlanDistanceAbs,cpuPlannedMass,gpuPlannedMass,cpuPassiveOps,\"\n"
        "            << \"depositKernelSeconds,depositDownloadSeconds,compactKernelSeconds,plannerKernelSeconds,totalSeconds\\n\";",
        "            << \"cpuTransferPairs,gpuTransferPairs,planMismatch,maxPlanMassAbs,maxPlanDistanceAbs,cpuPlannedMass,gpuPlannedMass,cpuPassiveOps,\"\n"
        "            << \"upstreamSharedState0474,upstreamUploadSkipped0474,uploadSeconds,\"\n"
        "            << \"depositKernelSeconds,depositDownloadSeconds,compactKernelSeconds,plannerKernelSeconds,totalSeconds\\n\";",
        "upstream csv header",
    )
    s = replace_once(
        s,
        "        << d.cpuPassiveOps << ',' << d.depositKernelSeconds << ',' << d.depositDownloadSeconds << ','\n"
        "        << d.compactKernelSeconds << ',' << d.plannerKernelSeconds << ',' << d.totalSeconds << '\\n';",
        "        << d.cpuPassiveOps << ','\n"
        "        << d.upstreamSharedState0474 << ',' << d.upstreamUploadSkipped0474 << ',' << d.uploadSeconds << ','\n"
        "        << d.depositKernelSeconds << ',' << d.depositDownloadSeconds << ','\n"
        "        << d.compactKernelSeconds << ',' << d.plannerKernelSeconds << ',' << d.totalSeconds << '\\n';",
        "upstream csv row",
    )

old = """        CudaParticleState gpuState{};
        CudaParticleStateDiagnostics uploadDiag{};
        gpuState.upload_all(state, &uploadDiag);
        CudaCellWorkspace cellWorkspace{};
        CudaCellMoments gpuDeposit{};
        CudaCellMomentsDiagnostics depositDiag{};
        CudaCellMomentsOptions options{};
        options.computeCellVelocities = true;
        options.downloadCellVelocities = true;
        options.enableAllFluidFastPath = true;
        options.enableUniformMassFastPath = true;
        cuda_deposit_cell_moments_atomic_from_persistent_state(
            state, gpuState, cellWorkspace, grid, GridShift{}, params, gpuDeposit, &depositDiag, options);
"""
new = """        CudaParticleState localGpuState{};
        CudaParticleState* gpuStatePtr = &localGpuState;
        CudaParticleStateDiagnostics uploadDiag{};
        if (cuda_resampling_upstream_shared_state_0474_requested()) {
            d.upstreamSharedState0474 = 1u;
            gpuStatePtr = &cuda_shared_particle_state_0251();
            if (cuda_shared_particle_state_0251_is_fresh()) {
                d.upstreamUploadSkipped0474 = 1u;
            } else {
                gpuStatePtr->upload_all(state, &uploadDiag);
                cuda_shared_particle_state_0251_mark_fresh("resampling_upstream_shadow_0474");
            }
        } else {
            gpuStatePtr->upload_all(state, &uploadDiag);
        }
        d.uploadSeconds = uploadDiag.uploadSeconds;
        CudaCellWorkspace cellWorkspace{};
        CudaCellMoments gpuDeposit{};
        CudaCellMomentsDiagnostics depositDiag{};
        CudaCellMomentsOptions options{};
        options.computeCellVelocities = true;
        options.downloadCellVelocities = true;
        options.enableAllFluidFastPath = true;
        options.enableUniformMassFastPath = true;
        cuda_deposit_cell_moments_atomic_from_persistent_state(
            state, *gpuStatePtr, cellWorkspace, grid, GridShift{}, params, gpuDeposit, &depositDiag, options);
"""
if old in s:
    s = s.replace(old, new, 1)
elif "CudaParticleState* gpuStatePtr" not in s:
    raise SystemExit("[0474] missing upstream upload block")

write(cu, s)
print("[0474] patched shared-state upstream gate and timing fields")

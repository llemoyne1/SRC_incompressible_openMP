#!/usr/bin/env python3
from pathlib import Path

root = Path('.')
src = root / 'src' / 'cuda_resampling_pipeline_shadow_0445.cu'
base = root / 'src' / 'src_mpcd_base.cpp'

text = src.read_text()

def rep(old, new, label):
    global text
    if old not in text:
        raise SystemExit(f'[0472] failed to locate {label}')
    text = text.replace(old, new, 1)

# Include shared state bridge.
rep('#include "cuda_resampling_particle_ops.h"\n', '#include "cuda_resampling_particle_ops.h"\n#include "cuda_shared_particle_state_0251.h"\n', 'shared particle state include')

# Extend diagnostics.
rep('''    std::uint64_t residentDeferredDownload0468 = 0u;
    std::uint64_t residentDirectCommit0471 = 0u;
    std::uint64_t sparseGate0461 = 0u;
''', '''    std::uint64_t residentDeferredDownload0468 = 0u;
    std::uint64_t residentDirectCommit0471 = 0u;
    std::uint64_t residentSharedState0472 = 0u;
    std::uint64_t residentSharedUploadSkipped0472 = 0u;
    std::uint64_t residentActivePrefixDownload0472 = 0u;
    std::uint64_t sparseGate0461 = 0u;
''', 'GpuDeviceCarrier0455 0472 fields')

# Add flag helpers after 0471 helper.
rep('''bool cuda_resampling_direct_state_commit_0471_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471");
}

CudaResamplingUpstreamShadow0450Diagnostics try_run_cuda_resampling_upstream_shadow_0450(
''', '''bool cuda_resampling_direct_state_commit_0471_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471");
}

bool cuda_resampling_shared_state_direct_commit_0472_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472");
}

bool cuda_resampling_active_prefix_download_0472_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472");
}

CudaResamplingUpstreamShadow0450Diagnostics try_run_cuda_resampling_upstream_shadow_0450(
''', '0472 env helpers')

# Replace 0471 direct commit block internals.
old = '''                const auto txWrapper0 = std::chrono::steady_clock::now();
                const auto txCarrier0 = std::chrono::steady_clock::now();
                const auto txUpload0 = std::chrono::steady_clock::now();
                CudaParticleState gpuState{};
                CudaParticleStateDiagnostics uploadDiag{};
                gpuState.upload_all(state, &uploadDiag);
                const double externalUploadSeconds =
                    std::chrono::duration<double>(std::chrono::steady_clock::now() - txUpload0).count() + uploadDiag.uploadSeconds;

                GpuDeviceCarrier0455 dc = apply_gpu_particle_edits_device_carrier_resident_0467(
                    gpuState, state, editWorkspace, grid, params, false);
                dc.uploadSeconds += externalUploadSeconds;
                dc.totalSeconds += externalUploadSeconds;
                dc.residentExternal0467B = 1u;
                dc.residentDeferredDownload0468 = 1u;
                dc.residentDirectCommit0471 = 1u;

                const bool ok = (dc.pass && dc.invalidMaterializeOps == 0u && dc.invalidApplyOps == 0u &&
                                 dc.extractionApplied == d.passiveOps && dc.insertionApplied == d.passiveOps);
                if (ok) {
                    const auto txDownload0 = std::chrono::steady_clock::now();
                    CudaParticleStateDiagnostics downloadDiag{};
                    gpuState.download_all(state, &downloadDiag);
                    const double externalStateDownloadSeconds =
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - txDownload0).count() + downloadDiag.downloadSeconds;
                    dc.stateDownloadSeconds += externalStateDownloadSeconds;
                    dc.totalSeconds += externalStateDownloadSeconds;
                }
'''
new = '''                const auto txWrapper0 = std::chrono::steady_clock::now();
                const auto txCarrier0 = std::chrono::steady_clock::now();
                const bool useSharedState0472 = cuda_resampling_shared_state_direct_commit_0472_requested();
                const bool activePrefixDownload0472 = cuda_resampling_active_prefix_download_0472_requested();

                CudaParticleState localGpuState{};
                CudaParticleState* gpuStatePtr = nullptr;
                bool sharedWasFresh0472 = false;
                double externalUploadSeconds = 0.0;
                if (useSharedState0472) {
                    gpuStatePtr = &cuda_shared_particle_state_0251();
                    sharedWasFresh0472 = cuda_shared_particle_state_0251_is_fresh();
                    if (!sharedWasFresh0472) {
                        const auto txUpload0 = std::chrono::steady_clock::now();
                        CudaParticleStateDiagnostics uploadDiag{};
                        gpuStatePtr->upload_all(state, &uploadDiag);
                        externalUploadSeconds =
                            std::chrono::duration<double>(std::chrono::steady_clock::now() - txUpload0).count() + uploadDiag.uploadSeconds;
                    }
                } else {
                    gpuStatePtr = &localGpuState;
                    const auto txUpload0 = std::chrono::steady_clock::now();
                    CudaParticleStateDiagnostics uploadDiag{};
                    gpuStatePtr->upload_all(state, &uploadDiag);
                    externalUploadSeconds =
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - txUpload0).count() + uploadDiag.uploadSeconds;
                }

                GpuDeviceCarrier0455 dc = apply_gpu_particle_edits_device_carrier_resident_0467(
                    *gpuStatePtr, state, editWorkspace, grid, params, false);
                dc.uploadSeconds += externalUploadSeconds;
                dc.totalSeconds += externalUploadSeconds;
                dc.residentExternal0467B = 1u;
                dc.residentDeferredDownload0468 = 1u;
                dc.residentDirectCommit0471 = 1u;
                dc.residentSharedState0472 = useSharedState0472 ? 1u : 0u;
                dc.residentSharedUploadSkipped0472 = (useSharedState0472 && sharedWasFresh0472) ? 1u : 0u;
                dc.residentActivePrefixDownload0472 = activePrefixDownload0472 ? 1u : 0u;

                const bool ok = (dc.pass && dc.invalidMaterializeOps == 0u && dc.invalidApplyOps == 0u &&
                                 dc.extractionApplied == d.passiveOps && dc.insertionApplied == d.passiveOps);
                if (ok) {
                    const auto txDownload0 = std::chrono::steady_clock::now();
                    CudaParticleStateDiagnostics downloadDiag{};
                    if (activePrefixDownload0472) {
                        gpuStatePtr->download_active_prefix(state, &downloadDiag);
                    } else {
                        gpuStatePtr->download_all(state, &downloadDiag);
                    }
                    const double externalStateDownloadSeconds =
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - txDownload0).count() + downloadDiag.downloadSeconds;
                    dc.stateDownloadSeconds += externalStateDownloadSeconds;
                    dc.totalSeconds += externalStateDownloadSeconds;
                    if (useSharedState0472) {
                        cuda_shared_particle_state_0251_mark_fresh("resampling_direct_commit_0472");
                    }
                } else if (useSharedState0472) {
                    cuda_shared_particle_state_0251_invalidate("resampling_direct_commit_0472_failed");
                }
'''
rep(old, new, '0471 direct-state commit upload/download block')

# Extend device-carrier CSV header and row.
rep('''               "uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,residentCore0467,residentExternal0467B,residentDeferredDownload0468,residentDirectCommit0471,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";
''', '''               "uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,residentCore0467,residentExternal0467B,residentDeferredDownload0468,residentDirectCommit0471,residentSharedState0472,residentSharedUploadSkipped0472,residentActivePrefixDownload0472,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";
''', 'device carrier CSV 0472 header')

rep('''        << d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.residentDeferredDownload0468 << ',' << d.residentDirectCommit0471 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','
        << d.applyKernelSeconds << ',' << d.stateDownloadSeconds << ',' << d.totalSeconds << '\\n';
''', '''        << d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.residentDeferredDownload0468 << ',' << d.residentDirectCommit0471 << ',' << d.residentSharedState0472 << ',' << d.residentSharedUploadSkipped0472 << ',' << d.residentActivePrefixDownload0472 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','
        << d.applyKernelSeconds << ',' << d.stateDownloadSeconds << ',' << d.totalSeconds << '\\n';
''', 'device carrier CSV 0472 row')

src.write_text(text)

# Patch src_mpcd_base invalidations to keep shared freshness conservative.
base_text = base.read_text()

def brep(old, new, label):
    global base_text
    if old not in base_text:
        raise SystemExit(f'[0472] failed to locate {label}')
    base_text = base_text.replace(old, new, 1)

brep('''    populationGuardEdited = populationGuard.applied;

    if (populationGuardEdited) {
''', '''    populationGuardEdited = populationGuard.applied;
    if (populationGuardEdited) {
        cuda_shared_particle_state_0251_invalidate("cpu_resampling_population_guard_edited_0472");
    }

    if (populationGuardEdited) {
''', 'population guard shared-state invalidation')

brep('''        latentActivation = apply_resampling_latent_activation(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
        planOrTransferEdited = planOrTransferEdited || latentActivation.applied;
    }
''', '''        latentActivation = apply_resampling_latent_activation(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
        planOrTransferEdited = planOrTransferEdited || latentActivation.applied;
        if (latentActivation.applied) {
            cuda_shared_particle_state_0251_invalidate("cpu_resampling_latent_activation_edited_0472");
        }
    }
''', 'latent activation shared-state invalidation')

brep('''            planOrTransferEdited = planOrTransferEdited || extractionApply.applied;

            if (params.resamplingInsertionEnable && extractionApply.applied) {
''', '''            planOrTransferEdited = planOrTransferEdited || extractionApply.applied;
            if (extractionApply.applied) {
                cuda_shared_particle_state_0251_invalidate("cpu_resampling_extraction_edited_0472");
            }

            if (params.resamplingInsertionEnable && extractionApply.applied) {
''', 'CPU extraction shared-state invalidation')

brep('''                planOrTransferEdited = planOrTransferEdited || insertionApply.applied;
            }
''', '''                planOrTransferEdited = planOrTransferEdited || insertionApply.applied;
                if (insertionApply.applied) {
                    cuda_shared_particle_state_0251_invalidate("cpu_resampling_insertion_edited_0472");
                }
            }
''', 'CPU insertion shared-state invalidation')

brep('''        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostRemapDeposit);
''', '''        if (remapApply.applied || thermalApply.applied || massGuardApply.applied) {
            cuda_shared_particle_state_0251_invalidate("resampling_remap_thermal_or_massguard_edited_0472");
        }
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostRemapDeposit);
''', 'remap/thermal/massguard shared-state invalidation')

brep('''        if (thermalApply.applied) {
            {
                MPCD_PROFILE_PHASE(result.profile, ResamplingPostThermalDeposit);
''', '''        if (thermalApply.applied) {
            cuda_shared_particle_state_0251_invalidate("resampling_late_thermal_edited_0472");
            {
                MPCD_PROFILE_PHASE(result.profile, ResamplingPostThermalDeposit);
''', 'late thermal shared-state invalidation')

base.write_text(base_text)
print('[0472] patched shared-state fast sync/direct commit path')

#!/usr/bin/env python3
from pathlib import Path

SRC = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
text = SRC.read_text()

if 'residentDeferredDownload0468' in text:
    print('[0468] deferred resident download markers already present')
    raise SystemExit(0)

# 1) Add env flag helper after 0467B helper.
old = '''bool cuda_resampling_resident_external_carrier_0467b_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B");
}
'''
new = old + '''
bool cuda_resampling_defer_resident_download_0468_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468");
}
'''
if old not in text:
    raise SystemExit('[0468] failed to locate 0467B env helper')
text = text.replace(old, new, 1)

# 2) Add diagnostic field.
old = '    std::uint64_t residentExternal0467B = 0u;\n'
new = old + '    std::uint64_t residentDeferredDownload0468 = 0u;\n'
if old not in text:
    raise SystemExit('[0468] failed to locate residentExternal0467B field')
text = text.replace(old, new, 1)

# 3) Add CSV column and value.
old = 'residentCore0467,residentExternal0467B,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
new = 'residentCore0467,residentExternal0467B,residentDeferredDownload0468,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
if old not in text:
    raise SystemExit('[0468] failed to locate device-carrier CSV header with 0467B column')
text = text.replace(old, new, 1)

old = "<< d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','"
new = "<< d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.residentDeferredDownload0468 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','"
if old not in text:
    raise SystemExit('[0468] failed to locate device-carrier CSV row write with 0467B column')
text = text.replace(old, new, 1)

# 4) Replace 0467B external branch body. Keep the branch location stable.
old = '''            if (cuda_resampling_resident_external_carrier_0467b_requested()) {
                // 0467B: ownership of the CUDA particle state is lifted out of the
                // legacy 0455 carrier wrapper. This is still a transaction-safe path:
                // tmp remains the CPU rollback/commit object and downloadState=true
                // preserves the host state after the resident core applies edits.
                // The point is architectural: the resident core is now called from
                // a caller-owned CudaParticleState, preparing a later multi-step
                // resident path that can suppress upload/download at this level.
                const auto txUpload0 = std::chrono::steady_clock::now();
                CudaParticleState gpuState{};
                CudaParticleStateDiagnostics uploadDiag{};
                gpuState.upload_all(tmp, &uploadDiag);
                const double externalUploadSeconds =
                    std::chrono::duration<double>(std::chrono::steady_clock::now() - txUpload0).count() + uploadDiag.uploadSeconds;
                dc = apply_gpu_particle_edits_device_carrier_resident_0467(
                    gpuState, tmp, editWorkspace, grid, params, true);
                dc.uploadSeconds += externalUploadSeconds;
                dc.residentExternal0467B = 1u;
            } else {
'''
new = '''            if (cuda_resampling_resident_external_carrier_0467b_requested()) {
                // 0467B/0468: ownership of the CUDA particle state is lifted out of
                // the legacy 0455 carrier wrapper. 0468 can call the resident core
                // with downloadState=false and perform the final state download in
                // this caller after the gate/apply status is known. This still keeps
                // transaction safety: tmp is committed to state only after success.
                const bool deferResidentDownload0468 = cuda_resampling_defer_resident_download_0468_requested();
                const auto txUpload0 = std::chrono::steady_clock::now();
                CudaParticleState gpuState{};
                CudaParticleStateDiagnostics uploadDiag{};
                gpuState.upload_all(tmp, &uploadDiag);
                const double externalUploadSeconds =
                    std::chrono::duration<double>(std::chrono::steady_clock::now() - txUpload0).count() + uploadDiag.uploadSeconds;
                dc = apply_gpu_particle_edits_device_carrier_resident_0467(
                    gpuState, tmp, editWorkspace, grid, params, !deferResidentDownload0468);
                dc.uploadSeconds += externalUploadSeconds;
                dc.residentExternal0467B = 1u;
                if (deferResidentDownload0468) {
                    dc.residentDeferredDownload0468 = 1u;
                    const bool residentOk0468 =
                        (dc.pass && dc.invalidMaterializeOps == 0u && dc.invalidApplyOps == 0u &&
                         dc.extractionApplied == d.passiveOps && dc.insertionApplied == d.passiveOps);
                    if (residentOk0468) {
                        const auto txDownload0 = std::chrono::steady_clock::now();
                        CudaParticleStateDiagnostics downloadDiag{};
                        gpuState.download_all(tmp, &downloadDiag);
                        const double externalStateDownloadSeconds =
                            std::chrono::duration<double>(std::chrono::steady_clock::now() - txDownload0).count() + downloadDiag.downloadSeconds;
                        dc.stateDownloadSeconds += externalStateDownloadSeconds;
                        dc.totalSeconds += externalStateDownloadSeconds;
                    }
                }
            } else {
'''
if old not in text:
    raise SystemExit('[0468] failed to locate 0467B external resident carrier branch')
text = text.replace(old, new, 1)

SRC.write_text(text)
print('[0468] patched deferred resident download caller path')

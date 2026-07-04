#!/usr/bin/env python3
from pathlib import Path

SRC = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
text = SRC.read_text()

if 'cuda_resampling_direct_state_commit_0471_requested' in text:
    print('[0471] direct state commit markers already present')
    raise SystemExit(0)

# 1) Env helper after 0470 helper.
anchor = '''bool cuda_resampling_resident_upstream_coupled_probe_0470_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_RESIDENT_UPSTREAM_COUPLED_PROBE_0470");
}
'''
insert = anchor + '''
bool cuda_resampling_direct_state_commit_0471_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471");
}
'''
if anchor not in text:
    raise SystemExit('[0471] failed to locate 0470 env helper')
text = text.replace(anchor, insert, 1)

# 2) Add diagnostic flag field.
old = '    std::uint64_t residentDeferredDownload0468 = 0u;\n'
new = old + '    std::uint64_t residentDirectCommit0471 = 0u;\n'
if old not in text:
    raise SystemExit('[0471] failed to locate residentDeferredDownload0468 field')
text = text.replace(old, new, 1)

# 3) Device-carrier CSV header/value.
old = 'residentCore0467,residentExternal0467B,residentDeferredDownload0468,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
new = 'residentCore0467,residentExternal0467B,residentDeferredDownload0468,residentDirectCommit0471,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
if old not in text:
    raise SystemExit('[0471] failed to locate device-carrier CSV header')
text = text.replace(old, new, 1)

old = "<< d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.residentDeferredDownload0468 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','"
new = "<< d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.residentDeferredDownload0468 << ',' << d.residentDirectCommit0471 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','"
if old not in text:
    raise SystemExit('[0471] failed to locate device-carrier CSV row write')
text = text.replace(old, new, 1)

# 4) Add a direct host-state commit fast path at the top of the 0455 device-carrier branch.
anchor = '''        if (cuda_resampling_device_carrier_0455_requested()) {
            const auto txWrapper0 = std::chrono::steady_clock::now();
            const auto txCopy0 = std::chrono::steady_clock::now();
            ParticleState tmp = state;
'''
insert = '''        if (cuda_resampling_device_carrier_0455_requested()) {
            if (cuda_resampling_direct_state_commit_0471_requested()) {
                // 0471A direct-state commit path: remove the CPU rollback copy
                // ParticleState tmp = state. The host state remains unchanged while
                // the resident core mutates a caller-owned CUDA particle state. Only
                // after the gate/apply status is successful do we download directly
                // into the authoritative host ParticleState. On failure, no download
                // occurs and the original host state is still intact.
                const auto txWrapper0 = std::chrono::steady_clock::now();
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

                const double txDeviceCarrierSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txCarrier0).count();
                d.gpuExtractionApplied = dc.extractionApplied;
                d.gpuInsertionApplied = dc.insertionApplied;
                d.gpuInvalidOperations = dc.invalidMaterializeOps + dc.invalidApplyOps;
                d.applyKernelSeconds = dc.applyKernelSeconds;
                d.totalSeconds = dc.totalSeconds;

                if (!ok) {
                    append_transaction_csv_0466(params, step, d.nActive, d.passiveOps,
                                                0.0, txDeviceCarrierSeconds, 0.0,
                                                std::chrono::duration<double>(std::chrono::steady_clock::now() - txWrapper0).count(),
                                                dc, false);
                }
                append_device_carrier_csv_0455(params, step, dc, true, ok, ok, ok, !ok,
                                               ok ? std::string{} : std::string("0471 direct state commit gate/apply failed"));
                if (!ok) {
                    d.skipped = true;
                    d.skipReason = "0471 direct state commit gate/apply failed; keeping original host state";
                    append_apply_csv_0448(params, d);
                    return d;
                }

                const double txWrapperTotalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txWrapper0).count();
                append_transaction_csv_0466(params, step, d.nActive, d.passiveOps,
                                            0.0, txDeviceCarrierSeconds, 0.0,
                                            txWrapperTotalSeconds, dc, true);
                GpuParticleApply0446 pa{};
                pa.extractionApplied = dc.extractionApplied;
                pa.insertionApplied = dc.insertionApplied;
                pa.invalidOperations = dc.invalidMaterializeOps + dc.invalidApplyOps;
                pa.kernelSeconds = dc.applyKernelSeconds;
                pa.totalSeconds = dc.totalSeconds;
                fill_extraction_insertion_diagnostics_0448(editWorkspace, pa, extractionApply, insertionApply);
                d.handled = true;
                d.applied = true;
                append_apply_csv_0448(params, d);
                return d;
            }
            const auto txWrapper0 = std::chrono::steady_clock::now();
            const auto txCopy0 = std::chrono::steady_clock::now();
            ParticleState tmp = state;
'''
if anchor not in text:
    raise SystemExit('[0471] failed to locate device-carrier transaction branch start')
text = text.replace(anchor, insert, 1)

SRC.write_text(text)
print('[0471] patched direct-state commit fast path')

#!/usr/bin/env python3
from pathlib import Path

src = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
if not src.exists():
    raise SystemExit('[0469] source not found: src/cuda_resampling_pipeline_shadow_0445.cu')
text = src.read_text()

if 'cuda_resampling_resident_no_final_download_probe_0469_requested' in text:
    print('[0469] already patched')
    raise SystemExit(0)

# 1) Add env flag helper near 0468 helper.
anchor = '''bool cuda_resampling_defer_resident_download_0468_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468");
}
'''
insert = anchor + '''
bool cuda_resampling_resident_no_final_download_probe_0469_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_RESIDENT_NO_FINAL_DOWNLOAD_PROBE_0469");
}
'''
if anchor not in text:
    raise SystemExit('[0469] failed to locate 0468 env helper')
text = text.replace(anchor, insert, 1)

# 2) Add dedicated no-final-download CSV helper before transaction CSV helper.
anchor = '''void append_transaction_csv_0466(
    const SimulationParams& params,
'''
helper = r'''
void append_resident_no_final_download_probe_csv_0469(
    const SimulationParams& params,
    std::uint64_t step,
    std::uint64_t nActive,
    std::uint64_t passiveOps,
    const GpuDeviceCarrier0455& dc,
    bool ok,
    double probeWrapperSeconds) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_resident_nodownload_0469.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream f(path, std::ios::app);
    f << std::setprecision(17);
    if (!exists) {
        f << "step,nActive,passiveOps,ok,cpuOps,gpuOps,invalidMaterializeOps,invalidApplyOps,"
             "extractionApplied,insertionApplied,residentCore0467,residentExternal0467B,"
             "residentDeferredDownload0468,uploadSeconds,materializeKernelSeconds,gateDownloadSeconds,"
             "applyKernelSeconds,stateDownloadSeconds,totalSeconds,probeWrapperSeconds\n";
    }
    f << step << ',' << nActive << ',' << passiveOps << ',' << (ok ? 1 : 0) << ','
      << dc.cpuOps << ',' << dc.gpuOps << ',' << dc.invalidMaterializeOps << ',' << dc.invalidApplyOps << ','
      << dc.extractionApplied << ',' << dc.insertionApplied << ','
      << dc.residentCore0467 << ',' << dc.residentExternal0467B << ',' << dc.residentDeferredDownload0468 << ','
      << dc.uploadSeconds << ',' << dc.materializeKernelSeconds << ',' << dc.gateDownloadSeconds << ','
      << dc.applyKernelSeconds << ',' << dc.stateDownloadSeconds << ',' << dc.totalSeconds << ','
      << probeWrapperSeconds << '\n';
}

'''
if anchor not in text:
    raise SystemExit('[0469] failed to locate transaction CSV helper insertion point')
text = text.replace(anchor, helper + anchor, 1)

# 3) Insert shadow no-final-download probe at the beginning of 0467B branch.
anchor = '''            if (cuda_resampling_resident_external_carrier_0467b_requested()) {
                // 0467B/0468: ownership of the CUDA particle state is lifted out of
                // the legacy 0455 carrier wrapper. 0468 can call the resident core
                // with downloadState=false and perform the final state download in
                // this caller after the gate/apply status is known. This still keeps
                // transaction safety: tmp is committed to state only after success.
                const bool deferResidentDownload0468 = cuda_resampling_defer_resident_download_0468_requested();
'''
replacement = '''            if (cuda_resampling_resident_external_carrier_0467b_requested()) {
                // 0467B/0468: ownership of the CUDA particle state is lifted out of
                // the legacy 0455 carrier wrapper. 0468 can call the resident core
                // with downloadState=false and perform the final state download in
                // this caller after the gate/apply status is known. This still keeps
                // transaction safety: tmp is committed to state only after success.
                if (cuda_resampling_resident_no_final_download_probe_0469_requested()) {
                    // 0469A diagnostic shadow: prove that the resident core can run,
                    // gate, and apply on a caller-owned CUDA state without performing
                    // any final particle-state download. The mutated CUDA state is
                    // intentionally discarded here; the normal 0468 transaction path
                    // below still performs the solver mutation and commit.
                    const auto probe0469_0 = std::chrono::steady_clock::now();
                    CudaParticleState probeGpuState0469{};
                    CudaParticleStateDiagnostics probeUploadDiag0469{};
                    const auto probeUpload0_0469 = std::chrono::steady_clock::now();
                    probeGpuState0469.upload_all(tmp, &probeUploadDiag0469);
                    const double probeUploadSeconds0469 =
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - probeUpload0_0469).count() +
                        probeUploadDiag0469.uploadSeconds;
                    GpuDeviceCarrier0455 probeDc0469 = apply_gpu_particle_edits_device_carrier_resident_0467(
                        probeGpuState0469, tmp, editWorkspace, grid, params, false);
                    probeDc0469.uploadSeconds += probeUploadSeconds0469;
                    probeDc0469.totalSeconds += probeUploadSeconds0469;
                    probeDc0469.residentExternal0467B = 1u;
                    probeDc0469.residentDeferredDownload0468 = 1u;
                    const bool probeOk0469 =
                        (probeDc0469.pass && probeDc0469.invalidMaterializeOps == 0u && probeDc0469.invalidApplyOps == 0u &&
                         probeDc0469.extractionApplied == d.passiveOps && probeDc0469.insertionApplied == d.passiveOps &&
                         probeDc0469.stateDownloadSeconds == 0.0);
                    append_resident_no_final_download_probe_csv_0469(
                        params, step, d.nActive, d.passiveOps, probeDc0469, probeOk0469,
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - probe0469_0).count());
                }
                const bool deferResidentDownload0468 = cuda_resampling_defer_resident_download_0468_requested();
'''
if anchor not in text:
    raise SystemExit('[0469] failed to locate 0467B/0468 external carrier branch')
text = text.replace(anchor, replacement, 1)

src.write_text(text)
print('[0469] patched resident no-final-download diagnostic probe')

#!/usr/bin/env python3
from pathlib import Path

SRC = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
text = SRC.read_text()

if 'cuda_resampling_resident_upstream_coupled_probe_0470_requested' in text:
    print('[0470] source already contains resident upstream-coupled probe')
    raise SystemExit(0)

anchor_env = '''bool cuda_resampling_resident_no_final_download_probe_0469_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_RESIDENT_NO_FINAL_DOWNLOAD_PROBE_0469");
}
'''
insert_env = anchor_env + '''

bool cuda_resampling_resident_upstream_coupled_probe_0470_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_RESIDENT_UPSTREAM_COUPLED_PROBE_0470");
}
'''
if anchor_env not in text:
    raise SystemExit('[0470] failed to locate 0469 env-function anchor')
text = text.replace(anchor_env, insert_env, 1)

anchor_append = '''void append_transaction_csv_0466(
'''
insert_append = r'''void append_resident_upstream_coupled_probe_csv_0470(
    const SimulationParams& params,
    std::uint64_t step,
    std::uint64_t nActive,
    std::uint64_t passiveOps,
    std::uint64_t nCells,
    bool upstreamOk,
    bool carrierOk,
    double maxCountDiff,
    double maxMassAbs,
    double maxPxAbs,
    double maxPyAbs,
    double depositKernelSeconds,
    double depositDownloadSeconds,
    double probeUploadSeconds,
    const GpuDeviceCarrier0455& dc,
    double probeWrapperSeconds) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_resident_upstream_0470.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream f(path, std::ios::app);
    f << std::setprecision(17);
    if (!exists) {
        f << "step,nActive,passiveOps,nCells,upstreamOk,carrierOk,ok,maxCountDiff,maxMassAbs,maxPxAbs,maxPyAbs,"
             "depositKernelSeconds,depositDownloadSeconds,probeUploadSeconds,cpuOps,gpuOps,invalidMaterializeOps,invalidApplyOps,"
             "extractionApplied,insertionApplied,residentCore0467,residentExternal0467B,residentDeferredDownload0468,"
             "uploadSeconds,materializeKernelSeconds,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds,probeWrapperSeconds\n";
    }
    const bool ok = upstreamOk && carrierOk;
    f << step << ',' << nActive << ',' << passiveOps << ',' << nCells << ','
      << (upstreamOk ? 1 : 0) << ',' << (carrierOk ? 1 : 0) << ',' << (ok ? 1 : 0) << ','
      << maxCountDiff << ',' << maxMassAbs << ',' << maxPxAbs << ',' << maxPyAbs << ','
      << depositKernelSeconds << ',' << depositDownloadSeconds << ',' << probeUploadSeconds << ','
      << dc.cpuOps << ',' << dc.gpuOps << ',' << dc.invalidMaterializeOps << ',' << dc.invalidApplyOps << ','
      << dc.extractionApplied << ',' << dc.insertionApplied << ','
      << dc.residentCore0467 << ',' << dc.residentExternal0467B << ',' << dc.residentDeferredDownload0468 << ','
      << dc.uploadSeconds << ',' << dc.materializeKernelSeconds << ',' << dc.gateDownloadSeconds << ','
      << dc.applyKernelSeconds << ',' << dc.stateDownloadSeconds << ',' << dc.totalSeconds << ','
      << probeWrapperSeconds << '\n';
}

'''
if anchor_append not in text:
    raise SystemExit('[0470] failed to locate transaction CSV append anchor')
text = text.replace(anchor_append, insert_append + anchor_append, 1)

anchor_block = '''                if (cuda_resampling_resident_no_final_download_probe_0469_requested()) {
'''
insert_block = r'''                if (cuda_resampling_resident_upstream_coupled_probe_0470_requested()) {
                    // 0470A diagnostic shadow: upload a caller-owned CUDA particle
                    // state once, run an upstream CUDA deposit on that same resident
                    // state, then run the resident carrier core with downloadState=false.
                    // The mutated device state is intentionally discarded; the normal
                    // 0468 transaction path below still performs the solver mutation.
                    const auto probe0470_0 = std::chrono::steady_clock::now();
                    CudaParticleState probeGpuState0470{};
                    CudaParticleStateDiagnostics probeUploadDiag0470{};
                    const auto probeUpload0_0470 = std::chrono::steady_clock::now();
                    probeGpuState0470.upload_all(tmp, &probeUploadDiag0470);
                    const double probeUploadSeconds0470 =
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - probeUpload0_0470).count() +
                        probeUploadDiag0470.uploadSeconds;

                    CudaCellWorkspace probeCellWorkspace0470{};
                    CudaCellMoments probeDeposit0470{};
                    CudaCellMomentsDiagnostics probeDepositDiag0470{};
                    CudaCellMomentsOptions probeDepositOptions0470{};
                    probeDepositOptions0470.computeCellVelocities = true;
                    probeDepositOptions0470.downloadCellVelocities = true;
                    probeDepositOptions0470.enableAllFluidFastPath = true;
                    probeDepositOptions0470.enableUniformMassFastPath = true;
                    cuda_deposit_cell_moments_atomic_from_persistent_state(
                        tmp, probeGpuState0470, probeCellWorkspace0470, grid, GridShift{}, params,
                        probeDeposit0470, &probeDepositDiag0470, probeDepositOptions0470);

                    const std::size_t nCells0470 = static_cast<std::size_t>(std::max(0, grid.numCells));
                    double maxCountDiff0470 = 0.0;
                    double maxMassAbs0470 = 0.0;
                    double maxPxAbs0470 = 0.0;
                    double maxPyAbs0470 = 0.0;
                    bool upstreamOk0470 = (nCells0470 > 0u && editWorkspace.mass.size() == nCells0470 &&
                                           editWorkspace.count.size() == nCells0470 && editWorkspace.px.size() == nCells0470 &&
                                           editWorkspace.py.size() == nCells0470 && probeDeposit0470.cellMass.size() == nCells0470 &&
                                           probeDeposit0470.cellCount.size() == nCells0470 && probeDeposit0470.cellPx.size() == nCells0470 &&
                                           probeDeposit0470.cellPy.size() == nCells0470);
                    if (upstreamOk0470) {
                        for (std::size_t c = 0; c < nCells0470; ++c) {
                            maxCountDiff0470 = std::max(maxCountDiff0470,
                                std::abs(static_cast<double>(editWorkspace.count[c]) - static_cast<double>(probeDeposit0470.cellCount[c])));
                            maxMassAbs0470 = std::max(maxMassAbs0470, std::abs(editWorkspace.mass[c] - probeDeposit0470.cellMass[c]));
                            maxPxAbs0470 = std::max(maxPxAbs0470, std::abs(editWorkspace.px[c] - probeDeposit0470.cellPx[c]));
                            maxPyAbs0470 = std::max(maxPyAbs0470, std::abs(editWorkspace.py[c] - probeDeposit0470.cellPy[c]));
                        }
                        constexpr double tol0470 = 2.0e-10;
                        upstreamOk0470 = (maxCountDiff0470 == 0.0 && maxMassAbs0470 <= tol0470 &&
                                          maxPxAbs0470 <= tol0470 && maxPyAbs0470 <= tol0470);
                    }

                    GpuDeviceCarrier0455 probeDc0470 = apply_gpu_particle_edits_device_carrier_resident_0467(
                        probeGpuState0470, tmp, editWorkspace, grid, params, false);
                    probeDc0470.uploadSeconds += probeUploadSeconds0470;
                    probeDc0470.totalSeconds += probeUploadSeconds0470;
                    probeDc0470.residentExternal0467B = 1u;
                    probeDc0470.residentDeferredDownload0468 = 1u;
                    const bool carrierOk0470 =
                        (probeDc0470.pass && probeDc0470.invalidMaterializeOps == 0u && probeDc0470.invalidApplyOps == 0u &&
                         probeDc0470.extractionApplied == d.passiveOps && probeDc0470.insertionApplied == d.passiveOps &&
                         probeDc0470.stateDownloadSeconds == 0.0);
                    append_resident_upstream_coupled_probe_csv_0470(
                        params, step, d.nActive, d.passiveOps, static_cast<std::uint64_t>(nCells0470), upstreamOk0470, carrierOk0470,
                        maxCountDiff0470, maxMassAbs0470, maxPxAbs0470, maxPyAbs0470,
                        probeDepositDiag0470.kernelSeconds, probeDepositDiag0470.downloadSeconds,
                        probeUploadSeconds0470, probeDc0470,
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - probe0470_0).count());
                }

'''
if anchor_block not in text:
    raise SystemExit('[0470] failed to locate 0469 probe insertion anchor')
text = text.replace(anchor_block, insert_block + anchor_block, 1)

SRC.write_text(text)
print('[0470] patched resident upstream-coupled diagnostic probe')

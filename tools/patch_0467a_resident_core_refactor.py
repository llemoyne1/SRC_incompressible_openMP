#!/usr/bin/env python3
from pathlib import Path
import re

src = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
text = src.read_text()

if 'apply_gpu_particle_edits_device_carrier_resident_0467' in text:
    print('[0467A] resident core refactor already present')
    raise SystemExit(0)

# 1) Add a diagnostic marker to the existing device-carrier struct/CSV.  This is
# intentionally benign: old parsers read by column name and ignore unknown extra
# columns, while the 0467 probe can prove the refactored core was used.
needle = '    std::uint64_t thrustCellListMaterializer0460 = 0u;\n'
if needle not in text:
    raise SystemExit('[0467A] failed to locate GpuDeviceCarrier0455 thrust marker field')
text = text.replace(needle, needle + '    std::uint64_t residentCore0467 = 0u;\n', 1)

# Header/row insertions are deliberately guarded: the exact header may include
# 0461/0466 additions, but the materializer columns are stable.
header_old = 'cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n'
header_new = 'cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,residentCore0467,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n'
if header_old in text:
    text = text.replace(header_old, header_new, 1)
else:
    raise SystemExit('[0467A] failed to locate device-carrier CSV header materializer columns')

row_old = '<< d.uploadSeconds << \',\' << d.materializeKernelSeconds << \',\' << d.cpuOpCarrier0458 << \',\' << d.donorSliceMaterializer0459 << \',\' << d.thrustCellListMaterializer0460 << \',\' << d.sparseGate0461'
row_new = '<< d.uploadSeconds << \',\' << d.materializeKernelSeconds << \',\' << d.cpuOpCarrier0458 << \',\' << d.donorSliceMaterializer0459 << \',\' << d.thrustCellListMaterializer0460 << \',\' << d.residentCore0467 << \',\' << d.sparseGate0461'
if row_old in text:
    text = text.replace(row_old, row_new, 1)
else:
    raise SystemExit('[0467A] failed to locate device-carrier CSV row materializer columns')

# 2) Extract the current 0455 function and turn it into a resident core that
# takes a CudaParticleState& supplied by the caller.  It must not allocate a
# local CudaParticleState and must not upload internally.
start_marker = 'GpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455(\n'
end_marker = '\nvoid append_device_carrier_csv_0455('
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('[0467A] failed to locate 0455 device-carrier function boundaries')
old_func = text[start:end]

sig_old = '''GpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455(
    ParticleState& state,
    const WeightedRealFluidDepositWorkspace& ws,
    const CellGrid& grid,
    const SimulationParams& params) {'''
sig_new = '''GpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_resident_0467(
    CudaParticleState& gpuState,
    ParticleState& state,
    const WeightedRealFluidDepositWorkspace& ws,
    const CellGrid& grid,
    const SimulationParams& params,
    bool downloadState) {'''
if sig_old not in old_func:
    raise SystemExit('[0467A] failed to locate 0455 function signature')
resident_func = old_func.replace(sig_old, sig_new, 1)

upload_block_old = '''    const auto t0 = std::chrono::steady_clock::now();
    const auto upload0 = std::chrono::steady_clock::now();
    CudaParticleState gpuState{};
    CudaParticleStateDiagnostics uploadDiag{};
    gpuState.upload_all(state, &uploadDiag);
    auto view = gpuState.device_view();'''
upload_block_new = '''    const auto t0 = std::chrono::steady_clock::now();
    auto view = gpuState.device_view();
    if (view.n != state.Np) {
        throw std::runtime_error("0467 resident device carrier: device/host particle capacity mismatch");
    }
    if (view.nActiveFluid != state.NactiveFluid) {
        throw std::runtime_error("0467 resident device carrier: device/host active-prefix mismatch");
    }'''
if upload_block_old not in resident_func:
    raise SystemExit('[0467A] failed to locate local CudaParticleState upload block in 0455 function')
resident_func = resident_func.replace(upload_block_old, upload_block_new, 1)

upload_seconds_old = '    out.uploadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - upload0).count() + uploadDiag.uploadSeconds;'
upload_seconds_new = '    out.uploadSeconds = 0.0;\n    out.residentCore0467 = 1u;'
if upload_seconds_old not in resident_func:
    raise SystemExit('[0467A] failed to locate uploadSeconds assignment in 0455 function')
resident_func = resident_func.replace(upload_seconds_old, upload_seconds_new, 1)

download_block_old = '''    if (out.invalidApplyOps == 0u) {
        const auto dl0 = std::chrono::steady_clock::now();
        CudaParticleStateDiagnostics downloadDiag{};
        gpuState.download_all(state, &downloadDiag);
        out.stateDownloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - dl0).count() + downloadDiag.downloadSeconds;
        out.pass = true;
    }'''
download_block_new = '''    if (out.invalidApplyOps == 0u) {
        if (downloadState) {
            const auto dl0 = std::chrono::steady_clock::now();
            CudaParticleStateDiagnostics downloadDiag{};
            gpuState.download_all(state, &downloadDiag);
            out.stateDownloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - dl0).count() + downloadDiag.downloadSeconds;
        } else {
            out.stateDownloadSeconds = 0.0;
        }
        out.pass = true;
    }'''
if download_block_old not in resident_func:
    raise SystemExit('[0467A] failed to locate final download_all block in 0455 function')
resident_func = resident_func.replace(download_block_old, download_block_new, 1)

# 3) Reintroduce the old public/local entry point as a thin compatibility
# wrapper. Existing callers are unchanged, but the body now goes through the
# resident core. This is the architectural seam needed for the next patch.
wrapper_func = r'''
GpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455(
    ParticleState& state,
    const WeightedRealFluidDepositWorkspace& ws,
    const CellGrid& grid,
    const SimulationParams& params) {
    GpuDeviceCarrier0455 out{};
    out.cpuOps = static_cast<std::uint64_t>(ws.passiveExtractionOperations.size());
    if (ws.transferPlan.empty() || ws.passiveExtractionOperations.empty()) {
        out.pass = ws.passiveExtractionOperations.empty();
        return out;
    }

    const auto t0 = std::chrono::steady_clock::now();
    const auto upload0 = std::chrono::steady_clock::now();
    CudaParticleState gpuState{};
    CudaParticleStateDiagnostics uploadDiag{};
    gpuState.upload_all(state, &uploadDiag);
    const double wrapperUploadSeconds =
        std::chrono::duration<double>(std::chrono::steady_clock::now() - upload0).count() + uploadDiag.uploadSeconds;

    out = apply_gpu_particle_edits_device_carrier_resident_0467(
        gpuState, state, ws, grid, params, true);
    out.uploadSeconds += wrapperUploadSeconds;
    out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return out;
}
'''

text = text[:start] + resident_func + '\n\n' + wrapper_func + text[end:]

src.write_text(text)
print('[0467A] patched minimal resident device-carrier core refactor')

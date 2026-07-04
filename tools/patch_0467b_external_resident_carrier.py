#!/usr/bin/env python3
from pathlib import Path

SRC = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
text = SRC.read_text()

if 'residentExternal0467B' in text:
    print('[0467B] resident external carrier markers already present')
    raise SystemExit(0)

# 1) Add env flag helper after the 0455 carrier flag helper.
old = '''bool cuda_resampling_device_carrier_0455_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455");
}
'''
new = old + '''
bool cuda_resampling_resident_external_carrier_0467b_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B");
}
'''
if old not in text:
    raise SystemExit('[0467B] failed to locate 0455 carrier env helper')
text = text.replace(old, new, 1)

# 2) Add diagnostic field to device-carrier struct.
old = '    std::uint64_t residentCore0467 = 0u;\n'
new = old + '    std::uint64_t residentExternal0467B = 0u;\n'
if old not in text:
    raise SystemExit('[0467B] failed to locate residentCore0467 field')
text = text.replace(old, new, 1)

# 3) Add CSV column and output value.
old = 'thrustCellListMaterializer0460,residentCore0467,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
new = 'thrustCellListMaterializer0460,residentCore0467,residentExternal0467B,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
if old not in text:
    raise SystemExit('[0467B] failed to locate device-carrier CSV header')
text = text.replace(old, new, 1)

old = "<< d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','"
new = "<< d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','"
if old not in text:
    raise SystemExit('[0467B] failed to locate device-carrier CSV row write')
text = text.replace(old, new, 1)

# 4) Replace only the device-carrier call in the 0448 transaction wrapper.
old = '''            const auto txCarrier0 = std::chrono::steady_clock::now();
            const GpuDeviceCarrier0455 dc =
                apply_gpu_particle_edits_device_carrier_0455(tmp, editWorkspace, grid, params);
            const double txDeviceCarrierSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txCarrier0).count();
'''
new = '''            const auto txCarrier0 = std::chrono::steady_clock::now();
            GpuDeviceCarrier0455 dc{};
            if (cuda_resampling_resident_external_carrier_0467b_requested()) {
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
                dc = apply_gpu_particle_edits_device_carrier_0455(tmp, editWorkspace, grid, params);
            }
            const double txDeviceCarrierSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txCarrier0).count();
'''
if old not in text:
    raise SystemExit('[0467B] failed to locate 0448 device-carrier transaction call')
text = text.replace(old, new, 1)

SRC.write_text(text)
print('[0467B] patched external resident carrier call path')

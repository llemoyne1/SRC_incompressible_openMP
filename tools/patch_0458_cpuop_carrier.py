#!/usr/bin/env python3
from pathlib import Path
import re

p = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
s = p.read_text()

marker = 'GpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455(\n'
if marker not in s:
    raise SystemExit('Cannot find apply_gpu_particle_edits_device_carrier_0455')

# Insert helper near the beginning of the anonymous namespace if not present.
helper = r'''

bool cuda_resampling_cpu_op_carrier_0458_requested()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458");
    if (!env) return false;
    const std::string v(env);
    return !v.empty() && v != "0" && v != "false" && v != "FALSE" && v != "off" && v != "OFF";
}
'''
if 'cuda_resampling_cpu_op_carrier_0458_requested' not in s:
    # place just before GpuDeviceCarrier0455 struct, still inside anonymous namespace
    anchor = 'struct GpuDeviceCarrier0455 {'
    if anchor not in s:
        raise SystemExit('Cannot find GpuDeviceCarrier0455 anchor')
    s = s.replace(anchor, helper + '\n' + anchor, 1)

# Add diagnostic field to struct.
old_struct_line = '    double materializeKernelSeconds = 0.0;\n'
new_struct_line = '    double materializeKernelSeconds = 0.0;\n    std::uint64_t cpuOpCarrier0458 = 0u;\n'
if 'cpuOpCarrier0458' not in s:
    if old_struct_line not in s:
        raise SystemExit('Cannot find materializeKernelSeconds struct field')
    s = s.replace(old_struct_line, new_struct_line, 1)

# Add CSV header/value column.
old_header = '"uploadSeconds,materializeKernelSeconds,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
new_header = '"uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";'
if 'cpuOpCarrier0458,gateDownloadSeconds' not in s:
    if old_header not in s:
        raise SystemExit('Cannot find device carrier CSV header')
    s = s.replace(old_header, new_header, 1)

old_value = '        << d.uploadSeconds << \',\' << d.materializeKernelSeconds << \',\' << d.gateDownloadSeconds << \',\''
new_value = '        << d.uploadSeconds << \',\' << d.materializeKernelSeconds << \',\' << d.cpuOpCarrier0458 << \',\' << d.gateDownloadSeconds << \',\''
if '<< d.cpuOpCarrier0458 <<' not in s:
    if old_value not in s:
        raise SystemExit('Cannot find device carrier CSV value line')
    s = s.replace(old_value, new_value, 1)

# Replace materializer launch block in apply_gpu_particle_edits_device_carrier_0455 only.
old = r'''    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    CUDA_CHECK_0445(cudaEventRecord(start));
    materialize_passive_ops_serial_kernel_0453<<<1,1>>>(
        static_cast<std::size_t>(state.NactiveFluid), view.x, view.y, view.mass, view.vx, view.vy, view.type, view.role,
        grid.Nx, grid.Ny, grid.dx, grid.dy,
        is_x_periodic(params) ? 1 : 0, is_y_periodic(params) ? 1 : 0,
        static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
        dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,
        dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,
        dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    CUDA_CHECK_0445(cudaGetLastError());
    float materializeMs = 0.0f;
    CUDA_CHECK_0445(cudaEventElapsedTime(&materializeMs, start, stop));
    CUDA_CHECK_0445(cudaEventDestroy(start));
    CUDA_CHECK_0445(cudaEventDestroy(stop));
    out.materializeKernelSeconds = static_cast<double>(materializeMs) * 1.0e-3;
'''
new = r'''    cudaEvent_t start{}, stop{};
    const bool cpuOpCarrier0458 = cuda_resampling_cpu_op_carrier_0458_requested();
    out.cpuOpCarrier0458 = cpuOpCarrier0458 ? 1u : 0u;
    if (cpuOpCarrier0458) {
        // 0458A diagnostic/performance bridge: bypass the validated but serial
        // donor-particle materializer and upload the already-built CPU passive
        // operation vector into the device-carrier buffers. This intentionally
        // does NOT claim host-free materialization; it isolates the cost of the
        // serial CUDA materializer so that the apply/remap/thermal path can be
        // timed independently.
        const auto& cpuOps0458 = ws.passiveExtractionOperations;
        if (cpuOps0458.size() > maxOps) throw std::runtime_error("0458 CPU-op carrier op count overflow");
        std::vector<unsigned int> hOutCount(1u, static_cast<unsigned int>(cpuOps0458.size()));
        std::vector<unsigned int> hInvalid(1u, 0u);
        std::vector<unsigned int> hParticle(cpuOps0458.size());
        std::vector<int> hDonor(cpuOps0458.size());
        std::vector<int> hReceiver(cpuOps0458.size());
        std::vector<std::uint32_t> hType(cpuOps0458.size());
        std::vector<double> hMass(cpuOps0458.size());
        std::vector<double> hPx(cpuOps0458.size());
        std::vector<double> hPy(cpuOps0458.size());
        std::vector<double> hKe(cpuOps0458.size());
        std::vector<std::uint8_t> hRole(cpuOps0458.size());
        for (std::size_t i = 0; i < cpuOps0458.size(); ++i) {
            const auto& a = cpuOps0458[i];
            hParticle[i] = static_cast<unsigned int>(a.particleIndex);
            hDonor[i] = a.donorCell;
            hReceiver[i] = a.receiverCell;
            hType[i] = a.particleType;
            hMass[i] = a.particleMass;
            hPx[i] = a.momentumX;
            hPy[i] = a.momentumY;
            hKe[i] = a.kineticEnergy;
            hRole[i] = a.currentRole;
        }
        dOutCount.copy_from_host(hOutCount);
        dInvalid.copy_from_host(hInvalid);
        if (!hParticle.empty()) {
            dOutParticle.copy_from_host(hParticle);
            dOutDonor.copy_from_host(hDonor);
            dOutReceiver.copy_from_host(hReceiver);
            dOutType.copy_from_host(hType);
            dOutMass.copy_from_host(hMass);
            dOutPx.copy_from_host(hPx);
            dOutPy.copy_from_host(hPy);
            dOutKe.copy_from_host(hKe);
            dOutRole.copy_from_host(hRole);
        }
        out.materializeKernelSeconds = 0.0;
    } else {
        CUDA_CHECK_0445(cudaEventCreate(&start));
        CUDA_CHECK_0445(cudaEventCreate(&stop));
        CUDA_CHECK_0445(cudaEventRecord(start));
        materialize_passive_ops_serial_kernel_0453<<<1,1>>>(
            static_cast<std::size_t>(state.NactiveFluid), view.x, view.y, view.mass, view.vx, view.vy, view.type, view.role,
            grid.Nx, grid.Ny, grid.dx, grid.dy,
            is_x_periodic(params) ? 1 : 0, is_y_periodic(params) ? 1 : 0,
            static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
            dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,
            dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,
            dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);
        CUDA_CHECK_0445(cudaEventRecord(stop));
        CUDA_CHECK_0445(cudaEventSynchronize(stop));
        CUDA_CHECK_0445(cudaGetLastError());
        float materializeMs = 0.0f;
        CUDA_CHECK_0445(cudaEventElapsedTime(&materializeMs, start, stop));
        CUDA_CHECK_0445(cudaEventDestroy(start));
        CUDA_CHECK_0445(cudaEventDestroy(stop));
        out.materializeKernelSeconds = static_cast<double>(materializeMs) * 1.0e-3;
    }
'''
if old not in s:
    raise SystemExit('Could not find exact 0455 serial materializer launch block. Source may differ; inspect lines 777-796.')
s = s.replace(old, new, 1)

p.write_text(s)
print('0458A CPU-op carrier bridge patch applied')

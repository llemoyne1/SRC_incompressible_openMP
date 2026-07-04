
from pathlib import Path
import re
p = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
s = p.read_text()

if 'sparseGate0461' in s:
    print('[0461A2] sparse gate markers already present; no source patch applied')
    raise SystemExit(0)

anchor = 'struct GpuDeviceCarrier0455 {'
if anchor not in s:
    raise SystemExit('[0461A2] missing GpuDeviceCarrier0455 anchor')
helpers = r'''

bool cuda_resampling_sparse_device_carrier_gate_0461_requested()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461");
    if (!env) return false;
    const std::string v(env);
    return !v.empty() && v != "0" && v != "false" && v != "FALSE" && v != "off" && v != "OFF";
}

std::uint64_t cuda_resampling_sparse_device_carrier_gate_every_0461()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461");
    if (!env) return 1u;
    try {
        const unsigned long long v = std::stoull(std::string(env));
        return v > 0ull ? static_cast<std::uint64_t>(v) : 1u;
    } catch (...) {
        return 1u;
    }
}
'''
s = s.replace(anchor, helpers + '\n' + anchor, 1)

old = '    std::uint64_t thrustCellListMaterializer0460 = 0u;\n'
if old not in s:
    raise SystemExit('[0461A2] missing thrustCellListMaterializer0460 field; is 0460 committed?')
s = s.replace(old, old + '    std::uint64_t sparseGate0461 = 0u;\n    std::uint64_t fullGate0461 = 1u;\n', 1)

old_gate_anchor = '    const auto gate0 = std::chrono::steady_clock::now();\n'
if old_gate_anchor not in s:
    raise SystemExit('[0461A2] missing gate0 anchor')
decision = r'''    const bool sparseGate0461 = cuda_resampling_sparse_device_carrier_gate_0461_requested();
    const std::uint64_t gateEvery0461 = cuda_resampling_sparse_device_carrier_gate_every_0461();
    static std::uint64_t deviceCarrierCall0461 = 0u;
    ++deviceCarrierCall0461;
    const bool fullGate0461 = (!sparseGate0461 || gateEvery0461 <= 1u ||
                               deviceCarrierCall0461 == 1u ||
                               (deviceCarrierCall0461 % gateEvery0461) == 0u);
    out.sparseGate0461 = sparseGate0461 ? 1u : 0u;
    out.fullGate0461 = fullGate0461 ? 1u : 0u;

'''
s = s.replace(old_gate_anchor, decision + old_gate_anchor, 1)

pattern = re.compile(r'''    const auto gate0 = std::chrono::steady_clock::now\(\);\n.*?    if \(!gatePass\) \{\n        out\.pass = false;\n        out\.totalSeconds = std::chrono::duration<double>\(std::chrono::steady_clock::now\(\) - t0\)\.count\(\);\n        return out;\n    \}\n\n(?=    CUDA_CHECK_0445\(cudaEventCreate\(&start\)\);)''', re.S)
replacement = r'''    const auto gate0 = std::chrono::steady_clock::now();
    std::vector<unsigned int> hCount, hInvalid;
    dOutCount.copy_to_host(hCount);
    dInvalid.copy_to_host(hInvalid);
    const std::size_t nOps = hCount.empty() ? 0u : static_cast<std::size_t>(hCount[0]);
    out.gpuOps = static_cast<std::uint64_t>(nOps);
    out.invalidMaterializeOps = hInvalid.empty() ? 0u : static_cast<std::uint64_t>(hInvalid[0]);
    if (nOps > maxOps) throw std::runtime_error("0455 device carrier op count overflow");

    bool gatePass = false;
    if (fullGate0461) {
        std::vector<unsigned int> hParticle;
        std::vector<int> hDonor, hReceiver;
        std::vector<std::uint32_t> hType;
        std::vector<double> hMass, hPx, hPy, hKe;
        std::vector<std::uint8_t> hRole;
        dOutParticle.copy_to_host(hParticle);
        dOutDonor.copy_to_host(hDonor);
        dOutReceiver.copy_to_host(hReceiver);
        dOutType.copy_to_host(hType);
        dOutMass.copy_to_host(hMass);
        dOutPx.copy_to_host(hPx);
        dOutPy.copy_to_host(hPy);
        dOutKe.copy_to_host(hKe);
        dOutRole.copy_to_host(hRole);

        const auto& cpuOps = ws.passiveExtractionOperations;
        const std::size_t cmp = std::min(cpuOps.size(), nOps);
        out.opMismatch = static_cast<std::uint64_t>(std::max(cpuOps.size(), nOps) - cmp);
        for (std::size_t i = 0; i < cmp; ++i) {
            const auto& a = cpuOps[i];
            if (a.particleIndex != static_cast<std::uint64_t>(hParticle[i]) ||
                a.donorCell != hDonor[i] || a.receiverCell != hReceiver[i] ||
                a.particleType != hType[i] || a.currentRole != hRole[i] ||
                a.plannedRoleAfterExtraction != static_cast<std::uint8_t>(ParticleRole::Inactive)) {
                ++out.opMismatch;
            }
            out.maxMassAbs = std::max(out.maxMassAbs, std::abs(a.particleMass - hMass[i]));
            out.maxPxAbs = std::max(out.maxPxAbs, std::abs(a.momentumX - hPx[i]));
            out.maxPyAbs = std::max(out.maxPyAbs, std::abs(a.momentumY - hPy[i]));
            out.cpuMass += a.particleMass;
            out.cpuPx += a.momentumX;
            out.cpuPy += a.momentumY;
            out.cpuKe += a.kineticEnergy;
            out.gpuMass += hMass[i];
            out.gpuPx += hPx[i];
            out.gpuPy += hPy[i];
            out.gpuKe += hKe[i];
        }
        std::vector<std::uint8_t> seen(static_cast<std::size_t>(state.Np), 0u);
        for (std::size_t i = 0; i < nOps; ++i) {
            if (static_cast<std::uint64_t>(hParticle[i]) >= state.Np) {
                ++out.duplicateParticleMismatch;
                continue;
            }
            const std::size_t idx = static_cast<std::size_t>(hParticle[i]);
            if (seen[idx]) ++out.duplicateParticleMismatch;
            seen[idx] = 1u;
        }
        constexpr double tol = 2.0e-10;
        const auto close = [tol](double a, double b) {
            const double scale = std::max({1.0, std::abs(a), std::abs(b)});
            return std::abs(a - b) <= tol * scale;
        };
        gatePass = (out.invalidMaterializeOps == 0u && out.opMismatch == 0u &&
                    out.duplicateParticleMismatch == 0u && out.cpuOps == out.gpuOps &&
                    out.maxMassAbs <= tol && out.maxPxAbs <= tol && out.maxPyAbs <= tol &&
                    close(out.cpuMass, out.gpuMass) && close(out.cpuPx, out.gpuPx) &&
                    close(out.cpuPy, out.gpuPy) && close(out.cpuKe, out.gpuKe));
    } else {
        // Sparse-gate step: keep the mutant CUDA path active, but avoid the heavy
        // operation-buffer downloads. We retain the cheap materializer count and
        // invalid-op checks every step, and still perform apply-result checks below.
        gatePass = (out.invalidMaterializeOps == 0u && out.cpuOps == out.gpuOps);
    }
    out.gateDownloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - gate0).count();
    if (!gatePass) {
        out.pass = false;
        out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        return out;
    }

'''
s2, n = pattern.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit('[0461A2] failed to replace strict gate block on 0460 layout')
s = s2

append_anchor = '    if (params.outputDir.empty()) return;\n'
if append_anchor not in s:
    raise SystemExit('[0461A2] missing append_device_carrier_csv body anchor')
s = s.replace(append_anchor, append_anchor + '    if (d.sparseGate0461 != 0u && d.fullGate0461 == 0u && pass && !skipped) return;\n', 1)

old_header = '"uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n"'
if old_header not in s:
    raise SystemExit('[0461A2] missing 0460 CSV header pattern')
new_header = '"uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n"'
s = s.replace(old_header, new_header, 1)

old_row = "<< d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.gateDownloadSeconds << ','"
if old_row not in s:
    raise SystemExit('[0461A2] missing 0460 CSV row pattern')
new_row = "<< d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','"
s = s.replace(old_row, new_row, 1)

p.write_text(s)
print('[0461A2] patched sparse device-carrier gate on 0460B layout')

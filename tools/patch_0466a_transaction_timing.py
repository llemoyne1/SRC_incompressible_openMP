#!/usr/bin/env python3
from pathlib import Path
import re

src = Path('src/cuda_resampling_pipeline_shadow_0445.cu')
text = src.read_text()

helper_marker = 'cuda_resampling_transaction_0466.csv'
if helper_marker not in text:
    insert_before = '\n} // namespace\n\nCudaResamplingPipelineApply0448Diagnostics try_apply_cuda_resampling_pipeline_particle_edits_0448('
    if insert_before not in text:
        raise SystemExit('[0466A3] failed to locate namespace boundary before 0448 apply wrapper')
    helper = r'''
void append_transaction_csv_0466(
    const SimulationParams& params,
    std::uint64_t step,
    std::uint64_t nActive,
    std::uint64_t passiveOps,
    double tmpCopySeconds,
    double deviceCarrierSeconds,
    double stateCommitSeconds,
    double wrapperTotalSeconds,
    const GpuDeviceCarrier0455& dc,
    bool accepted) {
    if (params.outputDir.empty()) return;
    const std::string path = params.outputDir + "/cuda_resampling_transaction_0466.csv";
    const bool exists = static_cast<bool>(std::ifstream(path).good());
    std::ofstream f(path, std::ios::app);
    if (!exists) {
        f << "step,nActive,passiveOps,tmpCopySeconds,deviceCarrierSeconds,stateCommitSeconds,wrapperTotalSeconds,"
             "deviceUploadSeconds,deviceGateDownloadSeconds,deviceStateDownloadSeconds,deviceMaterializeSeconds,deviceApplySeconds,"
             "deviceTotalSeconds,accepted,cpuOps,gpuOps,invalidMaterializeOps,invalidApplyOps\n";
    }
    f << step << ',' << nActive << ',' << passiveOps << ','
      << tmpCopySeconds << ',' << deviceCarrierSeconds << ',' << stateCommitSeconds << ',' << wrapperTotalSeconds << ','
      << dc.uploadSeconds << ',' << dc.gateDownloadSeconds << ',' << dc.stateDownloadSeconds << ','
      << dc.materializeKernelSeconds << ',' << dc.applyKernelSeconds << ',' << dc.totalSeconds << ','
      << (accepted ? 1 : 0) << ',' << dc.cpuOps << ',' << dc.gpuOps << ','
      << dc.invalidMaterializeOps << ',' << dc.invalidApplyOps << '\n';
}
'''
    text = text.replace(insert_before, '\n' + helper + insert_before, 1)

# Instrument the prologue of the 0455 transaction branch.
if 'txTmpCopySeconds' not in text:
    pat = re.compile(
        r'(\n\s*)if \(cuda_resampling_device_carrier_0455_requested\(\)\) \{\n'
        r'(\s*)ParticleState tmp = state;\n'
        r'(\s*)const GpuDeviceCarrier0455 dc =\n'
        r'(\s*)apply_gpu_particle_edits_device_carrier_0455\(tmp, editWorkspace, grid, params\);'
    )
    m = pat.search(text)
    if not m:
        raise SystemExit('[0466A3] failed to locate device-carrier transaction prologue around ParticleState tmp = state')
    branch_indent = m.group(1)
    body_indent = m.group(2)
    call_indent = m.group(4)
    repl = (
        f"{branch_indent}if (cuda_resampling_device_carrier_0455_requested()) {{\n"
        f"{body_indent}const auto txWrapper0 = std::chrono::steady_clock::now();\n"
        f"{body_indent}const auto txCopy0 = std::chrono::steady_clock::now();\n"
        f"{body_indent}ParticleState tmp = state;\n"
        f"{body_indent}const double txTmpCopySeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txCopy0).count();\n"
        f"{body_indent}const auto txCarrier0 = std::chrono::steady_clock::now();\n"
        f"{body_indent}const GpuDeviceCarrier0455 dc =\n"
        f"{call_indent}apply_gpu_particle_edits_device_carrier_0455(tmp, editWorkspace, grid, params);\n"
        f"{body_indent}const double txDeviceCarrierSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txCarrier0).count();"
    )
    text = text[:m.start()] + repl + text[m.end():]

# Log failed transactions immediately after the bool ok computation. This avoids
# brittle matching of the exact failure-return branch.
failure_marker = 'txFailureLogged0466'
if failure_marker not in text:
    ok_pat = re.compile(
        r'(\n\s*const bool ok = \(dc\.pass && dc\.invalidMaterializeOps == 0u && dc\.invalidApplyOps == 0u &&\n'
        r'\s*dc\.extractionApplied == d\.passiveOps && dc\.insertionApplied == d\.passiveOps\);)'
    )
    m = ok_pat.search(text)
    if not m:
        raise SystemExit('[0466A3] failed to locate 0455 ok computation for transaction CSV')
    indent = re.match(r'\n(\s*)', m.group(1)).group(1)
    insert = (
        m.group(1) + "\n"
        f"{indent}if (!ok) {{\n"
        f"{indent}    const bool txFailureLogged0466 = true;\n"
        f"{indent}    (void)txFailureLogged0466;\n"
        f"{indent}    append_transaction_csv_0466(params, step, d.nActive, d.passiveOps,\n"
        f"{indent}                                txTmpCopySeconds, txDeviceCarrierSeconds, 0.0,\n"
        f"{indent}                                std::chrono::duration<double>(std::chrono::steady_clock::now() - txWrapper0).count(),\n"
        f"{indent}                                dc, false);\n"
        f"{indent}}}"
    )
    text = text[:m.start()] + insert + text[m.end():]

# Log accepted transactions around the state commit.
commit_new_marker = 'txStateCommitSeconds'
if commit_new_marker not in text:
    commit_pat = re.compile(
        r'(\n\s*)state = std::move\(tmp\);\n'
        r'(\s*)GpuParticleApply0446 pa\{\};'
    )
    m = commit_pat.search(text)
    if not m:
        raise SystemExit('[0466A3] failed to locate 0455 accepted commit branch for transaction timing')
    indent = m.group(1)
    body_indent = m.group(2)
    repl = (
        f"{indent}const auto txCommit0 = std::chrono::steady_clock::now();\n"
        f"{body_indent}state = std::move(tmp);\n"
        f"{body_indent}const double txStateCommitSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txCommit0).count();\n"
        f"{body_indent}const double txWrapperTotalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - txWrapper0).count();\n"
        f"{body_indent}append_transaction_csv_0466(params, step, d.nActive, d.passiveOps,\n"
        f"{body_indent}                            txTmpCopySeconds, txDeviceCarrierSeconds, txStateCommitSeconds,\n"
        f"{body_indent}                            txWrapperTotalSeconds, dc, true);\n"
        f"{body_indent}GpuParticleApply0446 pa{{}};"
    )
    text = text[:m.start()] + repl + text[m.end():]

src.write_text(text)
print('[0466A3] patched transaction timing instrumentation around CUDA device-carrier wrapper')

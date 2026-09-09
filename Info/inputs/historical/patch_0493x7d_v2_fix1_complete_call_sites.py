#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_HEAD = "c47f49f8af4cd24e3c551754b2297a37fa173d50"
EXPECTED_DIRTY = {
    "include/simulation_params.h",
    "src/params_io_base.cpp",
    "src/cuda_q6_resident_0400.cu",
    "scripts/src_mpcd_run_common_0434.sh",
}

def run(*args):
    return subprocess.run(
        args, cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False
    )

branch = run("git", "branch", "--show-current").stdout.strip()
head = run("git", "rev-parse", "HEAD").stdout.strip()
if branch != "surf":
    raise SystemExit(f"[0493x7d-v2-fix1] ERROR expected branch surf, got {branch!r}")
if head != EXPECTED_HEAD:
    raise SystemExit(
        f"[0493x7d-v2-fix1] ERROR expected HEAD {EXPECTED_HEAD}, got {head}"
    )

dirty = set()
for line in run("git", "status", "--short", "--untracked-files=no").stdout.splitlines():
    if not line.strip():
        continue
    # porcelain v1: XY + space + path
    path = line[3:].strip()
    dirty.add(path)

unexpected = dirty - EXPECTED_DIRTY
missing = EXPECTED_DIRTY - dirty
if unexpected:
    raise SystemExit(
        "[0493x7d-v2-fix1] ERROR unexpected tracked modifications:\n  " +
        "\n  ".join(sorted(unexpected))
    )
if missing:
    raise SystemExit(
        "[0493x7d-v2-fix1] ERROR partial x7d-v2 state is not the expected one; "
        "missing modified files:\n  " + "\n  ".join(sorted(missing))
    )

# Verify that all changes written before the failed call-site stage are present.
required_markers = {
    "include/simulation_params.h": [
        "q6DensityRelaxationCompressionGateEnable",
        "q6DensityRelaxationCompressionThresholdFill",
    ],
    "src/params_io_base.cpp": [
        "0493x7d-v2 compression gate requires active density relaxation",
        "densityRelaxationCompressionThresholdFill",
    ],
    "src/cuda_q6_resident_0400.cu": [
        "compressionThresholdFill0493x7dv2",
        "compressionGateEnable0493x7dv2",
        "coherent0493x7dv2",
    ],
    "scripts/src_mpcd_run_common_0434.sh": [
        "Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE",
        "Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES",
        "q6DensityRelaxationCompressionThresholdFill",
    ],
}
for rel, markers in required_markers.items():
    text = (ROOT / rel).read_text()
    for marker in markers:
        if marker not in text:
            raise SystemExit(
                f"[0493x7d-v2-fix1] ERROR expected partial marker {marker!r} "
                f"missing in {rel}"
            )

cu_path = ROOT / "src/cuda_q6_resident_0400.cu"
original = cu_path.read_text()
text = original

# -------------------------------------------------------------------------
# A. Complete the two calls to q6_density_relaxation_target_divergence_0493x7c.
# The first patcher had modified the helper signature but had not yet written
# these call-site changes when it aborted.
# -------------------------------------------------------------------------
helper_old = re.compile(
    r'(?P<i>[ \t]*)densityRelaxationRawFill0493x7c,\s*mask,\s*c,\s*nx,\s*ny,\n'
    r'(?P=i)periodicX,\s*periodicY,\s*densityRelaxationBeta0493x7c,\n'
    r'(?P=i)densityRelaxationDt0493x7c,\s*1\);'
)

helper_new_probe = re.compile(
    r'densityRelaxationDt0493x7c,\s*\n'
    r'\s*densityRelaxationCompressionThresholdFill0493x7dv2,\s*\n'
    r'\s*densityRelaxationCompressionGateEnable0493x7dv2,\s*1\);'
)

old_helper_count = len(helper_old.findall(text))
new_helper_count = len(helper_new_probe.findall(text))

if old_helper_count == 2 and new_helper_count == 0:
    def repl_helper(m):
        i = m.group("i")
        return (
            f"{i}densityRelaxationRawFill0493x7c, mask, c, nx, ny,\n"
            f"{i}periodicX, periodicY, densityRelaxationBeta0493x7c,\n"
            f"{i}densityRelaxationDt0493x7c,\n"
            f"{i}densityRelaxationCompressionThresholdFill0493x7dv2,\n"
            f"{i}densityRelaxationCompressionGateEnable0493x7dv2, 1);"
        )
    text, n = helper_old.subn(repl_helper, text)
    if n != 2:
        raise SystemExit(
            f"[0493x7d-v2-fix1] ERROR helper-call replacement expected 2, got {n}"
        )
elif old_helper_count == 0 and new_helper_count == 2:
    print("[0493x7d-v2-fix1] helper call sites already complete")
else:
    raise SystemExit(
        "[0493x7d-v2-fix1] ERROR ambiguous helper-call state: "
        f"old={old_helper_count} new={new_helper_count}"
    )

# -------------------------------------------------------------------------
# B. Complete the two host kernel launches.
# Whitespace/indentation is intentionally flexible: the RHS launch and the
# projected-divergence diagnostic launch live at different nesting depths.
# -------------------------------------------------------------------------
launch_old = re.compile(
    r'(?P<i>[ \t]*)densityRelaxationRequested0493x7c\s*\?\s*'
    r'ws\.phaseFillRaw0493x6c\.data\(\)\s*:\s*nullptr,\n'
    r'(?P=i)densityRelaxationBeta0493x7d,\s*params\.dt,\n'
    r'(?P=i)densityRelaxationRequested0493x7c\s*\?\s*1\s*:\s*0,'
)

launch_new_probe = re.compile(
    r'densityRelaxationBeta0493x7d,\s*params\.dt,\s*\n'
    r'\s*params\.q6DensityRelaxationCompressionThresholdFill,\s*\n'
    r'\s*params\.q6DensityRelaxationCompressionGateEnable\s*\?\s*1\s*:\s*0,\s*\n'
    r'\s*densityRelaxationRequested0493x7c\s*\?\s*1\s*:\s*0,'
)

old_launch_count = len(launch_old.findall(text))
new_launch_count = len(launch_new_probe.findall(text))

if old_launch_count == 2 and new_launch_count == 0:
    def repl_launch(m):
        i = m.group("i")
        return (
            f"{i}densityRelaxationRequested0493x7c ? "
            f"ws.phaseFillRaw0493x6c.data() : nullptr,\n"
            f"{i}densityRelaxationBeta0493x7d, params.dt,\n"
            f"{i}params.q6DensityRelaxationCompressionThresholdFill,\n"
            f"{i}params.q6DensityRelaxationCompressionGateEnable ? 1 : 0,\n"
            f"{i}densityRelaxationRequested0493x7c ? 1 : 0,"
        )
    text, n = launch_old.subn(repl_launch, text)
    if n != 2:
        raise SystemExit(
            f"[0493x7d-v2-fix1] ERROR host-launch replacement expected 2, got {n}"
        )
elif old_launch_count == 0 and new_launch_count == 2:
    print("[0493x7d-v2-fix1] host launch sites already complete")
else:
    raise SystemExit(
        "[0493x7d-v2-fix1] ERROR ambiguous host-launch state: "
        f"old={old_launch_count} new={new_launch_count}"
    )

# Final semantic checks before writing.
if len(helper_new_probe.findall(text)) != 2:
    raise SystemExit("[0493x7d-v2-fix1] ERROR final helper-call count != 2")
if len(launch_new_probe.findall(text)) != 2:
    raise SystemExit("[0493x7d-v2-fix1] ERROR final host-launch count != 2")

# Atomic-at-file-level: only now overwrite CUDA source.
cu_path.write_text(text)

dc = run("git", "diff", "--check")
if dc.returncode != 0:
    # Restore the CUDA file to its pre-fix1 state; the already-written x7d-v2
    # partial modifications from the original patcher are intentionally kept.
    cu_path.write_text(original)
    raise SystemExit(
        "[0493x7d-v2-fix1] ERROR git diff --check failed; CUDA fix rolled back:\n"
        + dc.stdout
    )

print(f"[0493x7d-v2-fix1] branch={branch}")
print(f"[0493x7d-v2-fix1] base={head[:12]}")
print("[0493x7d-v2-fix1] helper target-divergence calls=2/2")
print("[0493x7d-v2-fix1] host CUDA launch sites=2/2")
print("[0493x7d-v2-fix1] git diff --check PASS")
print("[0493x7d-v2-fix1] x7d-v2 patch is now structurally complete")

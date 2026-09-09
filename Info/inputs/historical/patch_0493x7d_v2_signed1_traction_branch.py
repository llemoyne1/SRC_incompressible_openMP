#!/usr/bin/env python3
from pathlib import Path

FILES = {
    "params": Path("include/simulation_params.h"),
    "io": Path("src/params_io_base.cpp"),
    "cuda": Path("src/cuda_q6_resident_0400.cu"),
    "runner": Path("scripts/src_mpcd_run_common_0434.sh"),
}
for label, path in FILES.items():
    if not path.is_file():
        raise SystemExit(f"ERROR [{label}]: missing {path}")

MARKER = "0493x7d-v2-signed1"
if any(MARKER in p.read_text() for p in FILES.values()):
    raise SystemExit(f"ERROR: {MARKER} already appears to be applied")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(
            f"ERROR [{label}]: expected exactly one anchor, found {n}; "
            "working tree does not match the qualified x7d-v2/fix2a state"
        )
    return text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# 1) Parameters: two continuous controls, no new boolean.
#    gain=0 is an exact no-op and therefore preserves x7d-v2 behavior.
# ---------------------------------------------------------------------------
path = FILES["params"]
text = path.read_text()
old = '''    bool q6DensityRelaxationCompressionGateEnable = false;\n    double q6DensityRelaxationCompressionThresholdFill = 0.0;\n'''
new = '''    bool q6DensityRelaxationCompressionGateEnable = false;\n    double q6DensityRelaxationCompressionThresholdFill = 0.0;\n\n    // 0493x7d-v2-signed1 experimental traction/depression branch.  No extra\n    // enable flag: gain=0 is an exact no-op.  When gain>0, a negative density\n    // defect is admitted only when the center and at least one direct\n    // face-neighbour are below -q6DensityRelaxationTractionThresholdFill.\n    // Once classified, the full negative defect is used and multiplied by\n    // q6DensityRelaxationTractionGain.\n    double q6DensityRelaxationTractionThresholdFill = 0.0;\n    double q6DensityRelaxationTractionGain = 0.0;\n'''
text = replace_once(text, old, new, "simulation params")
path.write_text(text)

# ---------------------------------------------------------------------------
# 2) Parser + validation.
# ---------------------------------------------------------------------------
path = FILES["io"]
text = path.read_text()
old = '''        else if (key == "q6DensityRelaxationCompressionGateEnable" || key == "densityRelaxationCompressionGateEnable") p.q6DensityRelaxationCompressionGateEnable = parse_bool(value, key);\n        else if (key == "q6DensityRelaxationCompressionThresholdFill" || key == "densityRelaxationCompressionThresholdFill") p.q6DensityRelaxationCompressionThresholdFill = parse_double(value, key);\n'''
new = '''        else if (key == "q6DensityRelaxationCompressionGateEnable" || key == "densityRelaxationCompressionGateEnable") p.q6DensityRelaxationCompressionGateEnable = parse_bool(value, key);\n        else if (key == "q6DensityRelaxationCompressionThresholdFill" || key == "densityRelaxationCompressionThresholdFill") p.q6DensityRelaxationCompressionThresholdFill = parse_double(value, key);\n        else if (key == "q6DensityRelaxationTractionThresholdFill" || key == "densityRelaxationTractionThresholdFill") p.q6DensityRelaxationTractionThresholdFill = parse_double(value, key);\n        else if (key == "q6DensityRelaxationTractionGain" || key == "densityRelaxationTractionGain") p.q6DensityRelaxationTractionGain = parse_double(value, key);\n'''
text = replace_once(text, old, new, "parser")

old = '''    if (p.q6DensityRelaxationCompressionGateEnable &&\n        !(q6DensityRelaxationEffectiveBeta0493x7d > 0.0)) {\n        throw std::runtime_error(\n            "0493x7d-v2 compression gate requires active density relaxation");\n    }\n    if (q6DensityRelaxationEffectiveBeta0493x7d > 0.0 &&\n'''
new = '''    if (p.q6DensityRelaxationCompressionGateEnable &&\n        !(q6DensityRelaxationEffectiveBeta0493x7d > 0.0)) {\n        throw std::runtime_error(\n            "0493x7d-v2 compression gate requires active density relaxation");\n    }\n    if (!(p.q6DensityRelaxationTractionThresholdFill >= 0.0) ||\n        !std::isfinite(p.q6DensityRelaxationTractionThresholdFill)) {\n        throw std::runtime_error(\n            "0493x7d-v2-signed1 traction threshold fill must be finite and non-negative");\n    }\n    if (!(p.q6DensityRelaxationTractionGain >= 0.0) ||\n        !std::isfinite(p.q6DensityRelaxationTractionGain)) {\n        throw std::runtime_error(\n            "0493x7d-v2-signed1 traction gain must be finite and non-negative");\n    }\n    if (p.q6DensityRelaxationTractionGain > 0.0 &&\n        !(p.q6DensityRelaxationTractionThresholdFill > 0.0)) {\n        throw std::runtime_error(\n            "0493x7d-v2-signed1 traction gain requires q6DensityRelaxationTractionThresholdFill>0");\n    }\n    if (p.q6DensityRelaxationTractionGain > 0.0 &&\n        !p.q6DensityRelaxationCompressionGateEnable) {\n        throw std::runtime_error(\n            "0493x7d-v2-signed1 traction branch requires the coherent x7d-v2 compression gate");\n    }\n    if (p.q6DensityRelaxationTractionGain > 0.0 &&\n        !(q6DensityRelaxationEffectiveBeta0493x7d > 0.0)) {\n        throw std::runtime_error(\n            "0493x7d-v2-signed1 traction branch requires active density relaxation");\n    }\n    if (q6DensityRelaxationEffectiveBeta0493x7d > 0.0 &&\n'''
text = replace_once(text, old, new, "validation")
path.write_text(text)

# ---------------------------------------------------------------------------
# 3) CUDA target: keep the positive branch exactly as x7d-v2 and add a
#    coherent negative branch.  No topology/fullDomain switch is introduced.
# ---------------------------------------------------------------------------
path = FILES["cuda"]
text = path.read_text()

old = '''    double beta,\n    double dt,\n    double compressionThresholdFill0493x7dv2,\n    int compressionGateEnable0493x7dv2,\n    int enabled) {\n'''
new = '''    double beta,\n    double dt,\n    double compressionThresholdFill0493x7dv2,\n    int compressionGateEnable0493x7dv2,\n    double tractionThresholdFill0493x7dv2signed1,\n    double tractionGain0493x7dv2signed1,\n    int enabled) {\n'''
text = replace_once(text, old, new, "target signature")

old = '''    // 0493x7d-v2: classify positive coherent compression before applying the\n    // historical x7d target. Once classified, keep the full defect: this is a\n    // gate, not a dead-band subtraction.\n    if (compressionGateEnable0493x7dv2) {\n        if (!(compressionThresholdFill0493x7dv2 > 0.0) ||\n            defect < compressionThresholdFill0493x7dv2) {\n            return 0.0;\n        }\n\n        bool coherent0493x7dv2 = false;\n        if (periodicX || ix > 0) {\n            const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;\n            const double nd = rawFill[iy * nx + xw] - 1.0;\n            coherent0493x7dv2 =\n                isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n        }\n        if (!coherent0493x7dv2 && (periodicX || ix < nx - 1)) {\n            const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;\n            const double nd = rawFill[iy * nx + xe] - 1.0;\n            coherent0493x7dv2 =\n                isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n        }\n        if (!coherent0493x7dv2 && (periodicY || iy > 0)) {\n            const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;\n            const double nd = rawFill[ys * nx + ix] - 1.0;\n            coherent0493x7dv2 =\n                isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n        }\n        if (!coherent0493x7dv2 && (periodicY || iy < ny - 1)) {\n            const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;\n            const double nd = rawFill[yn * nx + ix] - 1.0;\n            coherent0493x7dv2 =\n                isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n        }\n        if (!coherent0493x7dv2) return 0.0;\n    }\n\n    return beta * defect / dt;\n'''
new = '''    // 0493x7d-v2: classify positive coherent compression before applying the\n    // historical x7d target. Once classified, keep the full defect: this is a\n    // gate, not a dead-band subtraction.\n    if (compressionGateEnable0493x7dv2) {\n        if (compressionThresholdFill0493x7dv2 > 0.0 &&\n            defect >= compressionThresholdFill0493x7dv2) {\n            bool coherent0493x7dv2 = false;\n            if (periodicX || ix > 0) {\n                const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;\n                const double nd = rawFill[iy * nx + xw] - 1.0;\n                coherent0493x7dv2 =\n                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n            }\n            if (!coherent0493x7dv2 && (periodicX || ix < nx - 1)) {\n                const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;\n                const double nd = rawFill[iy * nx + xe] - 1.0;\n                coherent0493x7dv2 =\n                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n            }\n            if (!coherent0493x7dv2 && (periodicY || iy > 0)) {\n                const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;\n                const double nd = rawFill[ys * nx + ix] - 1.0;\n                coherent0493x7dv2 =\n                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n            }\n            if (!coherent0493x7dv2 && (periodicY || iy < ny - 1)) {\n                const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;\n                const double nd = rawFill[yn * nx + ix] - 1.0;\n                coherent0493x7dv2 =\n                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;\n            }\n            if (!coherent0493x7dv2) return 0.0;\n            return beta * defect / dt;\n        }\n\n        // 0493x7d-v2-signed1: coherent traction/depression response.  The\n        // material law is intentionally topology-independent: free-surface\n        // exclusion remains the responsibility of the existing bulk contract\n        // above.  Like the positive branch, this is a classifier only; after\n        // admission the full negative defect is retained.\n        if (tractionGain0493x7dv2signed1 > 0.0 &&\n            tractionThresholdFill0493x7dv2signed1 > 0.0 &&\n            defect <= -tractionThresholdFill0493x7dv2signed1) {\n            bool coherentTraction0493x7dv2signed1 = false;\n            if (periodicX || ix > 0) {\n                const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;\n                const double nd = rawFill[iy * nx + xw] - 1.0;\n                coherentTraction0493x7dv2signed1 =\n                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;\n            }\n            if (!coherentTraction0493x7dv2signed1 && (periodicX || ix < nx - 1)) {\n                const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;\n                const double nd = rawFill[iy * nx + xe] - 1.0;\n                coherentTraction0493x7dv2signed1 =\n                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;\n            }\n            if (!coherentTraction0493x7dv2signed1 && (periodicY || iy > 0)) {\n                const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;\n                const double nd = rawFill[ys * nx + ix] - 1.0;\n                coherentTraction0493x7dv2signed1 =\n                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;\n            }\n            if (!coherentTraction0493x7dv2signed1 && (periodicY || iy < ny - 1)) {\n                const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;\n                const double nd = rawFill[yn * nx + ix] - 1.0;\n                coherentTraction0493x7dv2signed1 =\n                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;\n            }\n            if (!coherentTraction0493x7dv2signed1) return 0.0;\n            return tractionGain0493x7dv2signed1 * beta * defect / dt;\n        }\n\n        return 0.0;\n    }\n\n    return beta * defect / dt;\n'''
text = replace_once(text, old, new, "signed target logic")

# Extend both diagnostic/RHS kernel signatures.
old = '''    double densityRelaxationDt0493x7c,\n    double densityRelaxationCompressionThresholdFill0493x7dv2,\n    int densityRelaxationCompressionGateEnable0493x7dv2,\n    int densityRelaxationEnable0493x7c,\n'''
new = '''    double densityRelaxationDt0493x7c,\n    double densityRelaxationCompressionThresholdFill0493x7dv2,\n    int densityRelaxationCompressionGateEnable0493x7dv2,\n    double densityRelaxationTractionThresholdFill0493x7dv2signed1,\n    double densityRelaxationTractionGain0493x7dv2signed1,\n    int densityRelaxationEnable0493x7c,\n'''
count = text.count(old)
if count != 2:
    raise SystemExit(
        f"ERROR [kernel signatures]: expected two density relaxation signature anchors, found {count}"
    )
text = text.replace(old, new)

# Extend the two calls to the device target helper.
old = '''                densityRelaxationCompressionThresholdFill0493x7dv2,\n                densityRelaxationCompressionGateEnable0493x7dv2, 1);\n'''
new = '''                densityRelaxationCompressionThresholdFill0493x7dv2,\n                densityRelaxationCompressionGateEnable0493x7dv2,\n                densityRelaxationTractionThresholdFill0493x7dv2signed1,\n                densityRelaxationTractionGain0493x7dv2signed1, 1);\n'''
count = text.count(old)
if count != 2:
    raise SystemExit(
        f"ERROR [target call sites]: expected two target helper calls, found {count}"
    )
text = text.replace(old, new)

# Main RHS and projected-divergence launches.  Preserve each call site's
# indentation while inserting the two signed controls.
import re
pattern = re.compile(
    r"(?P<i>[ \t]*)params\.q6DensityRelaxationCompressionThresholdFill,\n"
    r"(?P=i)params\.q6DensityRelaxationCompressionGateEnable \? 1 : 0,\n"
    r"(?P=i)densityRelaxationRequested0493x7c \? 1 : 0,"
)

def _launch_repl(m):
    i = m.group("i")
    return (
        f"{i}params.q6DensityRelaxationCompressionThresholdFill,\n"
        f"{i}params.q6DensityRelaxationCompressionGateEnable ? 1 : 0,\n"
        f"{i}params.q6DensityRelaxationTractionThresholdFill,\n"
        f"{i}params.q6DensityRelaxationTractionGain,\n"
        f"{i}densityRelaxationRequested0493x7c ? 1 : 0,"
    )
text, count = pattern.subn(_launch_repl, text)
if count != 2:
    raise SystemExit(
        f"ERROR [main diagnostic launches]: expected two parameterized launches, found {count}"
    )

# Post-apply diagnostic disables density relaxation entirely; pass neutral
# signed-branch parameters as well.
old = '''                nullptr, 0.0, params.dt, 0.0, 0, 0,\n                audit.fullDomain ? 1 : 0);\n'''
new = '''                nullptr, 0.0, params.dt, 0.0, 0, 0.0, 0.0, 0,\n                audit.fullDomain ? 1 : 0);\n'''
text = replace_once(text, old, new, "post-apply neutral call")
path.write_text(text)

# ---------------------------------------------------------------------------
# 4) Q6-G-F runner controls.  Existing behavior remains default because the
#    traction gain defaults to zero.  The selected first prototype is enabled
#    explicitly with GAIN=0.75 and THRESHOLD_PARTICLES=6.0 at run time.
# ---------------------------------------------------------------------------
path = FILES["runner"]
text = path.read_text()
old = '''  local compression_threshold_particles="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"\n  local compression_threshold_fill\n  compression_threshold_fill="$(awk -v n="$compression_threshold_particles" -v g="$GAMMA" 'BEGIN{\n    if (!(n>0) || !(g>0)) exit 2;\n    printf "%.17g", n/g\n  }')" || {\n    echo "[0493x7d-v2] ERROR compression threshold requires positive particle threshold and GAMMA" >&2\n    return 2\n  }\n  cat <<PARAMS\n'''
new = '''  local compression_threshold_particles="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"\n  local compression_threshold_fill\n  compression_threshold_fill="$(awk -v n="$compression_threshold_particles" -v g="$GAMMA" 'BEGIN{\n    if (!(n>0) || !(g>0)) exit 2;\n    printf "%.17g", n/g\n  }')" || {\n    echo "[0493x7d-v2] ERROR compression threshold requires positive particle threshold and GAMMA" >&2\n    return 2\n  }\n  local traction_gain="${Q6_GF_DENSITY_TRACTION_GAIN:-0.0}"\n  local traction_threshold_particles="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"\n  local traction_threshold_fill\n  traction_threshold_fill="$(awk -v n="$traction_threshold_particles" -v g="$GAMMA" 'BEGIN{\n    if (!(n>0) || !(g>0)) exit 2;\n    printf "%.17g", n/g\n  }')" || {\n    echo "[0493x7d-v2-signed1] ERROR traction threshold requires positive particle threshold and GAMMA" >&2\n    return 2\n  }\n  cat <<PARAMS\n'''
text = replace_once(text, old, new, "runner controls")

old = '''q6DensityRelaxationCompressionGateEnable = ${compression_gate}\nq6DensityRelaxationCompressionThresholdFill = ${compression_threshold_fill}\nkeepMeanFlowEnable = false\n'''
new = '''q6DensityRelaxationCompressionGateEnable = ${compression_gate}\nq6DensityRelaxationCompressionThresholdFill = ${compression_threshold_fill}\nq6DensityRelaxationTractionThresholdFill = ${traction_threshold_fill}\nq6DensityRelaxationTractionGain = ${traction_gain}\nkeepMeanFlowEnable = false\n'''
text = replace_once(text, old, new, "runner params write")

old = '''      grep -Eq '^[[:space:]]*q6DensityRelaxationCompressionThresholdFill[[:space:]]*=[[:space:]]*[0-9.eE+-]+' "$params" || {\n        echo "[0493x7d-v2-run-ok] ERROR compression threshold fill missing" >&2; return 2; }\n    fi\n    if grep -Eq '^[[:space:]]*darcyBrinkmanEnable[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$params"; then\n'''
new = '''      grep -Eq '^[[:space:]]*q6DensityRelaxationCompressionThresholdFill[[:space:]]*=[[:space:]]*[0-9.eE+-]+' "$params" || {\n        echo "[0493x7d-v2-run-ok] ERROR compression threshold fill missing" >&2; return 2; }\n    fi\n    grep -Eq '^[[:space:]]*q6DensityRelaxationTractionThresholdFill[[:space:]]*=[[:space:]]*[0-9.eE+-]+' "$params" || {\n      echo "[0493x7d-v2-signed1-run-ok] ERROR traction threshold fill missing" >&2; return 2; }\n    grep -Eq '^[[:space:]]*q6DensityRelaxationTractionGain[[:space:]]*=[[:space:]]*[0-9.eE+-]+' "$params" || {\n      echo "[0493x7d-v2-signed1-run-ok] ERROR traction gain missing" >&2; return 2; }\n    if grep -Eq '^[[:space:]]*darcyBrinkmanEnable[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$params"; then\n'''
text = replace_once(text, old, new, "runner preflight")
path.write_text(text)

print("PASS: applied 0493x7d-v2-signed1 coherent traction/depression branch")
print("      compression branch unchanged: theta+ from existing x7d-v2 gate")
print("      traction controls: threshold fill + gain; gain=0 is exact no-op")
print("      runner defaults: theta-=6 particles, gain-=0.0")
print("modified:")
for p in FILES.values():
    print(" ", p)

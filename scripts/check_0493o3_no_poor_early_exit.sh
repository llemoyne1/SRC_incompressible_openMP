#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path

files = {
    "header": Path("include/cuda_resampling_population_guard_0297.h"),
    "helper": Path("include/cuda_local_support_split_0493o1.cuh"),
    "source": Path("src/cuda_resampling_population_guard_0297.cu"),
    "caller": Path("src/src_mpcd_base.cpp"),
}
for name, path in files.items():
    if not path.is_file():
        raise SystemExit(f"[0493o3-check] missing {name}: {path}")

header = files["header"].read_text()
helper = files["helper"].read_text()
source = files["source"].read_text()
caller = files["caller"].read_text()

required = {
    "header early flag": (header, "bool noPoorEarlyExit0493o3 = false;"),
    "helper detector": (helper, "detect_local_support_pairs_0493o3("),
    "helper light reset": (helper, "reset_local_support_detection_0493o3"),
    "helper candidate reset": (helper, "reset_local_support_plan_0493o3"),
    "source resolved gate": (source, "resolvedLocalSupportOnly0493o3"),
    "source early return": (source, "if (detectedLocalSupport0493o3.noPoorEarlyExit0493o3)"),
    "core timing CSV": (source, "localSupportCandidateBuildSeconds0493o3"),
    "caller timing CSV": (source, "cuda_resampling_population_guard_caller_0493o3.csv"),
    "caller timing write": (caller, "write_cuda_resampling_population_guard_caller_0493o3("),
}
for label, (text, marker) in required.items():
    if marker not in text:
        raise SystemExit(f"[0493o3-check] missing marker: {label}")

# The no-poor decision must precede kinetic preparation and candidate planning.
if source.index("detect_local_support_pairs_0493o3(") > source.index("tKrelBefore0493o3"):
    raise SystemExit("[0493o3-check] detector is not before pre-mutation kinetic work")
helper_detect = helper.index("LocalSupportSplitResult0493o1 detect_local_support_pairs_0493o3(")
helper_apply = helper.index("LocalSupportSplitResult0493o1 apply_local_support_split_only_0493o1(")
if helper_detect > helper_apply:
    raise SystemExit("[0493o3-check] detector ordering invalid")
detect_body = helper[helper_detect:helper_apply]
for forbidden in (
    "select_local_support_candidates_0493o1<<<",
    "plan_local_support_splits_0493o1<<<",
    "apply_local_support_plan_0493o1<<<",
):
    if forbidden in detect_body:
        raise SystemExit(f"[0493o3-check] detector contains mutating/planning phase: {forbidden}")

# No 0493o3 user parameter is introduced.
for path in (Path("include/simulation_params.h"), Path("src/params_io_base.cpp")):
    if path.is_file() and "0493o3" in path.read_text():
        raise SystemExit(f"[0493o3-check] unexpected new parameter marker in {path}")

# Lightweight lexical delimiter check, ignoring comments and strings.
def stripped(text: str) -> str:
    out = []
    i = 0
    state = "code"
    quote = ""
    while i < len(text):
        c = text[i]
        d = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == "/" and d == "/":
                state = "line"; out.extend("  "); i += 2; continue
            if c == "/" and d == "*":
                state = "block"; out.extend("  "); i += 2; continue
            if c in ('"', "'"):
                state = "string"; quote = c; out.append(" "); i += 1; continue
            out.append(c); i += 1
        elif state == "line":
            out.append("\n" if c == "\n" else " ")
            if c == "\n": state = "code"
            i += 1
        elif state == "block":
            if c == "*" and d == "/":
                state = "code"; out.extend("  "); i += 2
            else:
                out.append("\n" if c == "\n" else " "); i += 1
        else:
            if c == "\\": out.extend("  "); i += 2
            elif c == quote: state = "code"; out.append(" "); i += 1
            else: out.append("\n" if c == "\n" else " "); i += 1
    return "".join(out)

pairs = {")": "(", "]": "[", "}": "{"}
for name, path in files.items():
    stack = []
    for c in stripped(path.read_text()):
        if c in "([{": stack.append(c)
        elif c in ")]}":
            if not stack or stack.pop() != pairs[c]:
                raise SystemExit(f"[0493o3-check] delimiter mismatch in {path}")
    if stack:
        raise SystemExit(f"[0493o3-check] unclosed delimiters in {path}")

print("[0493o3-check] static CUDA fast-exit structure: PASS")
PY

python3 scripts/analyze_0493o3_no_poor_early_exit.py --self-test >/dev/null
printf '%s\n' '[0493o3-check] analyzer self-test: PASS'
printf '%s\n' '[0493o3-check] no new parameters: PASS'
printf '%s\n' '[0493o3-check] no-poor early exit patch: PASS'

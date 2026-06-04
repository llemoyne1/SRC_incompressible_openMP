#!/usr/bin/env python3
"""
0176 OpenMP-light diagnostics cleanup helper.

This script applies minimal, idempotent edits to the current working tree:
  - internal profile CSVs are disabled by default;
  - set MPCD_INTERNAL_PROFILES=1 to re-enable them;
  - runtime/fluid summaries are left unchanged.

It intentionally edits the current files in-place rather than shipping full
source replacements, so it can be applied safely on top of the current 0175
light branch without clobbering later optimizations.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path.cwd()

TRUE_HELPER = r'''
bool internal_profiles_enabled_0176() {
    const char* v = std::getenv("MPCD_INTERNAL_PROFILES");
    if (v == nullptr || *v == '\0') {
        return false;
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}
'''

WEIGHTED_HELPER = r'''
bool internal_profiles_enabled_0176() {
    const char* v = std::getenv("MPCD_INTERNAL_PROFILES");
    if (v == nullptr || *v == '\0') {
        return false;
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}
'''

SRC_HELPER = r'''
bool internal_profiles_enabled_0176() {
    const char* v = std::getenv("MPCD_INTERNAL_PROFILES");
    if (v == nullptr || *v == '\0') {
        return false;
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}
'''


def read(p: Path) -> str:
    if not p.exists():
        raise SystemExit(f"missing file: {p}")
    return p.read_text()


def write_if_changed(p: Path, s: str) -> bool:
    old = p.read_text() if p.exists() else ""
    if old == s:
        return False
    bak = p.with_suffix(p.suffix + ".0176bak")
    if not bak.exists() and p.exists():
        bak.write_text(old)
    p.write_text(s)
    return True


def ensure_include(s: str, include: str, after: str | None = None) -> str:
    line = f"#include <{include}>"
    if line in s:
        return s
    if after and after in s:
        return s.replace(after, after + "\n" + line, 1)
    # fallback: after last include block line
    lines = s.splitlines()
    idx = 0
    for i, line0 in enumerate(lines):
        if line0.startswith("#include "):
            idx = i + 1
    lines.insert(idx, line)
    return "\n".join(lines) + ("\n" if s.endswith("\n") else "")


def patch_main() -> bool:
    p = ROOT / "src" / "main_src_mpcd_base.cpp"
    s = read(p)
    s = ensure_include(s, "cstdlib", after="#include <chrono>")

    if "bool internal_profiles_enabled_0176()" not in s:
        marker = "int openmp_max_threads() {\n#ifdef _OPENMP\n    return omp_get_max_threads();\n#else\n    return 1;\n#endif\n}\n"
        if marker not in s:
            raise SystemExit("main_src_mpcd_base.cpp: cannot find openmp_max_threads marker")
        s = s.replace(marker, marker + "\n" + TRUE_HELPER + "\n", 1)

    old = '''        write_phase_profile_0163(params.outputDir, phaseProfileSeconds, phaseProfileSteps);
        write_q6_cg_profile_0163(params.outputDir, q6ProfileSeconds, ellipticProfileSeconds, q6ProfileSteps);
        write_resampling_guard_profile_0169(params.outputDir,
                                            populationGuardProfileSeconds, populationGuardProfileSteps,
                                            populationGuardOverfullCandidateCells,
                                            populationGuardUnderfullCandidateCells,
                                            populationGuardOverfullEditedCells,
                                            populationGuardUnderfullEditedCells,
                                            populationGuardOverfullCandidateParticleRefs,
                                            populationGuardUnderfullCandidateParticleRefs,
                                            populationGuardOverfullScanPasses,
                                            populationGuardUnderfullScanPasses,
                                            populationGuardOverfullParticleRefsScanned,
                                            populationGuardUnderfullParticleRefsScanned,
                                            populationGuardOverfullEligibleParticleRefs,
                                            populationGuardUnderfullEligibleParticleRefs,
                                            populationGuardOverfullCandidatePopulationMax,
                                            populationGuardUnderfullCandidatePopulationMax,
                                            massGuardProfileSeconds, massGuardProfileSteps);
        std::cout << "\\n[src_mpcd_base] wrote " << params.outputDir << "/phase_profile_0163.csv";
        std::cout << "\\n[src_mpcd_base] wrote " << params.outputDir << "/q6_cg_profile_0163.csv";
        std::cout << "\\n[src_mpcd_base] wrote " << params.outputDir << "/resampling_guard_profile_0169.csv";
        std::cout << "\\n[src_mpcd_base] done\\n";
'''
    new = '''        if (internal_profiles_enabled_0176()) {
            write_phase_profile_0163(params.outputDir, phaseProfileSeconds, phaseProfileSteps);
            write_q6_cg_profile_0163(params.outputDir, q6ProfileSeconds, ellipticProfileSeconds, q6ProfileSteps);
            write_resampling_guard_profile_0169(params.outputDir,
                                                populationGuardProfileSeconds, populationGuardProfileSteps,
                                                populationGuardOverfullCandidateCells,
                                                populationGuardUnderfullCandidateCells,
                                                populationGuardOverfullEditedCells,
                                                populationGuardUnderfullEditedCells,
                                                populationGuardOverfullCandidateParticleRefs,
                                                populationGuardUnderfullCandidateParticleRefs,
                                                populationGuardOverfullScanPasses,
                                                populationGuardUnderfullScanPasses,
                                                populationGuardOverfullParticleRefsScanned,
                                                populationGuardUnderfullParticleRefsScanned,
                                                populationGuardOverfullEligibleParticleRefs,
                                                populationGuardUnderfullEligibleParticleRefs,
                                                populationGuardOverfullCandidatePopulationMax,
                                                populationGuardUnderfullCandidatePopulationMax,
                                                massGuardProfileSeconds, massGuardProfileSteps);
            std::cout << "\\n[src_mpcd_base] wrote " << params.outputDir << "/phase_profile_0163.csv";
            std::cout << "\\n[src_mpcd_base] wrote " << params.outputDir << "/q6_cg_profile_0163.csv";
            std::cout << "\\n[src_mpcd_base] wrote " << params.outputDir << "/resampling_guard_profile_0169.csv";
        } else {
            std::cout << "\\n[src_mpcd_base] internal profile CSV disabled"
                      << " (set MPCD_INTERNAL_PROFILES=1 to enable)";
        }
        std::cout << "\\n[src_mpcd_base] done\\n";
'''
    if old in s and "internal profile CSV disabled" not in s:
        s = s.replace(old, new, 1)
    elif "internal profile CSV disabled" not in s:
        raise SystemExit("main_src_mpcd_base.cpp: profile write block not found or already changed unexpectedly")

    return write_if_changed(p, s)


def patch_weighted() -> bool:
    p = ROOT / "src" / "weighted_resampling.cpp"
    s = read(p)
    s = ensure_include(s, "cstdlib", after="#include <chrono>")
    s = ensure_include(s, "string", after="#include <stdexcept>")

    if "bool internal_profiles_enabled_0176()" not in s:
        marker = "int thread_id() {\n#ifdef _OPENMP\n    return omp_get_thread_num();\n#else\n    return 0;\n#endif\n}\n"
        if marker not in s:
            raise SystemExit("weighted_resampling.cpp: cannot find thread_id marker")
        s = s.replace(marker, marker + "\n" + WEIGHTED_HELPER + "\n", 1)

    old_add = '''        if (contextIndex >= calls.size()) {
            return;
        }
        if (!out.empty()) {
            outputDir = out;
        }
        calls[idx] += 1u;
'''
    new_add = '''        if (!internal_profiles_enabled_0176()) {
            return;
        }
        if (contextIndex >= calls.size()) {
            return;
        }
        if (!out.empty()) {
            outputDir = out;
        }
        calls[idx] += 1u;
'''
    if old_add in s and "if (!internal_profiles_enabled_0176()) {\n            return;\n        }\n        if (contextIndex >= calls.size())" not in s:
        s = s.replace(old_add, new_add, 1)

    old_dtor = '''    ~DepositProfileAccumulator() {
        if (outputDir.empty()) {
            return;
        }
'''
    new_dtor = '''    ~DepositProfileAccumulator() {
        if (!internal_profiles_enabled_0176()) {
            return;
        }
        if (outputDir.empty()) {
            return;
        }
'''
    if old_dtor in s and "~DepositProfileAccumulator() {\n        if (!internal_profiles_enabled_0176())" not in s:
        s = s.replace(old_dtor, new_dtor, 1)

    return write_if_changed(p, s)


def patch_src_mpcd_base() -> bool:
    p = ROOT / "src" / "src_mpcd_base.cpp"
    s = read(p)
    s = ensure_include(s, "cstdlib", after="#include <chrono>")
    s = ensure_include(s, "string", after="#include <limits>")

    if "PostGuardDepositProfileAccumulator" in s and "bool internal_profiles_enabled_0176()" not in s:
        marker = "#define MPCD_PROFILE_PHASE(profile, phaseName) \\\n    ScopedStepProfileTimer mpcdProfileTimer_##phaseName((profile), StepProfilePhaseIndex::phaseName)\n"
        if marker in s:
            s = s.replace(marker, marker + "\n" + SRC_HELPER + "\n", 1)
        else:
            # fallback after macro text without trailing newline variants
            marker2 = "ScopedStepProfileTimer mpcdProfileTimer_##phaseName((profile), StepProfilePhaseIndex::phaseName)\n"
            if marker2 not in s:
                raise SystemExit("src_mpcd_base.cpp: cannot find profile macro marker")
            s = s.replace(marker2, marker2 + "\n" + SRC_HELPER + "\n", 1)

    if "PostGuardDepositProfileAccumulator" in s:
        old_write = '''    void write() const {
        if (outputDir.empty()) {
            return;
        }
'''
        new_write = '''    void write() const {
        if (!internal_profiles_enabled_0176()) {
            return;
        }
        if (outputDir.empty()) {
            return;
        }
'''
        if old_write in s and "void write() const {\n        if (!internal_profiles_enabled_0176())" not in s:
            s = s.replace(old_write, new_write, 1)

        old_add = '''        if (!out.empty()) {
            outputDir = out;
        }
        calls += 1u;
'''
        new_add = '''        if (!internal_profiles_enabled_0176()) {
            return;
        }
        if (!out.empty()) {
            outputDir = out;
        }
        calls += 1u;
'''
        if old_add in s and "if (!internal_profiles_enabled_0176()) {\n            return;\n        }\n        if (!out.empty())" not in s:
            s = s.replace(old_add, new_add, 1)

    return write_if_changed(p, s)


def main() -> int:
    changed = []
    for name, fn in [("main_src_mpcd_base.cpp", patch_main),
                     ("weighted_resampling.cpp", patch_weighted),
                     ("src_mpcd_base.cpp", patch_src_mpcd_base)]:
        try:
            if fn():
                changed.append(name)
        except SystemExit as e:
            print(f"[0176] ERROR in {name}: {e}", file=sys.stderr)
            return 2
    if changed:
        print("[0176] updated: " + ", ".join(changed))
    else:
        print("[0176] no changes needed; files already look patched")
    print("[0176] internal profile CSVs are disabled by default; set MPCD_INTERNAL_PROFILES=1 to enable them.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

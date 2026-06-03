#!/usr/bin/env python3
"""Final repository hygiene audit for the OpenMP-light branch.

This script is intentionally read-only.  It inspects tracked files and writes
CSV summaries that help decide whether the light branch is ready to be kept as a
portable OpenMP production branch.
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
from pathlib import Path
from typing import Iterable

PROFILE_PATTERNS = [
    "phase_profile",
    "q6_cg_profile",
    "deposit_profile",
    "resampling_guard_profile",
    "post_guard_profile",
    "post_guard_equivalence",
    "post_guard_equivalence_trace",
    "MPCD_INTERNAL_PROFILES",
]

MAIN_ALLOWED_PROFILE_REFS = {
    "src/main_src_mpcd_base.cpp",
    "src/src_mpcd_base.cpp",
    "src/weighted_resampling.cpp",
    "src/q6_projection_adapter.cpp",
    "src/elliptic_projection.cpp",
    "include/weighted_resampling.h",
}

ROOT_ARTIFACT_RE = re.compile(
    r"^(validation_compare.*\.csv\+?|snapshot_.*\.zip|perf_summary_.*\.csv|phase_profile_.*\.csv|"
    r"q6_cg_profile_.*\.csv|deposit_profile_.*\.csv|resampling_guard_profile_.*\.csv|"
    r"post_guard_.*\.csv)$"
)

DEV_SCRIPT_RE = re.compile(
    r"^scripts/(run_performance_profile_.*\.sh|apply_openmp_light_diagnostics_0176\.py|"
    r"audit_openmp_light_cleanup_0178\.py|apply_openmp_light_cleanup_0179\.py|"
    r"audit_openmp_light_remaining_0180\.py|apply_openmp_light_archive_0181\.py)$"
)

CORE_SCRIPT_RE = re.compile(
    r"^scripts/(build.*|run_validation_mono_config_0162\.sh|compare_validation_mono_config_0162\.py|"
    r"generate_validation_state_0162\.py|run_openmp_light_smoke_0176\.sh)$"
)

CODE_EXTS = {".cpp", ".h", ".hpp", ".cc", ".cxx"}
TEXT_EXTS = CODE_EXTS | {".py", ".sh", ".md", ".txt", ".kv", ".csv"}


def git_files(root: Path) -> list[str]:
    out = subprocess.check_output(["git", "-C", str(root), "ls-files"], text=True)
    return [line.strip() for line in out.splitlines() if line.strip()]


def file_category(rel: str) -> str:
    p = Path(rel)
    if rel.startswith("dev_history/"):
        return "dev_history"
    if ROOT_ARTIFACT_RE.match(rel):
        return "root_artifact_should_not_be_tracked"
    if DEV_SCRIPT_RE.match(rel):
        return "dev_script_still_in_scripts"
    if CORE_SCRIPT_RE.match(rel):
        return "keep_core_script"
    if rel.startswith("scripts/"):
        return "review_script"
    if rel.startswith("doc/") or rel.startswith("docs/"):
        # Patch-era docs should have been archived; user docs can remain.
        name = p.name.lower()
        if name.startswith("readme_0") or "next_chat_prompt" in name:
            return "doc_history_candidate"
        return "review_doc"
    if rel.startswith("include/") or rel.startswith("src/"):
        return "keep_code"
    if rel.startswith("examples/") or rel.startswith("cases/"):
        return "review_case_or_example"
    if rel.startswith("runs/") or rel.startswith("build/"):
        return "tracked_generated_dir_warning"
    return "review_other"


def scan_profile_refs(root: Path, rels: Iterable[str]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for rel in rels:
        p = root / rel
        if p.suffix.lower() not in TEXT_EXTS or not p.is_file():
            continue
        try:
            text = p.read_text(errors="ignore")
        except Exception:
            continue
        hits = [pat for pat in PROFILE_PATTERNS if pat in text]
        if not hits:
            continue
        status = "allowed_guarded" if rel in MAIN_ALLOWED_PROFILE_REFS or rel.startswith("dev_history/") else "review_profile_reference"
        rows.append({
            "path": rel,
            "status": status,
            "patterns": ";".join(hits),
        })
    return rows


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for row in rows:
            w.writerow(row)


def main() -> int:
    ap = argparse.ArgumentParser(description="Final OpenMP-light repository audit (read-only).")
    ap.add_argument("--root", default=".", help="repository root")
    ap.add_argument("--out", default="cleanup_audit_0182", help="output directory")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    outdir = root / args.out
    rels = git_files(root)

    inventory = []
    summary: dict[str, int] = {}
    for rel in rels:
        cat = file_category(rel)
        summary[cat] = summary.get(cat, 0) + 1
        inventory.append({"path": rel, "category": cat})

    summary_rows = [{"category": k, "count": v} for k, v in sorted(summary.items())]
    profile_rows = scan_profile_refs(root, rels)

    recommendations = []
    def add(level: str, item: str, recommendation: str) -> None:
        recommendations.append({"level": level, "item": item, "recommendation": recommendation})

    root_artifacts = [r["path"] for r in inventory if r["category"] == "root_artifact_should_not_be_tracked"]
    if root_artifacts:
        add("action", "root artifacts", f"Remove or move {len(root_artifacts)} tracked root CSV/snapshot artifacts.")
    else:
        add("ok", "root artifacts", "No tracked root validation/profile artifacts detected.")

    dev_scripts = [r["path"] for r in inventory if r["category"] == "dev_script_still_in_scripts"]
    if dev_scripts:
        add("action", "dev scripts", f"Move {len(dev_scripts)} remaining dev/profile scripts to dev_history/scripts/.")
    else:
        add("ok", "dev scripts", "No performance/dev-only script remains in scripts/.")

    unapproved_profile = [r for r in profile_rows if r["status"] == "review_profile_reference"]
    if unapproved_profile:
        add("review", "profile references", f"Review {len(unapproved_profile)} profile references outside allowed code/dev_history files.")
    else:
        add("ok", "profile references", "Profile references are limited to guarded code or dev_history files.")

    tracked_generated = [r["path"] for r in inventory if r["category"] == "tracked_generated_dir_warning"]
    if tracked_generated:
        add("action", "tracked generated dirs", f"Investigate {len(tracked_generated)} tracked files under runs/ or build/.")
    else:
        add("ok", "tracked generated dirs", "No tracked files under runs/ or build/.")

    write_csv(outdir / "openmp_light_final_inventory_0182.csv", inventory, ["path", "category"])
    write_csv(outdir / "openmp_light_final_summary_0182.csv", summary_rows, ["category", "count"])
    write_csv(outdir / "openmp_light_final_profile_refs_0182.csv", profile_rows, ["path", "status", "patterns"])
    write_csv(outdir / "openmp_light_final_recommendations_0182.csv", recommendations, ["level", "item", "recommendation"])

    print(f"Wrote {outdir / 'openmp_light_final_inventory_0182.csv'}")
    print(f"Wrote {outdir / 'openmp_light_final_summary_0182.csv'}")
    print(f"Wrote {outdir / 'openmp_light_final_profile_refs_0182.csv'}")
    print(f"Wrote {outdir / 'openmp_light_final_recommendations_0182.csv'}")
    bad = [r for r in recommendations if r["level"] in {"action", "review"}]
    if bad:
        print("Final audit: REVIEW/ACTION items remain")
    else:
        print("Final audit: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

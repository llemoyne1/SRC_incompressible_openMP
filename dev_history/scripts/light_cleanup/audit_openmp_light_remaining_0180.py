#!/usr/bin/env python3
"""
Audit remaining files in the OpenMP-light branch after the 0179 dev-history move.

This script is read-only: it does not remove, move, or edit project files.
It creates CSV inventories to help decide what should remain in the production/light branch.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Tuple


DEV_PATTERNS = [
    re.compile(r"(^|/)(run_performance_profile_|audit_openmp_light_|apply_openmp_light_)", re.I),
    re.compile(r"(^|/)(README_0\d+|NEXT_CHAT_PROMPT|.*_PATCH|.*PROFILE.*|.*PROFILING.*)", re.I),
    re.compile(r"(017\d|016\d|015\d|014\d)", re.I),
    re.compile(r"(post_guard_equivalence|resampling_guard_profile|deposit_profile|q6_cg_profile|phase_profile)", re.I),
]

KEEP_SCRIPT_PATTERNS = [
    re.compile(r"(^|/)build_", re.I),
    re.compile(r"(^|/)run_validation_", re.I),
    re.compile(r"(^|/)compare_validation_", re.I),
    re.compile(r"(^|/)generate_validation_state_", re.I),
    re.compile(r"(^|/)run_openmp_light_smoke_", re.I),
]

KEEP_DOC_NAMES = {"README.md", "LICENSE", "COPYING", "CHANGELOG.md"}

CASE_SPECIFIC_PATTERNS = [
    re.compile(r"poiseuille", re.I),
    re.compile(r"taylor|tg_", re.I),
    re.compile(r"piston", re.I),
    re.compile(r"backward|backstep|step", re.I),
    re.compile(r"obstacle|cylinder|karman|wake|airfoil", re.I),
]

ROOT_ARTEFACT_PATTERNS = [
    re.compile(r"^validation_compare.*\.csv\+?$", re.I),
    re.compile(r"^snapshot_.*\.(zip|tar\.gz|tgz)$", re.I),
    re.compile(r"^perf_summary_.*\.csv$", re.I),
    re.compile(r"^phase_profile_.*\.csv$", re.I),
    re.compile(r"^q6_cg_profile_.*\.csv$", re.I),
    re.compile(r"^deposit_profile_.*\.csv$", re.I),
    re.compile(r"^resampling_guard_profile_.*\.csv$", re.I),
]

SOURCE_EXT = {".cpp", ".cc", ".c", ".h", ".hpp", ".cu", ".cuh"}
DOC_EXT = {".md", ".txt", ".rst", ".tex", ".pdf", ".odt", ".docx"}
SCRIPT_EXT = {".sh", ".py", ".m"}
DATA_EXT = {".csv", ".json", ".yaml", ".yml", ".kv", ".smpcd"}


@dataclass
class FileRecord:
    path: str
    tracked: bool
    size: int
    kind: str
    classification: str
    rationale: str
    suggested_action: str


def run_git(root: Path, args: List[str]) -> List[str]:
    try:
        out = subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL)
        return [line for line in out.splitlines() if line]
    except Exception:
        return []


def rel_files(root: Path, include_untracked: bool) -> List[Tuple[str, bool]]:
    tracked = set(run_git(root, ["ls-files"]))
    items = [(p, True) for p in sorted(tracked)]
    if include_untracked:
        untracked = set(run_git(root, ["ls-files", "--others", "--exclude-standard"]))
        for p in sorted(untracked - tracked):
            # Exclude common output/build folders from the audit by default.
            if p.startswith(("runs/", "build/", ".git/")):
                continue
            items.append((p, False))
    return items


def kind_for(path: str) -> str:
    p = Path(path)
    if path.startswith("src/") or path.startswith("include/"):
        return "source"
    if path.startswith("scripts/") or path.startswith("dev_history/scripts/"):
        return "script"
    if path.startswith("doc/") or path.startswith("dev_history/doc/"):
        return "doc"
    if path.startswith("dev_history/"):
        return "dev_history"
    if p.suffix.lower() in SOURCE_EXT:
        return "source"
    if p.suffix.lower() in SCRIPT_EXT:
        return "script"
    if p.suffix.lower() in DOC_EXT:
        return "doc"
    if p.suffix.lower() in DATA_EXT:
        return "data"
    return "other"


def any_match(patterns: Iterable[re.Pattern], text: str) -> bool:
    return any(p.search(text) for p in patterns)


def classify(path: str, tracked: bool) -> Tuple[str, str, str]:
    name = Path(path).name
    lower = path.lower()

    if path.startswith("dev_history/"):
        return ("already_archived", "already under dev_history", "keep archived")

    if path.startswith("runs/") or path.startswith("build/"):
        return ("ignore_runtime_output", "runtime/build output", "do not track")

    if any(p.search(name) for p in ROOT_ARTEFACT_PATTERNS) and "/" not in path:
        return ("root_artifact", "root-level run/validation artifact", "remove from light branch or archive")

    if path.startswith("scripts/"):
        if any_match(KEEP_SCRIPT_PATTERNS, name):
            return ("keep_script", "generic build/validation/light-smoke script", "keep")
        if any_match(DEV_PATTERNS, name):
            return ("candidate_archive_script", "profiling/dev-history script", "move to dev_history/scripts")
        if any_match(CASE_SPECIFIC_PATTERNS, name):
            return ("review_case_script", "case-specific script", "review: keep as example or move to dev_history/scripts/cases")
        return ("review_script", "script not automatically classified", "manual review")

    if path.startswith("doc/"):
        if name in KEEP_DOC_NAMES or name.lower() == "readme.md":
            return ("keep_doc", "top-level user-facing doc", "keep")
        if any_match(DEV_PATTERNS, name):
            return ("candidate_archive_doc", "patch/dev-history documentation", "move to dev_history/doc")
        if any_match(CASE_SPECIFIC_PATTERNS, name):
            return ("review_case_doc", "case-specific documentation", "review: keep, shorten, or move")
        return ("review_doc", "documentation not automatically classified", "manual review")

    if path.startswith("src/") or path.startswith("include/"):
        if any_match([re.compile(r"profile|profiling|post_guard_equivalence|deposit_profile|q6_cg_profile", re.I)], path):
            return ("source_profile_refs", "source path/name suggests profiling", "review but do not remove blindly")
        return ("keep_source", "core source/header", "keep")

    if any_match(CASE_SPECIFIC_PATTERNS, lower):
        return ("review_case_file", "case-specific file outside scripts/doc", "manual review")

    if any_match(DEV_PATTERNS, lower):
        return ("candidate_archive_other", "dev/profiling/history pattern", "move/archive or remove")

    if not tracked:
        return ("untracked_review", "untracked file not ignored", "review before adding")

    return ("review", "not automatically classified", "manual review")


def maybe_scan_profile_refs(root: Path, paths: Iterable[str]) -> List[dict]:
    patterns = [
        "MPCD_INTERNAL_PROFILES",
        "phase_profile_",
        "q6_cg_profile_",
        "deposit_profile_",
        "resampling_guard_profile_",
        "post_guard_profile_",
        "post_guard_equivalence",
        "ProfileAccumulator",
        "ScopedStepProfileTimer",
    ]
    rows = []
    for rel in paths:
        p = root / rel
        if not p.is_file() or p.suffix.lower() not in SOURCE_EXT | SCRIPT_EXT | {".md"}:
            continue
        try:
            text = p.read_text(errors="ignore")
        except Exception:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            for pat in patterns:
                if pat in line:
                    rows.append({"path": rel, "line": lineno, "pattern": pat, "text": line.strip()[:240]})
                    break
    return rows


def write_csv(path: Path, fieldnames: List[str], rows: List[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for row in rows:
            w.writerow(row)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="Repository root")
    ap.add_argument("--out", default="cleanup_audit_0180", help="Output directory")
    ap.add_argument("--include-untracked", action="store_true", help="Also audit untracked non-build/non-run files")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    outdir = root / args.out
    files = rel_files(root, args.include_untracked)

    records: List[FileRecord] = []
    for rel, tracked in files:
        p = root / rel
        try:
            size = p.stat().st_size if p.exists() else 0
        except Exception:
            size = 0
        classification, rationale, action = classify(rel, tracked)
        records.append(FileRecord(rel, tracked, size, kind_for(rel), classification, rationale, action))

    inv_rows = [r.__dict__ for r in records]
    write_csv(outdir / "openmp_light_remaining_inventory_0180.csv",
              ["path", "tracked", "size", "kind", "classification", "rationale", "suggested_action"],
              inv_rows)

    summary = {}
    for r in records:
        key = (r.kind, r.classification, r.suggested_action)
        summary[key] = summary.get(key, 0) + 1
    summary_rows = [
        {"kind": k[0], "classification": k[1], "suggested_action": k[2], "count": v}
        for k, v in sorted(summary.items())
    ]
    write_csv(outdir / "openmp_light_remaining_summary_0180.csv",
              ["kind", "classification", "suggested_action", "count"],
              summary_rows)

    profile_rows = maybe_scan_profile_refs(root, [r.path for r in records])
    write_csv(outdir / "openmp_light_remaining_profile_refs_0180.csv",
              ["path", "line", "pattern", "text"],
              profile_rows)

    recommendations = []
    for cls in [
        "root_artifact", "candidate_archive_script", "candidate_archive_doc",
        "candidate_archive_other", "review_case_script", "review_case_doc",
        "review_script", "review_doc", "review_case_file", "review"
    ]:
        count = sum(1 for r in records if r.classification == cls)
        if count:
            recommendations.append({"classification": cls, "count": count,
                                    "next_step": next_step_for(cls)})
    write_csv(outdir / "openmp_light_remaining_recommendations_0180.csv",
              ["classification", "count", "next_step"], recommendations)

    print(f"[0180-audit] wrote {outdir}")
    print(f"[0180-audit] files audited: {len(records)}")
    for row in summary_rows:
        if row["classification"] in {"root_artifact", "candidate_archive_script", "candidate_archive_doc", "review_script", "review_doc", "review_case_script", "review_case_doc", "review"}:
            print(f"[0180-audit] {row['kind']}/{row['classification']}: {row['count']}")
    return 0


def next_step_for(cls: str) -> str:
    if cls == "root_artifact":
        return "remove from Git or archive under dev_history/validation_comparisons if still useful"
    if cls == "candidate_archive_script":
        return "move to dev_history/scripts unless still used by light workflow"
    if cls == "candidate_archive_doc":
        return "move to dev_history/doc unless user-facing"
    if cls == "candidate_archive_other":
        return "move/archive or remove after manual check"
    if cls in {"review_case_script", "review_case_doc", "review_case_file"}:
        return "decide whether this is a production example; otherwise move to dev_history/cases"
    if cls in {"review_script", "review_doc", "review"}:
        return "manual review before any cleanup"
    return "keep"


if __name__ == "__main__":
    raise SystemExit(main())

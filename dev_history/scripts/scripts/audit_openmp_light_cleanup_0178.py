#!/usr/bin/env python3
"""Audit OpenMP-light repository cleanup candidates without modifying files.

Produces CSV inventories for scripts/doc/code/profile artifacts to support a
careful cleanup pass. This script is intentionally read-only.
"""
from __future__ import annotations

import argparse
import csv
import os
import re
from pathlib import Path
from typing import Iterable

PROFILE_PATTERNS = [
    r"phase_profile", r"q6_cg_profile", r"deposit_profile",
    r"resampling_guard_profile", r"post_guard_profile",
    r"post_guard_equivalence", r"post_guard_equivalence_trace",
]
PATCH_HISTORY_PATTERNS = [
    r"README_0\d+", r"_0\d+", r"performance_profile", r"profile_0\d+",
    r"validation_mono_config_0162", r"compare_validation_mono_config_0162",
]
KEEP_SCRIPT_PATTERNS = [
    r"build", r"validation", r"run_openmp_light_smoke_0176", r"generate_validation_state_0162",
]
KEEP_DOC_PATTERNS = [
    r"README\.md$", r"README_0176", r"README_0177", r"OPENMP_LIGHT",
]
SOURCE_EXTS = {".cpp", ".h", ".hpp", ".c", ".cc"}
TEXT_EXTS = SOURCE_EXTS | {".sh", ".py", ".md", ".txt", ".cmake", ".kv"}


def rel(path: Path, root: Path) -> str:
    return str(path.relative_to(root)).replace(os.sep, "/")


def match_any(text: str, patterns: Iterable[str]) -> bool:
    return any(re.search(p, text, re.IGNORECASE) for p in patterns)


def read_text_safe(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except Exception:
        return ""


def classify_file(path: Path, root: Path) -> tuple[str, str]:
    r = rel(path, root)
    name = path.name
    text = ""
    if path.suffix in TEXT_EXTS and path.stat().st_size < 2_000_000:
        text = read_text_safe(path)

    has_profile = match_any(r, PROFILE_PATTERNS) or match_any(text, PROFILE_PATTERNS)
    has_patch_history = match_any(r, PATCH_HISTORY_PATTERNS)

    if r.startswith("runs/") or r.startswith("build/") or r.startswith(".git/"):
        return "ignore_generated", "generated/build/git directory"

    if r.startswith("scripts/"):
        if match_any(name, KEEP_SCRIPT_PATTERNS):
            return "keep", "core build/validation/light smoke script"
        if has_profile or has_patch_history:
            return "candidate_move_dev", "development profiling or patch-era script"
        return "review", "script requires manual classification"

    if r.startswith("doc/"):
        if match_any(name, KEEP_DOC_PATTERNS):
            return "keep", "current light-mode documentation or main README"
        if has_patch_history or has_profile:
            return "candidate_move_dev_history", "patch-era/profile documentation"
        return "review", "documentation requires manual classification"

    if r.startswith("src/") or r.startswith("include/"):
        if has_profile:
            return "code_profile_refs", "source contains internal profile references; should remain guarded or be compiled out"
        return "keep", "source file without detected internal profile references"

    if has_profile or has_patch_history:
        return "candidate_remove_or_move", "top-level patch/profile artifact"
    return "review", "unclassified repository file"


def write_inventory(root: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    for path in sorted(root.rglob("*")):
        if path.is_dir():
            continue
        if "/.git/" in str(path) or "/runs/" in str(path) or "/build/" in str(path):
            # include only explicit top-level generated dirs as ignored summary if needed; skip noise
            continue
        try:
            size = path.stat().st_size
        except OSError:
            size = 0
        action, reason = classify_file(path, root)
        rows.append({
            "path": rel(path, root),
            "size_bytes": size,
            "action": action,
            "reason": reason,
        })

    with (out_dir / "openmp_light_cleanup_inventory_0178.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["path", "size_bytes", "action", "reason"])
        writer.writeheader()
        writer.writerows(rows)

    # Summary counts by action
    counts = {}
    for row in rows:
        counts[row["action"]] = counts.get(row["action"], 0) + 1
    with (out_dir / "openmp_light_cleanup_summary_0178.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["action", "count"])
        writer.writeheader()
        for action, count in sorted(counts.items()):
            writer.writerow({"action": action, "count": count})

    # Grep-like profile references in code/scripts/docs for targeted review
    ref_rows = []
    for path in sorted(root.rglob("*")):
        if path.is_dir() or path.suffix not in TEXT_EXTS:
            continue
        if any(part in {".git", "runs", "build"} for part in path.parts):
            continue
        text = read_text_safe(path)
        for lineno, line in enumerate(text.splitlines(), start=1):
            if match_any(line, PROFILE_PATTERNS):
                ref_rows.append({"path": rel(path, root), "line": lineno, "text": line.strip()[:300]})
    with (out_dir / "openmp_light_profile_references_0178.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["path", "line", "text"])
        writer.writeheader()
        writer.writerows(ref_rows)


def main() -> int:
    ap = argparse.ArgumentParser(description="Audit OpenMP-light cleanup candidates without modifying repository files.")
    ap.add_argument("--root", default=".", help="Repository root, default current directory")
    ap.add_argument("--out", default="cleanup_audit_0178", help="Output directory for audit CSVs")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    out_dir = Path(args.out)
    if not (root / ".git").exists():
        # Worktrees have .git as a file, so this also works.
        if not (root / ".git").is_file():
            print(f"[0178-audit] warning: {root} does not look like a git root")
    write_inventory(root, out_dir)
    print(f"[0178-audit] wrote {out_dir}/openmp_light_cleanup_inventory_0178.csv")
    print(f"[0178-audit] wrote {out_dir}/openmp_light_cleanup_summary_0178.csv")
    print(f"[0178-audit] wrote {out_dir}/openmp_light_profile_references_0178.csv")
    print("[0178-audit] read-only audit complete; no repository files modified")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

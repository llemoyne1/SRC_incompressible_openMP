#!/usr/bin/env python3
"""
0179 OpenMP-light cleanup helper.

This script performs a conservative repository cleanup for the clean/openmp-light branch.
Default mode is dry-run. Use --apply to actually move files.

It only touches categories that were explicitly verified as tracked in the conversation:
  - root validation_compare*.csv files
  - scripts/run_performance_profile_*.sh
  - scripts/apply_openmp_light_diagnostics_0176.py

Optionally, with --move-doc-history, it also moves patch-era docs matching
  doc/README_[0-9]*.md and doc/NEXT_CHAT_PROMPT*.md
into dev_history/doc/patch_history/.

It does not touch source files, include files, validation scripts, build scripts,
or any files under runs/.
"""
from __future__ import annotations

import argparse
import csv
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List


@dataclass
class MoveItem:
    src: Path
    dst: Path
    category: str
    reason: str


def repo_root() -> Path:
    try:
        out = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
        return Path(out)
    except Exception:
        return Path.cwd()


def git_tracked(root: Path, rel: Path) -> bool:
    try:
        subprocess.check_call(
            ["git", "ls-files", "--error-unmatch", rel.as_posix()],
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def safe_git_mv(root: Path, src: Path, dst: Path, apply: bool) -> str:
    rel_src = src.relative_to(root)
    rel_dst = dst.relative_to(root)
    if not src.exists():
        return "missing"
    if dst.exists():
        return "destination_exists"
    if not apply:
        return "dry_run"
    dst.parent.mkdir(parents=True, exist_ok=True)
    if git_tracked(root, rel_src):
        subprocess.check_call(["git", "mv", rel_src.as_posix(), rel_dst.as_posix()], cwd=root)
        return "git_mv"
    shutil.move(str(src), str(dst))
    return "move"


def collect_items(root: Path, move_doc_history: bool) -> List[MoveItem]:
    items: List[MoveItem] = []

    # Root validation comparison CSVs: these are development/run artifacts and
    # should not live at repository root in the light branch.
    for p in sorted(root.glob("validation_compare*.csv*")):
        if p.is_file():
            items.append(MoveItem(
                src=p,
                dst=root / "dev_history" / "validation_comparisons" / p.name,
                category="root_validation_comparison_csv",
                reason="tracked validation comparison artifact should not stay at repository root",
            ))

    # Performance profile scripts from the optimization campaign.
    for p in sorted((root / "scripts").glob("run_performance_profile_*.sh")):
        if p.is_file():
            items.append(MoveItem(
                src=p,
                dst=root / "dev_history" / "scripts" / "performance_profiles" / p.name,
                category="performance_profile_script",
                reason="development/profiling script retained in dev_history, not production scripts/",
            ))

    # One-shot script used only to patch the light diagnostics mode.
    p = root / "scripts" / "apply_openmp_light_diagnostics_0176.py"
    if p.is_file():
        items.append(MoveItem(
            src=p,
            dst=root / "dev_history" / "scripts" / "light_diagnostics" / p.name,
            category="one_shot_light_patch_script",
            reason="one-shot transformation script retained in dev_history",
        ))

    if move_doc_history:
        doc = root / "doc"
        if doc.exists():
            for p in sorted(doc.glob("README_[0-9]*.md")):
                if p.is_file():
                    items.append(MoveItem(
                        src=p,
                        dst=root / "dev_history" / "doc" / "patch_history" / p.name,
                        category="patch_history_doc",
                        reason="patch-era README archived away from production doc/",
                    ))
            for p in sorted(doc.glob("NEXT_CHAT_PROMPT*.md")):
                if p.is_file():
                    items.append(MoveItem(
                        src=p,
                        dst=root / "dev_history" / "doc" / "patch_history" / p.name,
                        category="next_chat_prompt_doc",
                        reason="development handoff prompt archived away from production doc/",
                    ))

    # Avoid duplicate src paths if glob patterns overlap.
    seen = set()
    unique: List[MoveItem] = []
    for item in items:
        key = item.src.resolve()
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique


def write_manifest(root: Path, items: Iterable[MoveItem], statuses: List[str], apply: bool) -> Path:
    out_dir = root / "cleanup_audit_0179"
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = out_dir / "openmp_light_cleanup_manifest_0179.csv"
    with manifest.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["apply", "status", "category", "src", "dst", "reason"])
        for item, status in zip(items, statuses):
            w.writerow([
                int(apply),
                status,
                item.category,
                item.src.relative_to(root).as_posix(),
                item.dst.relative_to(root).as_posix(),
                item.reason,
            ])
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description="Conservative cleanup for OpenMP-light branch.")
    ap.add_argument("--root", default=".", help="repository root; default=current directory")
    ap.add_argument("--apply", action="store_true", help="actually move files; default is dry-run")
    ap.add_argument("--move-doc-history", action="store_true", help="also archive doc/README_[0-9]*.md and NEXT_CHAT_PROMPT*.md")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not (root / ".git").exists():
        # If this is a worktree, .git may be a file. Accept that.
        if not (root / ".git").is_file():
            root = repo_root().resolve()

    items = collect_items(root, args.move_doc_history)
    statuses: List[str] = []
    for item in items:
        status = safe_git_mv(root, item.src, item.dst, args.apply)
        statuses.append(status)
        verb = "MOVE" if args.apply else "WOULD_MOVE"
        print(f"[{verb}] {item.src.relative_to(root)} -> {item.dst.relative_to(root)}  ({item.category}; {status})")

    manifest = write_manifest(root, items, statuses, args.apply)
    print(f"[0179-cleanup] items: {len(items)}")
    print(f"[0179-cleanup] manifest: {manifest.relative_to(root)}")
    if not args.apply:
        print("[0179-cleanup] dry-run only. Re-run with --apply to move files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

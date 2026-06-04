#!/usr/bin/env python3
"""
0181 OpenMP-light safe archive staging.

Reads the 0180 remaining-cleanup inventory and moves only safe archive candidates
into dev_history/, preserving their relative path to avoid name collisions.

Default mode is dry-run. Use --apply to actually move files.
"""
from __future__ import annotations

import argparse
import csv
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

SAFE_CLASSES_DEFAULT = {
    "candidate_archive_doc",
    "candidate_archive_script",
    "candidate_archive_other",
}

DEST_BY_CLASS = {
    "candidate_archive_doc": Path("dev_history/doc"),
    "candidate_archive_script": Path("dev_history/scripts"),
    "candidate_archive_other": Path("dev_history/artifacts"),
}

EXCLUDE_PREFIXES = (
    ".git/",
    "build/",
    "runs/",
    "dev_history/",
)

@dataclass
class InventoryRow:
    path: str
    tracked: bool
    size: int | None
    kind: str
    classification: str
    rationale: str
    suggested_action: str


def run_git(root: Path, args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def is_tracked(root: Path, rel: str) -> bool:
    cp = run_git(root, ["ls-files", "--error-unmatch", rel], check=False)
    return cp.returncode == 0


def git_available(root: Path) -> bool:
    return (root / ".git").exists() or run_git(root, ["rev-parse", "--is-inside-work-tree"], check=False).returncode == 0


def load_inventory(path: Path) -> list[InventoryRow]:
    rows: list[InventoryRow] = []
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        required = {"path", "tracked", "kind", "classification", "rationale", "suggested_action"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"Inventory {path} is missing columns: {sorted(missing)}")
        for r in reader:
            size = None
            try:
                size = int(r.get("size", ""))
            except ValueError:
                pass
            rows.append(
                InventoryRow(
                    path=r["path"],
                    tracked=str(r.get("tracked", "")).lower() == "true",
                    size=size,
                    kind=r.get("kind", ""),
                    classification=r["classification"],
                    rationale=r.get("rationale", ""),
                    suggested_action=r.get("suggested_action", ""),
                )
            )
    return rows


def safe_relpath(rel: str) -> str:
    p = Path(rel)
    if p.is_absolute() or ".." in p.parts:
        raise ValueError(f"Unsafe path in inventory: {rel}")
    return rel.replace("\\", "/")


def default_inventory(root: Path) -> Path:
    candidates = [
        root / "cleanup_audit_0180" / "openmp_light_remaining_inventory_0180.csv",
        root / "openmp_light_remaining_inventory_0180.csv",
    ]
    for p in candidates:
        if p.exists():
            return p
    raise SystemExit(
        "Could not find 0180 inventory. Expected cleanup_audit_0180/"
        "openmp_light_remaining_inventory_0180.csv. Pass --inventory explicitly."
    )


def should_skip(rel: str) -> bool:
    rel_norm = rel.replace("\\", "/")
    return rel_norm.startswith(EXCLUDE_PREFIXES)


def destination_for(row: InventoryRow) -> Path:
    base = DEST_BY_CLASS[row.classification]
    return base / row.path


def ensure_unique_dest(root: Path, dest_rel: Path) -> Path:
    """Return dest_rel, or add a numeric suffix if needed to avoid overwrite."""
    dest = root / dest_rel
    if not dest.exists():
        return dest_rel
    parent = dest_rel.parent
    stem = dest_rel.stem
    suffix = dest_rel.suffix
    for i in range(1, 1000):
        candidate = parent / f"{stem}__{i:03d}{suffix}"
        if not (root / candidate).exists():
            return candidate
    raise RuntimeError(f"Could not find unique destination for {dest_rel}")


def move_file(root: Path, src_rel: str, dst_rel: Path, apply: bool, use_git: bool) -> tuple[str, str]:
    src = root / src_rel
    dst = root / dst_rel
    if not src.exists():
        return "missing", "source file does not exist"
    if not apply:
        return "dry_run", "would move"
    dst.parent.mkdir(parents=True, exist_ok=True)
    if use_git and is_tracked(root, src_rel):
        cp = run_git(root, ["mv", src_rel, str(dst_rel)], check=False)
        if cp.returncode == 0:
            return "moved_git", "git mv"
        # Fallback: git mv can fail for unusual tracked paths. Do not silently ignore.
        return "error", cp.stderr.strip() or cp.stdout.strip() or "git mv failed"
    shutil.move(str(src), str(dst))
    return "moved", "filesystem move"


def write_manifest(path: Path, rows: Iterable[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "action",
        "status",
        "source",
        "destination",
        "classification",
        "kind",
        "tracked_inventory",
        "rationale",
        "note",
    ]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Stage safe OpenMP-light cleanup moves from 0180 audit.")
    p.add_argument("--root", default=".", help="repository root")
    p.add_argument("--inventory", default=None, help="0180 inventory CSV")
    p.add_argument("--out", default="cleanup_audit_0181/openmp_light_archive_manifest_0181.csv")
    p.add_argument("--apply", action="store_true", help="perform moves; otherwise dry-run")
    p.add_argument("--include-untracked", action="store_true", help="also move untracked candidates from inventory")
    p.add_argument("--no-git", action="store_true", help="use filesystem moves instead of git mv")
    p.add_argument(
        "--classes",
        default=",".join(sorted(SAFE_CLASSES_DEFAULT)),
        help="comma-separated classifications to process",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    inventory = Path(args.inventory).resolve() if args.inventory else default_inventory(root)
    classes = {c.strip() for c in args.classes.split(",") if c.strip()}
    bad = classes.difference(DEST_BY_CLASS)
    if bad:
        raise SystemExit(f"Unsupported classifications for automatic archive: {sorted(bad)}")

    use_git = (not args.no_git) and git_available(root)
    rows = load_inventory(inventory)
    manifest: list[dict[str, str]] = []
    processed = 0
    skipped = 0

    for row in rows:
        if row.classification not in classes:
            continue
        rel = safe_relpath(row.path)
        if should_skip(rel):
            skipped += 1
            manifest.append({
                "action": "skip",
                "status": "skipped",
                "source": rel,
                "destination": "",
                "classification": row.classification,
                "kind": row.kind,
                "tracked_inventory": str(row.tracked),
                "rationale": row.rationale,
                "note": "excluded prefix or already archived",
            })
            continue
        if (not row.tracked) and (not args.include_untracked):
            skipped += 1
            manifest.append({
                "action": "skip",
                "status": "skipped",
                "source": rel,
                "destination": "",
                "classification": row.classification,
                "kind": row.kind,
                "tracked_inventory": str(row.tracked),
                "rationale": row.rationale,
                "note": "untracked not included",
            })
            continue
        dst_rel = ensure_unique_dest(root, destination_for(row))
        status, note = move_file(root, rel, dst_rel, args.apply, use_git)
        processed += 1 if status in {"dry_run", "moved_git", "moved"} else 0
        manifest.append({
            "action": "move",
            "status": status,
            "source": rel,
            "destination": str(dst_rel).replace("\\", "/"),
            "classification": row.classification,
            "kind": row.kind,
            "tracked_inventory": str(row.tracked),
            "rationale": row.rationale,
            "note": note,
        })

    out = root / args.out
    write_manifest(out, manifest)
    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"[0181] mode      : {mode}")
    print(f"[0181] root      : {root}")
    print(f"[0181] inventory : {inventory}")
    print(f"[0181] manifest  : {out}")
    print(f"[0181] processed : {processed}")
    print(f"[0181] skipped   : {skipped}")
    if not args.apply:
        print("[0181] dry-run only. Re-run with --apply to move files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

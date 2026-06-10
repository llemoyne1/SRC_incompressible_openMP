#!/usr/bin/env python3
"""Summarize inactive-slot scaling runs produced by run_active_prefix_scaling_0315i.sh."""
from __future__ import annotations

import csv
import math
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


def _parse_time_number_0315i(value: str) -> float:
    """Parse GNU time values robustly under non-C locales and m:ss formats."""
    value = (value or "").strip().replace(",", ".")
    if not value:
        return math.nan
    if ":" in value:
        try:
            total = 0.0
            for part in value.split(":"):
                total = total * 60.0 + float(part)
            return total
        except Exception:
            return math.nan
    try:
        return float(value)
    except Exception:
        return math.nan


def _read_text_if_exists_0315i(path: Path) -> str:
    try:
        if path.exists() and path.stat().st_size > 0:
            return path.read_text(errors="replace")
    except Exception:
        pass
    return ""


def _parse_time_text_0315i(text: str) -> Tuple[float, float, float]:
    """Parse several time-output formats from arbitrary stdout/stderr text."""
    if not text:
        return math.nan, math.nan, math.nan

    # Preferred wrapper format, produced by src_gpu_demo_common_0283.sh:
    # elapsed=1.234 user=0.120 sys=0.040
    m = re.search(
        r"elapsed\s*=\s*([0-9.,:+\-eE]+)\s+user\s*=\s*([0-9.,:+\-eE]+)\s+sys\s*=\s*([0-9.,:+\-eE]+)",
        text,
    )
    if m:
        return tuple(_parse_time_number_0315i(x) for x in m.groups())  # type: ignore[return-value]

    # GNU /usr/bin/time default/POSIX-ish forms: real/user/sys can appear on
    # separate lines, with either dots or commas and optionally m:ss.xx.
    vals: Dict[str, float] = {}
    for key, raw in re.findall(r"(?m)^\s*(real|user|sys)\s+([0-9.,:]+)", text):
        vals[key] = _parse_time_number_0315i(raw)
    if vals:
        return vals.get("real", math.nan), vals.get("user", math.nan), vals.get("sys", math.nan)

    # GNU verbose format, if a developer ran /usr/bin/time -v manually.
    m = re.search(r"Elapsed \(wall clock\) time.*?:\s*([0-9:,\.]+)", text)
    if m:
        return _parse_time_number_0315i(m.group(1)), math.nan, math.nan

    return math.nan, math.nan, math.nan


def _candidate_paths_0315i(path_text: str, manifest_path: Path, art_dir: Path) -> Iterable[Path]:
    """Return plausible locations for paths recorded in the manifest.

    Manifest paths are normally relative to the repository root.  If the user
    invokes the summarizer from another directory, try ART_DIR-relative and
    manifest-directory-relative fallbacks before giving up.
    """
    if not path_text:
        return []
    p = Path(path_text)
    candidates = [p]
    if not p.is_absolute():
        candidates.append(manifest_path.parent / p)
        candidates.append(art_dir / p.name)
    # Deduplicate while preserving order.
    seen = set()
    out = []
    for c in candidates:
        try:
            key = str(c.resolve())
        except Exception:
            key = str(c)
        if key not in seen:
            seen.add(key)
            out.append(c)
    return out


def parse_time_sources(row: Dict[str, str], manifest_path: Path, art_dir: Path) -> Tuple[float, float, float, str]:
    """Parse timing from the internal time file, then wrapper stdout/stderr.

    0315i originally parsed only runRoot/logs/<case>.time.  On some runs this
    file can be absent or rewritten by wrapper cleanup, while src_gpu_demo_common
    still echoes the same elapsed line to wrapper stdout.  Use the logs as a
    robust fallback so existing runs can be summarized without rerunning.
    """
    sources = [
        ("timeFile", row.get("timeFile", "")),
        ("stdoutFile", row.get("stdoutFile", "")),
        ("stderrFile", row.get("stderrFile", "")),
    ]
    for label, path_text in sources:
        for path in _candidate_paths_0315i(path_text, manifest_path, art_dir):
            text = _read_text_if_exists_0315i(path)
            elapsed, user_time, sys_time = _parse_time_text_0315i(text)
            if math.isfinite(elapsed):
                return elapsed, user_time, sys_time, f"{label}:{path}"
    return math.nan, math.nan, math.nan, "none"


def read_summary_final(path: Path) -> Dict[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with path.open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    return rows[-1] if rows else {}


def mean(values: List[float]) -> float:
    finite = [v for v in values if math.isfinite(v)]
    return statistics.mean(finite) if finite else math.nan


def stdev(values: List[float]) -> float:
    finite = [v for v in values if math.isfinite(v)]
    return statistics.stdev(finite) if len(finite) >= 2 else 0.0 if len(finite) == 1 else math.nan


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: summarize_active_prefix_scaling_0315i.py MANIFEST ART_DIR", file=sys.stderr)
        return 2
    manifest_path = Path(sys.argv[1])
    art_dir = Path(sys.argv[2])
    details_path = art_dir / "active_prefix_0315i_scaling_details.csv"
    summary_path = art_dir / "active_prefix_0315i_scaling_summary.csv"

    with manifest_path.open(newline="") as fh:
        manifest = list(csv.DictReader(fh))

    detail_rows: List[Dict[str, object]] = []
    grouped: Dict[Tuple[str, int], List[Dict[str, object]]] = defaultdict(list)

    for row in manifest:
        case = row["caseName"]
        inactive = int(row["inactiveSlots"])
        steps = int(row["requestedSteps"])
        rc = int(row["exitCode"])
        elapsed, user_time, sys_time, time_source = parse_time_sources(row, manifest_path, art_dir)
        final = read_summary_final(Path(row["summaryFile"]))
        sec_per_step = elapsed / steps if math.isfinite(elapsed) and steps > 0 else math.nan
        detail = {
            "caseName": case,
            "inactiveSlots": inactive,
            "repeat": int(row["repeat"]),
            "exitCode": rc,
            "requestedSteps": steps,
            "elapsedSeconds": elapsed,
            "userSeconds": user_time,
            "sysSeconds": sys_time,
            "secondsPerStep": sec_per_step,
            "timeSource": time_source,
            "finalStep": final.get("step", ""),
            "Np": final.get("Np", ""),
            "nFluidParticles": final.get("nFluidParticles", ""),
            "nInactiveParticles": final.get("nInactiveParticles", ""),
            "totalMass": final.get("totalMass", ""),
            "kBTEstimate": final.get("kBTEstimate", ""),
            "runRoot": row["runRoot"],
        }
        detail_rows.append(detail)
        grouped[(case, inactive)].append(detail)

    baseline_by_case: Dict[str, float] = {}
    for case in sorted({k[0] for k in grouped}):
        min_inactive = min(inactive for c, inactive in grouped if c == case)
        baseline_by_case[case] = mean([float(r["secondsPerStep"]) for r in grouped[(case, min_inactive)]])

    summary_rows: List[Dict[str, object]] = []
    for (case, inactive), rows in sorted(grouped.items()):
        elapsed_values = [float(r["elapsedSeconds"]) for r in rows]
        sps_values = [float(r["secondsPerStep"]) for r in rows]
        exit_codes = [int(r["exitCode"]) for r in rows]
        sps_mean = mean(sps_values)
        baseline = baseline_by_case.get(case, math.nan)
        ratio = sps_mean / baseline if math.isfinite(sps_mean) and math.isfinite(baseline) and baseline > 0 else math.nan
        summary_rows.append({
            "caseName": case,
            "inactiveSlots": inactive,
            "repeats": len(rows),
            "allExitZero": int(all(code == 0 for code in exit_codes)),
            "elapsedMeanSeconds": mean(elapsed_values),
            "elapsedStdSeconds": stdev(elapsed_values),
            "secondsPerStepMean": sps_mean,
            "secondsPerStepStd": stdev(sps_values),
            "ratioVsSmallestInactive": ratio,
            "finalNFluidParticlesLastRepeat": rows[-1].get("nFluidParticles", "") if rows else "",
            "finalNInactiveParticlesLastRepeat": rows[-1].get("nInactiveParticles", "") if rows else "",
        })

    detail_fields = [
        "caseName", "inactiveSlots", "repeat", "exitCode", "requestedSteps",
        "elapsedSeconds", "userSeconds", "sysSeconds", "secondsPerStep",
        "timeSource", "finalStep", "Np", "nFluidParticles", "nInactiveParticles",
        "totalMass", "kBTEstimate", "runRoot",
    ]
    summary_fields = [
        "caseName", "inactiveSlots", "repeats", "allExitZero",
        "elapsedMeanSeconds", "elapsedStdSeconds", "secondsPerStepMean",
        "secondsPerStepStd", "ratioVsSmallestInactive",
        "finalNFluidParticlesLastRepeat", "finalNInactiveParticlesLastRepeat",
    ]
    with details_path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=detail_fields)
        writer.writeheader()
        writer.writerows(detail_rows)
    with summary_path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=summary_fields)
        writer.writeheader()
        writer.writerows(summary_rows)

    failed = [r for r in detail_rows if int(r["exitCode"]) != 0]
    missing_time = [r for r in detail_rows if not math.isfinite(float(r["elapsedSeconds"]))]
    print(f"[0315i-scale] runs={len(detail_rows)} failed={len(failed)} missingTime={len(missing_time)}")
    if failed:
        for r in failed[:20]:
            print(f"[0315i-scale] FAIL case={r['caseName']} inactive={r['inactiveSlots']} repeat={r['repeat']} exitCode={r['exitCode']}")
        return 1
    if missing_time:
        for r in missing_time[:12]:
            print(f"[0315i-scale] WARN missing time case={r['caseName']} inactive={r['inactiveSlots']} repeat={r['repeat']} source={r['timeSource']}", file=sys.stderr)
    for r in summary_rows:
        print(
            "[0315i-scale] "
            f"case={r['caseName']} inactive={r['inactiveSlots']} "
            f"s/step={float(r['secondsPerStepMean']):.6g} "
            f"ratio={float(r['ratioVsSmallestInactive']):.4g}"
        )
    return 0 if not missing_time else 0


if __name__ == "__main__":
    raise SystemExit(main())

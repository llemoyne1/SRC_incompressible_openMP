#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "scripts" / "analyze_0493x7n_compression_estimator_offline.py"

if not P.exists():
    raise SystemExit(f"[0493x7n-compression-fix1] ERROR missing {P}")

text = P.read_text()

old = 'def list_case_frames(root, meta, base, stride):\n    dump_dir = resolve_dump_dir(root, meta["kind"])\n    dumps = base.list_dumps(dump_dir)\n    dumps = [(s, p) for s, p in dumps if int(s) > 0]\n    if stride > 1:\n        dumps = dumps[::stride]\n    if not dumps:\n        raise ValueError(f"no nonzero dumps in {dump_dir}")\n    return dumps\n'
new = 'def list_case_frames(root, meta, base, stride):\n    dump_dir = resolve_dump_dir(root, meta["kind"])\n\n    # First keep compatibility with the canonical 0493w1 calibrator naming.\n    dumps = base.list_dumps(dump_dir)\n\n    # run_ok_dambreak.sh writes states as:\n    #   state_step_00000010.smpcd\n    # which the 0493w1 list_dumps() helper does not recognize.\n    # Fall back to this explicit public-runner format without changing the\n    # canonical state reader.\n    if not dumps:\n        rx = re.compile(r"^state_step_(\\d+)\\.smpcd$")\n        fallback = []\n        for path in sorted(dump_dir.glob("state_step_*.smpcd")):\n            m = rx.match(path.name)\n            if m:\n                fallback.append((int(m.group(1)), path))\n        dumps = fallback\n\n    dumps = sorted(\n        [(int(s), Path(p)) for s, p in dumps if int(s) > 0],\n        key=lambda item: item[0],\n    )\n\n    if stride > 1:\n        dumps = dumps[::stride]\n\n    if not dumps:\n        sample = sorted(p.name for p in dump_dir.glob("*.smpcd"))[:10]\n        raise ValueError(\n            f"no nonzero dumps recognized in {dump_dir}; "\n            f"sample smpcd files={sample}"\n        )\n\n    return dumps\n'

n = text.count(old)
if n != 1:
    raise SystemExit(
        f"[0493x7n-compression-fix1] ERROR list_case_frames matches={n}"
    )

text = text.replace(old, new, 1)

checks = [
    "import re",
    'rx = re.compile(r"^state_step_(\\d+)\\.smpcd$")',
    'dump_dir.glob("state_step_*.smpcd")',
    "fallback.append((int(m.group(1)), path))",
]
for needle in checks:
    if needle not in text:
        raise SystemExit(
            f"[0493x7n-compression-fix1] ERROR post-check missing {needle!r}"
        )

P.write_text(text)
P.chmod(0o755)

print("[0493x7n-compression-fix1] canonical dump discovery retained")
print("[0493x7n-compression-fix1] added state_step_XXXXXXXX.smpcd fallback")
print("[0493x7n-compression-fix1] done")

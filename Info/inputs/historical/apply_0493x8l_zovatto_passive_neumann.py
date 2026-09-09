#!/usr/bin/env python3
from pathlib import Path
import sys

TAG = "0493x8l"

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "src/cuda_q6_resident_0400.cu"
text = path.read_text(encoding="utf-8")

if "passiveNeumannRightOutlet0493x8l" in text:
    print(f"[{TAG}-patch] already applied")
    raise SystemExit(0)

if "    int inletProfileCode = 0;" in text:
    anchor = "    int inletProfileCode = 0;"
    pos = text.find(anchor)
    line_end = text.find("\n", pos)
    text = (
        text[:line_end + 1]
        + "    int passiveNeumannRightOutlet0493x8l = 0;\n"
        + text[line_end + 1:]
    )
else:
    anchor = "struct Q6SegmentedIo0409 {\n    int enabled = 0;\n    int count = 0;\n"
    if anchor not in text:
        raise SystemExit(f"[{TAG}-patch] Q6SegmentedIo0409 anchor not found")
    text = text.replace(
        anchor,
        anchor + "    int passiveNeumannRightOutlet0493x8l = 0;\n",
        1,
    )

make_start = text.find(
    "Q6SegmentedIo0409 q6_make_segmented_0409(const SimulationParams& params, double time) {"
)
if make_start < 0:
    raise SystemExit(f"[{TAG}-patch] q6_make_segmented_0409 not found")
make_end = text.find("\n}", make_start)
if make_end < 0:
    raise SystemExit(f"[{TAG}-patch] q6_make_segmented_0409 end not found")
make_region = text[make_start:make_end]

if "cfg.inletProfileCode = q6_segmented_profile_code_0493x8k(params);" in make_region:
    init_anchor = "    cfg.inletProfileCode = q6_segmented_profile_code_0493x8k(params);\n"
else:
    init_anchor = (
        "    cfg.count = std::min(static_cast<int>(params.openBoundarySegments.size()), "
        "kOpenBoundaryMaxSegments);\n"
    )
if init_anchor not in make_region:
    raise SystemExit(f"[{TAG}-patch] q6_make_segmented initialization anchor not found")

make_region = make_region.replace(
    init_anchor,
    init_anchor
    + '    cfg.passiveNeumannRightOutlet0493x8l = '
      'params.openBoundaryOutletMode == "neumann" ? 1 : 0;\n',
    1,
)
text = text[:make_start] + make_region + text[make_end:]

fn_start = text.find(
    "__device__ double q6_species_boundary_flux_for_cell_0493w7("
)
if fn_start < 0:
    raise SystemExit(f"[{TAG}-patch] q6_species_boundary_flux_for_cell_0493w7 not found")
fn_end = text.find("// 0493x6h-B0", fn_start)
if fn_end < 0:
    raise SystemExit(f"[{TAG}-patch] species boundary end marker not found")

region = text[fn_start:fn_end]

branch = '''        // 0493x8l: Zovatto-style passive right outlet.
        // Discrete zero-normal-gradient: copy the current boundary-cell ux
        // to the boundary face. The Q6-G-F boundary correction is therefore
        // target-before = 0 instead of imposing segmentUx.
        if (cfg.mode[k] == 2 && cfg.passiveNeumannRightOutlet0493x8l && face == 1) {
            if (speciesIndex < 0 || speciesIndex >= species.speciesCount ||
                cell < 0 || cell >= species.numCells) {
                return 0.0;
            }
            const int sk = speciesIndex * species.numCells + cell;
            const double m = species.mass[sk];
            if (!(m > 0.0)) return 0.0;
            const double localUx = species.px[sk] / m;
            return localUx * fraction;
        }

'''

profile_anchor = (
    "        const double targetFlux =\n"
    "            q6_segmented_profiled_flux_0493x8k(cfg, k, tangent);\n"
)
if profile_anchor in region:
    region = region.replace(profile_anchor, branch + profile_anchor, 1)
else:
    mode_anchor = "        if (cfg.mode[k] == 1) {\n"
    if mode_anchor not in region:
        raise SystemExit(f"[{TAG}-patch] species boundary insertion anchor not found")
    region = region.replace(mode_anchor, branch + mode_anchor, 1)

text = text[:fn_start] + region + text[fn_end:]
path.write_text(text, encoding="utf-8")

print(f"[{TAG}-patch] patched src/cuda_q6_resident_0400.cu")
print(f"[{TAG}-patch] passive scope: right segmented outlet + neumann + Q6-G-F species path")
print(f"[{TAG}-patch] SRC outlet unchanged; x8k inlet unchanged")
print(f"[{TAG}-patch] outlet segmentUx remains nominal diagnostic metadata only")

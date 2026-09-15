#!/usr/bin/env python3
from pathlib import Path
import re

src=Path('src/cuda_q6_resident_0400.cu').read_text()
marker='0493x17d-fix2: x17a/x16l kernels use one particle per CUDA thread'
if src.count(marker) != 2:
    raise SystemExit(f'[0493x17d-fix2-check] ERROR expected two coverage markers, found {src.count(marker)}')

# Scope the two public wrappers and ensure the old 4096-block cap is absent.
for name in ['cuda_q6_apply_chi_kinetic_boundary_prestream_0493x16j',
             'cuda_q6_record_chi_penetration_poststream_0493x16l']:
    i=src.find('bool '+name)
    if i < 0:
        raise SystemExit(f'[0493x17d-fix2-check] ERROR missing {name}')
    j=src.find('\nbool ', i+5)
    block=src[i:] if j < 0 else src[i:j]
    if 'std::min(4096' in block:
        raise SystemExit(f'[0493x17d-fix2-check] ERROR old 4096-block cap remains in {name}')
    if '(nParticles + threads - 1u) / threads' not in block:
        raise SystemExit(f'[0493x17d-fix2-check] ERROR full particle launch formula absent in {name}')

# Reproduce the failing smoke cardinality.
n=4_377_600
threads=256
blocks=(n+threads-1)//threads
launched=blocks*threads
if blocks != 17100 or launched < n:
    raise SystemExit('[0493x17d-fix2-check] ERROR analytical full-coverage calculation failed')
if 4096*threads != 1_048_576:
    raise SystemExit('[0493x17d-fix2-check] ERROR old-cap reference calculation failed')

ana=Path('scripts/analyze_0493x17d_fixed_membrane_publishable.py').read_text()
for token in ['penetration_full_particle_coverage','hydrodynamic_x_load_present','minPenetrationParticleCoverage']:
    if token not in ana:
        raise SystemExit(f'[0493x17d-fix2-check] ERROR analyzer missing {token}')

run=Path('scripts/run_0493x17d_fixed_membrane_publishable.sh').read_text()
if 'set -euo pipefail' in run:
    raise SystemExit('[0493x17d-fix2-check] ERROR runner still uses set -euo pipefail')
if 'LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"' not in run:
    raise SystemExit('[0493x17d-fix2-check] ERROR LiveVis default cadence is not 1')

print(f'[0493x17d-fix2-check] oldCoverage={4096*threads}/{n}={4096*threads/n:.6f}')
print(f'[0493x17d-fix2-check] newBlocks={blocks} launchedThreads={launched} nParticles={n}')
print('[0493x17d-fix2-check] PASS')

#!/usr/bin/env python3
from pathlib import Path

path = Path('src/cuda_q6_resident_0400.cu')
if not path.is_file():
    raise SystemExit(f'ERROR: missing {path}')

text = path.read_text()
old = '''        const bool periodicMomentumCorrectionThisSpecies0493x7dv2fix2 =\n            params.projectionMomentumCorrectionEnable &&\n            faceToParticleRt00493x6hB1 && audit.fullDomain &&\n            !virialDensityKickRequested0493x7a && (periodicX || periodicY);\n'''
new = '''        const bool periodicMomentumCorrectionThisSpecies0493x7dv2fix2 =\n            faceToParticleRt00493x6hB1 && audit.fullDomain &&\n            !virialDensityKickRequested0493x7a && (periodicX || periodicY);\n'''

count = text.count(old)
if count != 1:
    raise SystemExit(
        f'ERROR: expected exactly one x7d-v2-fix2 guard, found {count}; '
        'source does not match the just-applied fix2 patch'
    )

path.write_text(text.replace(old, new, 1))
print('PASS: x7d-v2-fix2a enabled periodic projected-species momentum closure')
print('      independent of legacy projectionMomentumCorrectionEnable')
print('modified:', path)

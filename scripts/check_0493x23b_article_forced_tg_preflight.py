#!/usr/bin/env python3
from __future__ import annotations
import argparse, math
from pathlib import Path


def parse_kv(path: Path):
    d = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k.strip()] = v.strip()
    return d


def f(v): return float(v)
def i(v): return int(float(v))
def close(a,b,rtol=1e-12,atol=1e-14): return math.isclose(float(a),float(b),rel_tol=rtol,abs_tol=atol)

p=argparse.ArgumentParser()
p.add_argument('--src',required=True,type=Path); p.add_argument('--closure',required=True,type=Path)
p.add_argument('--expected-nx',required=True,type=int); p.add_argument('--expected-ny',required=True,type=int)
p.add_argument('--expected-gamma',required=True,type=float); p.add_argument('--expected-dt',required=True,type=float)
p.add_argument('--expected-kbt',required=True,type=float); p.add_argument('--expected-angle',required=True,type=float)
p.add_argument('--expected-force',required=True,type=float); p.add_argument('--expected-mode-x',required=True,type=int)
p.add_argument('--expected-mode-y',required=True,type=int); p.add_argument('--expected-steps',required=True,type=int)
p.add_argument('--expected-dump-every',required=True,type=int)
a=p.parse_args()
S=parse_kv(a.src); C=parse_kv(a.closure)
errors=[]

def req(cond,msg):
    if not cond: errors.append(msg)

req(S.get('inputState') == C.get('inputState') and bool(S.get('inputState')), 'inputState must be identical and non-empty')
for key in ['Lx','Ly','Nx','Ny','dt','nSteps','bcLeft','bcRight','bcBottom','bcTop','bcX','bcY',
            'bodyAccelerationX','bodyAccelerationY','taylorGreenForcingEnable','taylorGreenForcingAmplitude',
            'taylorGreenForcingModeX','taylorGreenForcingModeY','rotationAngle','randomRotationSign','gridShiftEnable',
            'rngSeed','thermostatEnable','thermostatMode','thermostatEvery','thermostatTargetKBT','thermostatMinParticles',
            'kBT','summaryEvery','dumpStateEvery','resamplingEnable']:
    req(key in S and key in C, f'missing common key {key}')
    if key in S and key in C: req(S[key] == C[key], f'common key differs: {key}: SRC={S[key]} closure={C[key]}')

req(i(S['Nx'])==a.expected_nx and i(C['Nx'])==a.expected_nx,'Nx mismatch')
req(i(S['Ny'])==a.expected_ny and i(C['Ny'])==a.expected_ny,'Ny mismatch')
req(close(S['dt'],a.expected_dt),'dt mismatch')
req(close(S['kBT'],a.expected_kbt),'kBT mismatch')
req(close(S['rotationAngle'],a.expected_angle),'rotation angle mismatch')
req(close(S['taylorGreenForcingAmplitude'],a.expected_force),'forcing amplitude mismatch')
req(i(S['taylorGreenForcingModeX'])==a.expected_mode_x and i(S['taylorGreenForcingModeY'])==a.expected_mode_y,'forcing mode mismatch')
req(i(S['nSteps'])==a.expected_steps,'steps mismatch')
req(i(S['dumpStateEvery'])==a.expected_dump_every,'dump cadence mismatch')
req(S.get('taylorGreenForcingEnable','').lower()=='true','forcing not enabled')
for k in ['bcLeft','bcRight','bcBottom','bcTop','bcX','bcY']:
    req(S.get(k)=='periodic',f'{k} not periodic')
req(S.get('srcClassicCudaModeEnable','').lower()=='true','SRC must use classic resident SRC path')
req(S.get('projectionEnable','').lower()=='false','SRC projection must be off')
req(C.get('srcClassicCudaModeEnable','').lower()=='false','closure must leave srcClassicCudaModeEnable=false')
req(C.get('projectionEnable','').lower()=='true','closure projection must be on')
req(C.get('q6ForceProjectionMode')=='prestream_single_fused','closure forcing/projection ordering mismatch')
req(C.get('speciesQ6Mode')=='free_surface_masked','closure speciesQ6Mode mismatch')
req(C.get('speciesQ6Enable','').lower()=='true','closure speciesQ6Enable missing')
req(C.get('resamplingEnable','').lower()=='false','closure resampling must be off')
req(S.get('resamplingEnable','').lower()=='false','SRC resampling must be off')

# gamma is encoded by the target mass at m=1 in common params.
req(close(S.get('resamplingTargetCellMass','nan'),a.expected_gamma),'SRC gamma/target mass mismatch')
req(close(C.get('resamplingTargetCellMass','nan'),a.expected_gamma),'closure gamma/target mass mismatch')

if errors:
    print('[0493x23b-preflight] FAIL')
    for e in errors: print('  -',e)
    raise SystemExit(2)
print('[0493x23b-preflight] PASS')
print(f"[0493x23b-preflight] shared inputState={S['inputState']}")
print(f"[0493x23b-preflight] grid={a.expected_nx}x{a.expected_ny} gamma={a.expected_gamma:g} dt={a.expected_dt:.17g} kBT={a.expected_kbt:.17g}")
print(f"[0493x23b-preflight] forcing=continuous TG mode=({a.expected_mode_x},{a.expected_mode_y}) amplitude={a.expected_force:.17g}")
print(f"[0493x23b-preflight] steps={a.expected_steps} dumpEvery={a.expected_dump_every}")
print('[0493x23b-preflight] paths=SRC | SRC + particle/field closure (internal src-q6-g-f)')

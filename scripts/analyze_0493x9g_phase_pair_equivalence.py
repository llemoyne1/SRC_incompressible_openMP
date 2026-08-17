#!/usr/bin/env python3
import argparse, csv, hashlib, json, math
from pathlib import Path

MODES = ('legacy','family','type')
INFO_FILES = [
    'species_runtime_0493x9f.csv',
    'cuda_static_drop_pressure_0493x9e.csv',
    'cuda_static_drop_velocity_0493x9e.csv',
    'cuda_ellipse_shape_0493x9f.csv',
    'cuda_surface_tension_0493x9d.csv',
]

# x9g is an architectural selector generalization. The CUDA/thermal trajectory is
# not bitwise deterministic between independent invocations, even from an identical
# state and identical physical parameters. Gate the invariants that x9g must preserve,
# and report raw CSV hashes only as information.
PHYSICS_CHECKS = {
    # key: (relative tolerance, absolute tolerance)
    'effectiveRadius':              (5.0e-4, 5.0e-7),
    'momentRadiusMajor':            (1.0e-4, 2.0e-7),
    'momentRadiusMinor':            (1.0e-4, 2.0e-7),
    'axisRatio':                    (1.0e-4, 2.0e-6),
    'ellipticity':                  (0.0,    5.0e-5),
    'tailMomentRadiusMajorMean':    (2.0e-4, 3.0e-7),
    'tailMomentRadiusMinorMean':    (2.0e-4, 3.0e-7),
    'tailAxisRatioMean':            (2.0e-4, 3.0e-6),
    'tailEllipticityMean':          (0.0,    8.0e-5),
}

PARAM_IGNORE = {
    'inputState', 'outputDir',
    'phaseInterfaceASelector', 'phaseInterfaceBSelector',
}

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1<<20), b''):
            h.update(b)
    return h.hexdigest()

def read_last(path):
    with path.open(newline='') as f:
        rows=list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f'[0493x9g-check] ERROR empty CSV: {path}')
    return rows[-1]

def finite_float(x):
    try:
        v=float(x)
    except Exception:
        return None
    return v if math.isfinite(v) else None

def close_num(a,b,rtol=1e-14,atol=0.0):
    x=finite_float(a); y=finite_float(b)
    if x is None or y is None:
        return a == b, float('nan')
    scale=max(abs(x),abs(y))
    err=abs(x-y)
    return err <= atol + rtol*scale, err/max(scale,1e-300)

def parse_params(path):
    out={}
    for raw in path.read_text().splitlines():
        line=raw.split('#',1)[0].strip()
        if not line or '=' not in line:
            continue
        k,v=line.split('=',1)
        k=k.strip(); v=v.strip()
        if k in PARAM_IGNORE:
            continue
        out[k]=v
    return out

def compare_dicts(a,b):
    ka=set(a); kb=set(b)
    only_a=sorted(ka-kb); only_b=sorted(kb-ka)
    diffs=[]
    for k in sorted(ka&kb):
        if a[k] != b[k]:
            diffs.append((k,a[k],b[k]))
    return only_a,only_b,diffs

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    args=ap.parse_args()
    root=Path(args.root)
    outs={m:root/m/'output' for m in MODES}
    ok=True

    print('[0493x9g-check] structural selector equivalence + tolerance-based physics invariants')

    # 1) Generated initial state must be exactly identical.
    states={m:root/m/'init'/'ellipse_relaxation_0493x9f.smpcd' for m in MODES}
    if not all(p.exists() for p in states.values()):
        print('[0493x9g-check] ERROR missing one or more initial states')
        ok=False
    else:
        hs={m:sha(p) for m,p in states.items()}
        exact=len(set(hs.values())) == 1
        print('[0493x9g-check] initialState: exact=' + str(int(exact)) +
              ' sha=' + hs['legacy'][:16])
        if not exact:
            ok=False

    # 2) Every physical parameter except path + selector identity must be exact.
    params={m:root/m/'params'/'ellipse_relaxation_0493x9f.kv' for m in MODES}
    if not all(p.exists() for p in params.values()):
        print('[0493x9g-check] ERROR missing one or more params files')
        ok=False
    else:
        pd={m:parse_params(p) for m,p in params.items()}
        for m in ('family','type'):
            only_l,only_m,diffs=compare_dicts(pd['legacy'],pd[m])
            same=not only_l and not only_m and not diffs
            print(f'[0493x9g-check] params legacy/{m}: exactPhysical={int(same)}')
            if not same:
                ok=False
                if only_l: print(f'[0493x9g-check]   onlyLegacy={only_l}')
                if only_m: print(f'[0493x9g-check]   only{m.capitalize()}={only_m}')
                for k,a,b in diffs[:12]:
                    print(f'[0493x9g-check]   DIFF {k}: legacy={a} {m}={b}')

    # 3) Raw trajectory hashes are informational only. Independent CUDA/thermal
    #    invocations are not guaranteed bitwise deterministic.
    print('[0493x9g-check] raw CSV hashes (INFO only; not a PASS gate)')
    for name in INFO_FILES:
        paths=[outs[m]/name for m in MODES]
        if not all(p.exists() for p in paths):
            print(f'[0493x9g-check] MISSING {name}: ' +
                  ' '.join(f'{m}={int(p.exists())}' for m,p in zip(MODES,paths)))
            ok=False
            continue
        hashes=[sha(p) for p in paths]
        exact=len(set(hashes))==1
        print(f'[0493x9g-check] {name}: exact={int(exact)} shaLegacy={hashes[0][:16]}')

    # 4) Selector resolution / phase-pair audit is an exact semantic gate.
    expected={
        'legacy':('family:liquid','family:gas'),
        'family':('family:liquid','family:gas'),
        'type':('type:1','type:2'),
    }
    audit={}
    for m in MODES:
        p=outs[m]/'cuda_phase_pair_0493x9g.csv'
        if not p.exists():
            print(f'[0493x9g-check] MISSING phase pair audit for {m}: {p}')
            ok=False
            continue
        r=read_last(p); audit[m]=r
        ea,eb=expected[m]
        print('[0493x9g-check] pair ' + m + ': A=' + r['phaseASelector'] +
              ' B=' + r['phaseBSelector'] + ' counts=' +
              r['phaseASpeciesCount'] + '/' + r['phaseBSpeciesCount'] +
              ' refs=' + r['phaseAReferenceCellMass'] + '/' + r['phaseBReferenceCellMass'] +
              ' interface=' + r['phaseInterfaceEnabled'])
        if r['phaseASelector'] != ea or r['phaseBSelector'] != eb:
            ok=False
        if r['phaseASpeciesCount'] != '1' or r['phaseBSpeciesCount'] != '1' or r['phaseInterfaceEnabled'] != '1':
            ok=False

    if len(audit)==3:
        invariant_fields=(
            'phaseASpeciesCount','phaseBSpeciesCount',
            'phaseAReferenceCellMass','phaseBReferenceCellMass',
            'phaseInterfaceEnabled',
        )
        for field in invariant_fields:
            base=audit['legacy'][field]
            for m in ('family','type'):
                same,rel=close_num(base,audit[m][field],rtol=1e-14,atol=1e-14)
                if not same:
                    print(f'[0493x9g-check] ERROR pair invariant {field}: legacy={base} {m}={audit[m][field]}')
                    ok=False

    # 5) Compare robust x9f shape observables. This catches a real physics change
    #    while allowing the small independent-run CUDA/thermostat divergence seen
    #    with identical input state and physical parameters.
    reports={m:root/m/'ellipse_relaxation_0493x9f.json' for m in MODES}
    if not all(p.exists() for p in reports.values()):
        print('[0493x9g-check] ERROR missing one or more x9f JSON reports')
        ok=False
    else:
        rr={m:json.loads(p.read_text()) for m,p in reports.items()}
        print('[0493x9g-check] robust physical observables vs legacy')
        for key,(rtol,atol) in PHYSICS_CHECKS.items():
            base=rr['legacy'][key]
            line=[f'{key}: legacy={base:.10g}']
            key_ok=True
            for m in ('family','type'):
                v=rr[m][key]
                same,rel=close_num(base,v,rtol=rtol,atol=atol)
                abs_err=abs(float(v)-float(base))
                line.append(f'{m}={v:.10g} abs={abs_err:.3e} rel={rel:.3e} pass={int(same)}')
                key_ok = key_ok and same
            print('[0493x9g-check]   ' + ' | '.join(line))
            if not key_ok:
                ok=False

        # Useful diagnostics, explicitly not gates because instantaneous interface
        # velocity and COM displacement are much noisier than shape invariants.
        for key in ('particleCenterDisplacement','interfaceSpeedRmsTrueBand'):
            vals=' '.join(f'{m}={rr[m][key]:.8g}' for m in MODES)
            print(f'[0493x9g-check] INFO {key}: {vals}')

    print('[0493x9g-check] status=' + ('PASS' if ok else 'FAIL'))
    raise SystemExit(0 if ok else 2)

if __name__=='__main__':
    main()

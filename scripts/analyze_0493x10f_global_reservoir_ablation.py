#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        'usage: analyze_0493x10f_global_reservoir_ablation.py '
        '<cuda_phase_kinetic_crossing_0493x9z.csv>')

p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10f-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def S(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def pct(a,b): return 100.0*a/b if b else 0.0

last = rows[-1]
checks = S('hardFinalEndpointChecks')
outside = S('hardFinalEndpointOutsideBefore')
after = S('hardFinalEndpointOutsideAfter')
miss = S('hardFinalLocalAnchorMisses')
maxdeep = max(I(r,'deepOuterParticles') for r in rows)

active = S('globalReactionActive')
trivial = S('globalReactionTrivial')
invalid = S('globalReactionInvalid')
scales = [F(r,'globalReactionScale') for r in rows if I(r,'globalReactionActive')]
cancel = [F(r,'globalReactionCancellationRatio') for r in rows if I(r,'globalReactionActive')]
dus = [F(r,'globalReactionDeltaUMagnitude') for r in rows if I(r,'globalReactionActive')]

print('===== 0493x10f GLOBAL RESERVOIR ABLATION =====')
print(f'file={p} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- global exact reaction ---')
print(f'active={active} trivial={trivial} invalid={invalid}')
if scales:
    print(f'scale a: last={scales[-1]:.9g} min={min(scales):.9g} max={max(scales):.9g} mean={sum(scales)/len(scales):.9g}')
if cancel:
    print('S cancellation |sum S|/sum|S_cell|: '
          f'last={cancel[-1]:.6e} max={max(cancel):.6e} mean={sum(cancel)/len(cancel):.6e}')
if dus:
    print(f'global receiver |du|: last={dus[-1]:.6e} max={max(dus):.6e}')
print(f'last donorCells={I(last,"globalReactionDonorCells")} '
      f'receiverCells={I(last,"globalReactionReceiverCells")} '
      f'receiverMass={F(last,"globalReactionReceiverMass"):.9g}')

print('--- actual pass-3 conservation ---')
dp = max(maxabs('deltaPx'), maxabs('deltaPy'))
de = maxabs('deltaKineticEnergy')
formula = maxabs('globalReactionFormulaResidual')
print(f'max|deltaP|={dp:.12e}')
print(f'max|deltaKE|={de:.12e}')
print(f'max|analyticResidual|={formula:.12e}')

print('--- hard barrier / shape context ---')
print(f'outsideBefore={outside}/{checks} ({pct(outside,checks):.6f}%)')
print(f'outsideAfter={after}/{checks} anchorMisses={miss} maxDeepOuter={maxdeep}')
print(f'last hardFinalReceiverOutsideBefore={I(last,"hardFinalReceiverOutsideBefore")}')

cons = dp < 1e-9 and de < 1e-9 and formula < 1e-9
ret = after == 0 and miss == 0
glob = active > 0 and invalid == 0
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('hardRetentionContract=' + ('PASS' if ret else 'FAIL'))
print('globalReservoirContract=' + ('PASS' if glob else 'FAIL'))
print('multiComponentContract=NOT_APPLICABLE_ABLATION_ONLY')
print('shapeContract=VISUAL_PENDING')

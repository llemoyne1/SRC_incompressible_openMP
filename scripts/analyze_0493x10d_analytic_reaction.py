#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10d_analytic_reaction.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10d-check] ERROR empty CSV')

required = [
    'analyticConservativeReactionCells','analyticPositiveScaleCells',
    'analyticInwardCells','analyticNonInwardPositiveCells',
    'analyticTrivialCells','analyticInvalidCells',
    'analyticDonorScaleMean','analyticDonorScaleAbsFromSpecularMean',
    'hardFinalEndpointOutsideAfter','hardFinalLocalAnchorMisses',
]
missing = [k for k in required if k not in rows[0]]
if missing:
    raise SystemExit('[0493x10d-check] ERROR missing columns: ' + ','.join(missing))

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def wmean(mean_key, count_key):
    n = sum(I(r,count_key) for r in rows)
    return (sum(F(r,mean_key)*I(r,count_key) for r in rows)/n) if n else 0.0

a_cells = isum('analyticConservativeReactionCells')
pos = isum('analyticPositiveScaleCells')
inward = isum('analyticInwardCells')
nonin = isum('analyticNonInwardPositiveCells')
triv = isum('analyticTrivialCells')
invalid = isum('analyticInvalidCells')
no_recv = isum('reactionNoReceiverCells')
floors = isum('reactionEnergyFloorCells')
degen = isum('reactionThermalDegenerateCells')
still_out = isum('appliedStillOutwardRelative')
applied = isum('appliedReflections')
out_after = isum('hardFinalEndpointOutsideAfter')
anchor_miss = isum('hardFinalLocalAnchorMisses')
deep_max = max(I(r,'deepOuterParticles') for r in rows)
max_dp = max(maxabs('deltaPx'), maxabs('deltaPy'))
max_de = maxabs('deltaKineticEnergy')
formula_res = maxabs('reactionEnergyResidualAbs')
mean_a = wmean('analyticDonorScaleMean','analyticPositiveScaleCells')
mean_da2 = wmean('analyticDonorScaleAbsFromSpecularMean','analyticPositiveScaleCells')
last = rows[-1]

print('===== 0493x10d ANALYTIC CONSERVATIVE HARD-r1 REACTION =====')
print(f'file={p} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- analytic cell reaction ---')
print(f'cells={a_cells} positiveScale={pos} trivialExactRoot={triv} invalid={invalid} noReceiver={no_recv}')
print(f'inward(a>1)={inward} nonInwardPositive(0<a<=1)={nonin}')
print(f'meanA={mean_a:.9g} mean|a-2|={mean_da2:.9g}')
print(f'legacyEnergyFloorCells={floors} legacyThermalDegenerateCells={degen}')
print('--- actual pass-3 conservation ---')
print(f'max|deltaP|={max_dp:.12e}')
print(f'max|deltaKE|={max_de:.12e}')
print(f'maxAnalyticFormulaResidualAbsSum={formula_res:.12e}')
print('--- kinetic interface / hard barrier ---')
print(f'appliedStillOutwardRelative={still_out}/{applied}')
print(f'hardFinalOutsideAfter={out_after} anchorMisses={anchor_miss} maxDeepOuter={deep_max}')

# These are absolute reduced-unit tolerances.  Prior x9/x10 roundoff audits are
# around 1e-13; 1e-8 leaves ample room for atomic reduction ordering while
# still sharply separating the old O(1..100) reaction defects.
cons = max_dp <= 1e-8 and max_de <= 1e-8
geom = out_after == 0 and anchor_miss == 0
analytic = invalid == 0 and floors == 0
inw = nonin == 0 and triv == 0 and still_out == 0
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('hardRetentionContract=' + ('PASS' if geom else 'FAIL'))
print('analyticNoFloorContract=' + ('PASS' if analytic else 'FAIL'))
print('inwardnessContract=' + ('PASS' if inw else 'FAIL'))
if cons and geom and analytic and inw:
    print('qualification=PASS')
elif cons and geom and analytic:
    print('qualification=PASS_P_E_RETENTION__INWARDNESS_NEEDS_REVIEW')
else:
    print('qualification=FAIL')

#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        'usage: analyze_0493x10i_mesoscopic_reservoirs.py '
        '<cuda_phase_kinetic_crossing_0493x9z.csv>')

p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10i-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def weighted_mean(value_key, count_key):
    den=sum(I(r,count_key) for r in rows)
    num=sum(F(r,value_key)*I(r,count_key) for r in rows)
    return num/den if den else 0.0

last=rows[-1]
active=isum('mesoReactionActiveReservoirs')
trivial=isum('mesoReactionTrivialReservoirs')
invalid=isum('mesoReactionInvalidReservoirs')
no_recv=isum('mesoReactionNoReceiverReservoirs')
dp=max(maxabs('deltaPx'),maxabs('deltaPy'))
de=maxabs('deltaKineticEnergy')
formula=max(F(r,'mesoReactionFormulaResidualAbsSum') for r in rows)
deep=max(I(r,'deepOuterParticles') for r in rows)

print('===== 0493x10i SHIFTED MESOSCOPIC RESERVOIRS =====')
print(f'file={p} rows={len(rows)} lastStep={I(last,"step")}')
print(f'blockCells={I(last,"mesoReactionBlockCells")} '
      f'lastShift=({I(last,"mesoReactionShiftX")},{I(last,"mesoReactionShiftY")}) '
      f'reservoirSlots={I(last,"mesoReactionReservoirSlots")}')
print('--- reaction reservoirs ---')
print(f'active={active} trivial={trivial} invalid={invalid} noReceiver={no_recv}')
print(f'trivialFraction={(trivial/active if active else 0):.6%} '
      f'invalidFraction={(invalid/active if active else 0):.6%}')
print(f'meanA={weighted_mean("mesoReactionScaleMean","mesoReactionActiveReservoirs"):.9g} '
      f'mean|a-2|={weighted_mean("mesoReactionScaleAbsFromSpecularMean","mesoReactionActiveReservoirs"):.9g}')
print(f'mean|du|={weighted_mean("mesoReactionDeltaUMagnitudeMean","mesoReactionActiveReservoirs"):.9g} '
      f'meanCancellation={weighted_mean("mesoReactionCancellationMean","mesoReactionActiveReservoirs"):.9g}')
print(f'last donorCells={I(last,"mesoReactionDonorCells")} '
      f'receiverCells={I(last,"mesoReactionReceiverCells")} '
      f'receiverMass={F(last,"mesoReactionReceiverMassSum"):.9g}')
print('--- actual conservation / mobile interface ---')
print(f'max|deltaP|={dp:.12e}')
print(f'max|deltaKE|={de:.12e}')
print(f'maxMesoFormulaResidualAbsSum={formula:.12e}')
print(f'maxDeepOuter={deep}')
print(f'universalHardBarrierChecks={isum("hardFinalEndpointChecks")}')
print(f'interiorDonorFinalOutside={isum("appliedInteriorFinalOutside")} '
      f'shellDonorFinalOutside={isum("shellHardRetentionFinalOutside")}')

cons=(dp < 1e-8 and de < 1e-9 and formula < 1e-8)
mobile=(isum('hardFinalEndpointChecks')==0)
seal=(isum('appliedInteriorFinalOutside')==0 and
      isum('shellHardRetentionFinalOutside')==0)
finite=(invalid==0)
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('mobileInterfaceContract=' + ('PASS' if mobile else 'FAIL'))
print('thermalDonorSealContract=' + ('PASS' if seal else 'FAIL'))
print('mesoscopicFiniteContract=' + ('PASS' if finite else 'FAIL'))
print('shapeContract=VISUAL_PENDING')
print('multiComponentContract=NOT_QUALIFIED_NO_CCL')

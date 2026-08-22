#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10c_final_endpoint_barrier.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
path = Path(sys.argv[1])
with path.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10c-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def rat(a,b): return a/b if b else 0.0
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)

last = rows[-1]
checks = isum('hardFinalEndpointChecks')
outside_before = isum('hardFinalEndpointOutsideBefore')
receiver_out = isum('hardFinalReceiverOutsideBefore')
neutral_out = isum('hardFinalNeutralOutsideBefore')
corr = isum('hardFinalEndpointCorrections')
local = isum('hardFinalLocalAnchorCorrections')
miss = isum('hardFinalLocalAnchorMisses')
outside_after = isum('hardFinalEndpointOutsideAfter')

deep0 = I(rows[0], 'deepOuterParticles')
deep1 = I(last, 'deepOuterParticles')
shell0 = I(rows[0], 'shellParticles')
shell1 = I(last, 'shellParticles')
outer0 = I(rows[0], 'phaseAOuterCellParticles')
outer1 = I(last, 'phaseAOuterCellParticles')

print('===== 0493x10c FINAL POST-VELOCITY ENDPOINT BARRIER =====')
print(f'file={path} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- final barrier ---')
print(f'checks={checks}')
print(f'outsideBefore={outside_before} ({rat(outside_before,checks):.6%} of checked)')
print(f'  receiverReactionCreated/Remaining={receiver_out} ({rat(receiver_out,outside_before):.3%} of outside)')
print(f'  neutralOrOldGate={neutral_out} ({rat(neutral_out,outside_before):.3%} of outside)')
print(f'corrections={corr} localAnchorCorrections={local} anchorMisses={miss}')
print(f'outsideAfter={outside_after}/{checks} ({rat(outside_after,checks):.9%})')
print('--- classification halo before same-pass recovery ---')
print(f'outer first={outer0} last={outer1} growth={outer1-outer0:+d}')
print(f'shell first={shell0} last={shell1} growth={shell1-shell0:+d}')
print(f'deepOuter first={deep0} last={deep1} growth={deep1-deep0:+d}')
print('--- reaction audit retained only as context ---')
print(f'max|deltaP|={max(maxabs("deltaPx"),maxabs("deltaPy")):.6e}')
print(f'max|deltaKE|={maxabs("deltaKineticEnergy"):.6e}')
print(f'lastMeanLambdaDev={F(last,"reactionLambdaDeviationAbsMean"):.6e}')

contract = (outside_after == 0 and miss == 0)
print('finalEndpointContract=' + ('PASS' if contract else 'FAIL'))
if contract and deep1 > 0:
    print('interpretation=all corrected-pass endpoints are inside current alpha; residual deepOuter is pre-correction/reclassification history')
elif contract:
    print('interpretation=hard r=1 geometric retention closed on current alpha')
else:
    print('interpretation=hard barrier still has an uncovered local geometry path')

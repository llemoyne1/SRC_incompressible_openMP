#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10g_dripping_vk_validation.py <output-dir>')
out = Path(sys.argv[1])
kin = out / 'cuda_phase_kinetic_crossing_0493x9z.csv'
shape = out / 'cuda_ellipse_shape_0493x9f.csv'

def rows(path):
    if not path.exists(): return []
    with path.open(newline='') as f: return list(csv.DictReader(f))
def F(r,k):
    try: return float(r.get(k,0) or 0)
    except Exception: return 0.0
def I(r,k): return int(F(r,k))
def mean(v): return sum(v)/len(v) if v else 0.0
def maxabs(rs,k): return max((abs(F(r,k)) for r in rs), default=0.0)

kr = rows(kin)
if not kr:
    raise SystemExit(f'[0493x10g-drip-check] ERROR missing/empty {kin}')
checks=sum(I(r,'hardFinalEndpointChecks') for r in kr)
out_before=sum(I(r,'hardFinalEndpointOutsideBefore') for r in kr)
out_after=sum(I(r,'hardFinalEndpointOutsideAfter') for r in kr)
miss=sum(I(r,'hardFinalLocalAnchorMisses') for r in kr)
deep=max((I(r,'deepOuterParticles') for r in kr), default=0)
trivial=sum(I(r,'globalReactionTrivial') for r in kr)
invalid=sum(I(r,'globalReactionInvalid') for r in kr)
active=[r for r in kr if I(r,'globalReactionActive')]
scales=[F(r,'globalReactionScale') for r in active]
cancel=[F(r,'globalReactionCancellationRatio') for r in active]
dus=[F(r,'globalReactionDeltaUMagnitude') for r in active]

print('===== 0493x10g DRIPPING VK / RETENTION AUDIT =====')
print(f'rows={len(kr)} lastStep={I(kr[-1],"step")}')
print(f'barrier outsideBefore={out_before}/{checks} ({(out_before/checks if checks else 0):.6%}) outsideAfter={out_after} anchorMisses={miss} maxDeepOuter={deep}')
print(f'globalReaction activeRows={len(active)} trivial={trivial} invalid={invalid}')
if scales:
    print(f'global a last={scales[-1]:.9g} min={min(scales):.9g} max={max(scales):.9g} mean={mean(scales):.9g}')
    print(f'S cancellation mean={mean(cancel):.6e} max={max(cancel):.6e}; max|du|={max(dus):.6e}')
print(f'max|deltaP|={max(maxabs(kr,"deltaPx"),maxabs(kr,"deltaPy")):.12e}')
print(f'max|deltaKE|={maxabs(kr,"deltaKineticEnergy"):.12e}')

sr=rows(shape)
if sr:
    first,last=sr[0],sr[-1]
    print('--- liquid inventory / topology proxy ---')
    print(f'liquidParticles={F(first,"liquidParticles"):.0f}->{F(last,"liquidParticles"):.0f} liquidMass={F(first,"liquidMass"):.9g}->{F(last,"liquidMass"):.9g}')
    print(f'COM=({F(last,"xCM"):.6g},{F(last,"yCM"):.6g}) axisRatio(last)={F(last,"axisRatio"):.6g}')

ret=(out_after==0 and miss==0)
cons=(max(maxabs(kr,'deltaPx'),maxabs(kr,'deltaPy')) < 1e-7 and maxabs(kr,'deltaKineticEnergy') < 1e-9)
print('retentionContract=' + ('PASS' if ret else 'FAIL'))
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('surfaceTensionPotentialContract=VISUAL: require hanging drop/neck/pinch-off/free drop/impact as reached in run window')
print('multiComponentContract=NOT_QUALIFIED: after pinch-off detached drop and feeding jet share the current x10g global reservoir')

#!/usr/bin/env python3
import argparse, csv, math
from pathlib import Path

def f(row, key, default=0.0):
    try: return float(row.get(key, default))
    except (TypeError, ValueError): return default

def i(row, key, default=0):
    try: return int(float(row.get(key, default)))
    except (TypeError, ValueError): return default

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--csv', required=True); args=ap.parse_args()
    path=Path(args.csv)
    if not path.is_file(): raise SystemExit(f'[0493x9u-check] missing {path}')
    with path.open(newline='') as fh: rows=list(csv.DictReader(fh))
    if not rows: raise SystemExit(f'[0493x9u-check] no rows in {path}')
    keys=('phaseAParticlesInOuterSupport','crossings','legacyHalfIsoCrossings','supportExitCrossings',
          'selectedReflections','transmittedCrossings','appliedReflections','unsupportedReflections',
          'bathSearchFailures','bathDepth0','bathDepth1','bathDepth2','normalFallbacks','convertedParticles')
    sums={k:sum(i(r,k) for r in rows) for k in keys}
    ref_mass=sum(f(r,'reflectedMass') for r in rows); tx_mass=sum(f(r,'transmittedMass') for r in rows)
    max_dp=max(math.hypot(f(r,'deltaPx'),f(r,'deltaPy')) for r in rows)
    max_dke=max(abs(f(r,'deltaKineticEnergy')) for r in rows)
    rvals=[f(r,'reflectionFraction',math.nan) for r in rows]; target=i(rows[-1],'evaporationTargetType',-1)
    partition=sums['crossings']==sums['legacyHalfIsoCrossings']+sums['supportExitCrossings']
    select_partition=sums['crossings']==sums['selectedReflections']+sums['transmittedCrossings']
    depth_partition=sums['crossings']==sums['bathDepth0']+sums['bathDepth1']+sums['bathDepth2']
    r_one=all(math.isfinite(x) and abs(x-1.0)<=1e-14 for x in rvals)
    apply_ok=(not r_one) or (sums['transmittedCrossings']==0 and sums['appliedReflections']==sums['selectedReflections'] and sums['unsupportedReflections']==0)
    conversion_ok=target<0 or sums['convertedParticles']==sums['transmittedCrossings']
    conservative=math.isfinite(max_dp) and math.isfinite(max_dke) and max_dp<=1e-9 and max_dke<=1e-9
    status='PASS' if partition and select_partition and depth_partition and apply_ok and conversion_ok and conservative else 'FAIL'
    print('===== 0493x9u SUPPORT-EDGE KINETIC REFLECTION =====')
    print(f'file={path}')
    print(f'rows={len(rows)} reflectionFractionLast={rvals[-1]:.9g} evaporationTargetType={target}')
    print(f"outerSupportParticleSamples={sums['phaseAParticlesInOuterSupport']} bathSearchFailures={sums['bathSearchFailures']}")
    print(f"crossings={sums['crossings']} legacyHalfIso={sums['legacyHalfIsoCrossings']} supportExit={sums['supportExitCrossings']} partitionOK={int(partition)}")
    if sums['crossings']: print(f"supportExit/crossings={sums['supportExitCrossings']/sums['crossings']:.9g}")
    print(f"selected={sums['selectedReflections']} transmitted={sums['transmittedCrossings']} applied={sums['appliedReflections']} unsupported={sums['unsupportedReflections']}")
    print(f"bathDepth(0,1,2)=({sums['bathDepth0']},{sums['bathDepth1']},{sums['bathDepth2']}) depthPartitionOK={int(depth_partition)} normalFallbacks={sums['normalFallbacks']}")
    print(f'reflectedMass={ref_mass:.9g} transmittedMass={tx_mass:.9g}')
    print(f'max|deltaP|={max_dp:.6e} max|deltaKE|={max_dke:.6e} conservative={int(conservative)}')
    print(f'status={status}')
if __name__=='__main__': main()

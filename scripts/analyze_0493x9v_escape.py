#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path


def iv(row, key, default=0):
    try:
        return int(float(row.get(key, default)))
    except (TypeError, ValueError):
        return default


def fv(row, key, default=0.0):
    try:
        return float(row.get(key, default))
    except (TypeError, ValueError):
        return default


def ratio(a, b):
    return float(a) / float(b) if b else 0.0


def pct(a, b):
    return 100.0 * ratio(a, b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv', required=True)
    args = ap.parse_args()
    path = Path(args.csv)
    if not path.is_file():
        raise SystemExit(f'[0493x9v-check] missing {path}')
    with path.open(newline='') as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise SystemExit(f'[0493x9v-check] no rows in {path}')

    count_keys = (
        'outerSupportParticles','outerSupportCellParticlesLT3','crossings','supportExitCrossings',
        'bathSearchFailures','bathSearchFailureWouldExitLocal','detectorPredictedOuterTarget',
        'missedOccupiedOuterTarget','missedSparseOuterTargetLT3','absoluteSupportExitCandidates',
        'missedRelativeButAbsoluteExit','bathAlphaGEHalf','bathAlphaLTHalf',
        'supportExitBathAlphaGEHalf','supportExitBathAlphaLTHalf','selectedReflections',
        'appliedReflections','unsupportedReflections','unsupportedInvalidBath',
        'unsupportedInvalidDonorGroup','unsupportedNoReceiverMass','unsupportedNormalCancellation',
        'unsupportedGroupNotOutward','appliedStillOutwardRelative','appliedStillRelativeExit',
        'appliedStillAbsoluteExit')
    s = {k: sum(iv(r, k) for r in rows) for k in count_keys}

    max_dp = max(math.hypot(fv(r,'deltaPx'), fv(r,'deltaPy')) for r in rows)
    max_dke = max(abs(fv(r,'deltaKineticEnergy')) for r in rows)
    last = rows[-1]

    unsupported_parts = (
        s['unsupportedInvalidBath'] + s['unsupportedInvalidDonorGroup'] +
        s['unsupportedNoReceiverMass'] + s['unsupportedNormalCancellation'] +
        s['unsupportedGroupNotOutward'])
    unsupported_partition = unsupported_parts == s['unsupportedReflections']
    bath_partition = s['bathAlphaGEHalf'] + s['bathAlphaLTHalf'] == s['crossings']
    support_bath_partition = (
        s['supportExitBathAlphaGEHalf'] + s['supportExitBathAlphaLTHalf'] == s['supportExitCrossings'])
    bounds_ok = (
        s['appliedStillOutwardRelative'] <= s['appliedReflections'] and
        s['appliedStillRelativeExit'] <= s['appliedReflections'] and
        s['appliedStillAbsoluteExit'] <= s['appliedReflections'])
    conservative = max_dp <= 1e-9 and max_dke <= 1e-9 and math.isfinite(max_dp) and math.isfinite(max_dke)
    structural = unsupported_partition and bath_partition and support_bath_partition and bounds_ok and conservative

    print('===== 0493x9v KINETIC ESCAPE-PATH DIAGNOSTIC =====')
    print(f'file={path}')
    print(f"rows={len(rows)} lastStep={iv(last,'step')} reflectionFraction={fv(last,'reflectionFraction'):.9g}")
    print(f"outerSupportSamples={s['outerSupportParticles']} sparseOuterLT3={s['outerSupportCellParticlesLT3']} "
          f"({pct(s['outerSupportCellParticlesLT3'],s['outerSupportParticles']):.3f}%)")
    print(f"crossings={s['crossings']} supportExit={s['supportExitCrossings']}")

    print('--- route A: halo cells become accepted support ---')
    print(f"detectorPredictedOuterTarget={s['detectorPredictedOuterTarget']} "
          f"missedOccupiedOuterTarget={s['missedOccupiedOuterTarget']} "
          f"({pct(s['missedOccupiedOuterTarget'],s['detectorPredictedOuterTarget']):.3f}%)")
    print(f"missedSparseOuterTargetLT3={s['missedSparseOuterTargetLT3']} "
          f"({pct(s['missedSparseOuterTargetLT3'],s['missedOccupiedOuterTarget']):.3f}% of occupied-target misses)")

    print('--- route B: no inward bath found ---')
    print(f"bathSearchFailures={s['bathSearchFailures']} "
          f"wouldExitUsingLocalMean={s['bathSearchFailureWouldExitLocal']} "
          f"({pct(s['bathSearchFailureWouldExitLocal'],s['bathSearchFailures']):.3f}%)")

    print('--- route C: bath is not physical bulk alpha>=0.5 ---')
    print(f"bathAlpha>=0.5={s['bathAlphaGEHalf']} bathAlpha<0.5={s['bathAlphaLTHalf']} "
          f"outerBathFraction={pct(s['bathAlphaLTHalf'],s['crossings']):.3f}% partitionOK={int(bath_partition)}")
    print(f"supportExit bathAlpha>=0.5={s['supportExitBathAlphaGEHalf']} "
          f"bathAlpha<0.5={s['supportExitBathAlphaLTHalf']} "
          f"outerBathFraction={pct(s['supportExitBathAlphaLTHalf'],s['supportExitCrossings']):.3f}% "
          f"partitionOK={int(support_bath_partition)}")

    print('--- route D: detector relative path vs actual x+v*dt path ---')
    print(f"absoluteSupportExitCandidates={s['absoluteSupportExitCandidates']} "
          f"missedRelativeButAbsoluteExit={s['missedRelativeButAbsoluteExit']} "
          f"({pct(s['missedRelativeButAbsoluteExit'],s['absoluteSupportExitCandidates']):.3f}%)")

    print('--- route E: selected reflection cannot be applied ---')
    print(f"selected={s['selectedReflections']} applied={s['appliedReflections']} "
          f"unsupported={s['unsupportedReflections']} "
          f"({pct(s['unsupportedReflections'],s['selectedReflections']):.3f}%)")
    print('unsupportedReasons='
          f"invalidBath:{s['unsupportedInvalidBath']},"
          f"invalidDonorGroup:{s['unsupportedInvalidDonorGroup']},"
          f"noReceiverMass:{s['unsupportedNoReceiverMass']},"
          f"normalCancellation:{s['unsupportedNormalCancellation']},"
          f"groupNotOutward:{s['unsupportedGroupNotOutward']} "
          f"partitionOK={int(unsupported_partition)}")

    print('--- route F: reflection applied but particle can still move outward ---')
    print(f"appliedStillOutwardRelative={s['appliedStillOutwardRelative']}/{s['appliedReflections']} "
          f"({pct(s['appliedStillOutwardRelative'],s['appliedReflections']):.3f}%)")
    print(f"appliedStillRelativeExit={s['appliedStillRelativeExit']}/{s['appliedReflections']} "
          f"({pct(s['appliedStillRelativeExit'],s['appliedReflections']):.3f}%)")
    print(f"appliedStillAbsoluteExit={s['appliedStillAbsoluteExit']}/{s['appliedReflections']} "
          f"({pct(s['appliedStillAbsoluteExit'],s['appliedReflections']):.3f}%)")
    print(f"lastPostRelativeNormalMean={fv(last,'postRelativeNormalSpeedMean'):.6g} "
          f"lastPositivePostMean={fv(last,'postOutwardRelativeNormalSpeedMean'):.6g}")

    print(f'max|deltaP|={max_dp:.6e} max|deltaKE|={max_dke:.6e} conservative={int(conservative)}')

    # Rank the observable leakage mechanisms by normalized prevalence. This is
    # intentionally descriptive, not a physics PASS/FAIL criterion.
    mechanisms = [
        ('occupied-halo target accepted', ratio(s['missedOccupiedOuterTarget'], s['detectorPredictedOuterTarget'])),
        ('bath search failure with local predicted exit', ratio(s['bathSearchFailureWouldExitLocal'], s['bathSearchFailures'])),
        ('support-exit bath remains alpha<0.5', ratio(s['supportExitBathAlphaLTHalf'], s['supportExitCrossings'])),
        ('relative detector misses absolute empty-cell exit', ratio(s['missedRelativeButAbsoluteExit'], s['absoluteSupportExitCandidates'])),
        ('selected reflection unsupported', ratio(s['unsupportedReflections'], s['selectedReflections'])),
        ('applied reflection still outward relative', ratio(s['appliedStillOutwardRelative'], s['appliedReflections'])),
        ('applied reflection still predicts relative exit', ratio(s['appliedStillRelativeExit'], s['appliedReflections'])),
    ]
    mechanisms.sort(key=lambda kv: kv[1], reverse=True)
    print('dominantNormalizedSignals:')
    for name, val in mechanisms[:5]:
        print(f'  {val:.6f}  {name}')
    print(f'structuralDiagnosticConsistency={"PASS" if structural else "FAIL"}')


if __name__ == '__main__':
    main()

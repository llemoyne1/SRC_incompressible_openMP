#!/usr/bin/env python3
"""Analyze the first active Q6-G-F Laplace static-drop test (0493x9d)."""
from __future__ import annotations
import argparse, csv, json, math
from pathlib import Path


def rows(path: Path):
    if not path.exists():
        raise SystemExit(f"missing CSV: {path}")
    with path.open(newline='') as f:
        out=list(csv.DictReader(f))
    if not out:
        raise SystemExit(f"empty CSV: {path}")
    return out


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--capillary',type=Path,required=True)
    ap.add_argument('--species',type=Path,required=True)
    ap.add_argument('--json',type=Path,required=True)
    ap.add_argument('--liquid-type',type=int,required=True)
    ap.add_argument('--sigma',type=float,required=True)
    ap.add_argument('--radius',type=float,required=True)
    ap.add_argument('--thermal-pressure',type=float,required=True)
    args=ap.parse_args()
    cr=rows(args.capillary)
    c=cr[-1]
    step=int(float(c['step']))
    kmean=float(c['curvatureMean']); kstd=float(c['curvatureStd'])
    pmean=float(c['laplacePressureMean']); pstd=float(c['laplacePressureStd'])
    expected_k=1.0/args.radius
    expected_p=args.sigma*expected_k
    rel_k=(kmean-expected_k)/expected_k if expected_k else math.nan
    rel_p=(pmean-expected_p)/expected_p if expected_p else 0.0

    sr=rows(args.species)
    liquid=[r for r in sr if int(float(r['type']))==args.liquid_type]
    if not liquid:
        raise SystemExit(f'liquid type {args.liquid_type} missing from species diagnostics')
    final=max(liquid,key=lambda r:int(float(r['step'])))
    mean_vx=float(final['meanVx']); mean_vy=float(final['meanVy'])
    com_speed=math.hypot(mean_vx,mean_vy)
    pressure_ratio=expected_p/args.thermal_pressure if args.thermal_pressure>0 else math.nan
    status='PASS-structural'
    if not (int(float(c['crossingFaces']))>0 and int(float(c['validCurvatureFaces']))>0):
        status='FAIL-structural'
    vals=[kmean,kstd,pmean,pstd,mean_vx,mean_vy,com_speed]
    if not all(math.isfinite(v) for v in vals):
        status='FAIL-structural'
    report=dict(status=status,step=step,sigma=args.sigma,radius=args.radius,
                exactCurvature=expected_k,curvatureMean=kmean,curvatureStd=kstd,
                relativeCurvatureMeanError=rel_k,expectedLaplacePressure=expected_p,
                capillaryBoundaryPressureMean=pmean,capillaryBoundaryPressureStd=pstd,
                relativeBoundaryPressureMeanError=rel_p,thermalPressure=args.thermal_pressure,
                laplaceToThermalPressureRatio=pressure_ratio,
                liquidMeanVx=mean_vx,liquidMeanVy=mean_vy,liquidComSpeed=com_speed,
                note='x9d first active boundary-jump audit; solution-pressure/spurious-cell-flow qualification follows')
    args.json.parent.mkdir(parents=True,exist_ok=True)
    args.json.write_text(json.dumps(report,indent=2)+'\n')
    print('[0493x9d-analysis] '
          f'status={status} step={step} sigma={args.sigma:.8g} '
          f'kMean={kmean:.8g} kExact={expected_k:.8g} kErr={100*rel_k:.3f}% '
          f'dPcap={pmean:.8g} dPLaplace={expected_p:.8g} dPErr={100*rel_p:.3f}% '
          f'dP/pThermal={100*pressure_ratio:.4f}% '
          f'COM=({mean_vx:.3e},{mean_vy:.3e}) |COM|={com_speed:.3e}')
    print(f'[0493x9d-analysis] report={args.json}')
    return 0 if status.startswith('PASS') else 2

if __name__=='__main__':
    raise SystemExit(main())

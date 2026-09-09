#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument('csv')
ap.add_argument('--mode', choices=('static','dripping'), required=True)
ap.add_argument('--dt', type=float, default=0.002)
args = ap.parse_args()

p = Path(args.csv)
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10l-check] ERROR empty CSV')

def F(r,k):
    try: return float(r.get(k,0) or 0)
    except Exception: return 0.0

def I(r,k): return int(F(r,k))

def T(r):
    if 'time' in r and str(r.get('time','')).strip():
        return F(r,'time')
    return I(r,'step') * args.dt

valid = [r for r in rows if I(r,'preWallVelocityCells') > 0]
tip_valid = [r for r in rows if I(r,'preWallLowerTipCells') > 0]
if not valid:
    raise SystemExit('[0493x10l-check] ERROR no pre-wall interface velocity samples')

n = sum(I(r,'preWallVelocityCells') for r in valid)
vn_sum = sum(F(r,'preWallVnSum') for r in valid)
vn_sq = sum(F(r,'preWallVnSqSum') for r in valid)
abs_sum = sum(F(r,'preWallAbsVnSum') for r in valid)
pos = sum(I(r,'preWallPositiveVnCells') for r in valid)
neg = sum(I(r,'preWallNegativeVnCells') for r in valid)
mass = sum(F(r,'preWallVelocityMassSum') for r in valid)
mass_vn = sum(F(r,'preWallMassVnSum') for r in valid)
mean_vn = vn_sum/n
rms_vn = math.sqrt(max(0.0, vn_sq/n))
mean_abs = abs_sum/n
mass_mean_vn = mass_vn/mass if mass > 0 else 0.0

nt = sum(I(r,'preWallLowerTipCells') for r in tip_valid)
tip_vn_sum = sum(F(r,'preWallLowerTipVnSum') for r in tip_valid)
tip_vn_sq = sum(F(r,'preWallLowerTipVnSqSum') for r in tip_valid)
tip_abs_sum = sum(F(r,'preWallLowerTipAbsVnSum') for r in tip_valid)
tip_mass = sum(F(r,'preWallLowerTipMassSum') for r in tip_valid)
tip_mass_vn = sum(F(r,'preWallLowerTipMassVnSum') for r in tip_valid)
tip_pos = sum(I(r,'preWallLowerTipPositiveVnCells') for r in tip_valid)
tip_neg = sum(I(r,'preWallLowerTipNegativeVnCells') for r in tip_valid)
tip_mean = tip_vn_sum/nt if nt else 0.0
tip_rms = math.sqrt(max(0.0, tip_vn_sq/nt)) if nt else 0.0
tip_mean_abs = tip_abs_sum/nt if nt else 0.0
tip_mass_mean = tip_mass_vn/tip_mass if tip_mass > 0 else 0.0

area0 = F(rows[0],'preWallAlphaArea')
area1 = F(rows[-1],'preWallAlphaArea')
area_rel = (area1-area0)/area0 if area0 else 0.0

# Observed lower-tip motion over audit rows.  Outward at the lower tip is
# downward, so outward speed is -dy/dt.
tip_series = [(T(r), F(r,'preWallLowerTipY')) for r in tip_valid]
obs_speeds = []
for (t0,y0),(t1,y1) in zip(tip_series, tip_series[1:]):
    dt = t1-t0
    if dt > 0:
        obs_speeds.append(-(y1-y0)/dt)
obs_mean = sum(obs_speeds)/len(obs_speeds) if obs_speeds else 0.0
obs_rms = math.sqrt(sum(v*v for v in obs_speeds)/len(obs_speeds)) if obs_speeds else 0.0
tip_y0 = tip_series[0][1] if tip_series else 0.0
tip_y1 = tip_series[-1][1] if tip_series else 0.0

net_flux_rows = [F(r,'preWallNetNormalFluxProxy') for r in valid]
mean_net_flux = sum(net_flux_rows)/len(net_flux_rows)
length_rows = [F(r,'preWallInterfaceLengthProxy') for r in valid]
mean_length = sum(length_rows)/len(length_rows)

print('===== 0493x10l PRE-WALL INTERFACE DIAGNOSTICS =====')
print(f'file={p} mode={args.mode} rows={len(rows)} lastStep={I(rows[-1],"step")}')
print('--- whole alpha=.5 interface, AFTER Q6/B1 and BEFORE kinetic wall ---')
print(f'velocitySamples={n} meanVn={mean_vn:.9g} rmsVn={rms_vn:.9g} '
      f'mean|Vn|={mean_abs:.9g} massWeightedMeanVn={mass_mean_vn:.9g}')
print(f'positiveFraction={(pos/n if n else 0):.6%} negativeFraction={(neg/n if n else 0):.6%}')
print(f'meanNetNormalFluxProxy={mean_net_flux:.9g} meanInterfaceLengthProxy={mean_length:.9g}')
print(f'alphaArea first={area0:.9g} last={area1:.9g} relativeDrift={area_rel:+.6%}')
print('--- lower tip (lowest interface row + 2-cell liquid-side band) ---')
print(f'tipSamples={nt} tipMeanVn={tip_mean:.9g} tipRmsVn={tip_rms:.9g} '
      f'tipMean|Vn|={tip_mean_abs:.9g} tipMassWeightedMeanVn={tip_mass_mean:.9g}')
print(f'tipPositiveFraction={(tip_pos/nt if nt else 0):.6%} '
      f'tipNegativeFraction={(tip_neg/nt if nt else 0):.6%}')
print(f'tipY first={tip_y0:.9g} last={tip_y1:.9g} '
      f'observedOutwardTipSpeedMean={obs_mean:.9g} observedOutwardTipSpeedRms={obs_rms:.9g}')

if args.mode == 'static':
    ratio = abs(mean_vn)/max(rms_vn,1e-30)
    print(f'staticSignedToRmsRatio={ratio:.6g}')
    print('staticHypothesis=SUPPORTED' if ratio < 0.15 and abs(area_rel) < 0.02
          else 'staticHypothesis=REVIEW')
else:
    ratio = obs_mean/tip_mean if abs(tip_mean) > 1e-30 else 0.0
    print(f'observedToPredictedTipSpeedRatio={ratio:.6g}')
    if tip_mean > 0.005 and obs_mean < 0.25*tip_mean:
        print('movingWallHypothesis=SUPPORTED_Q6_PREDICTS_OUTWARD_TIP_BUT_CURRENT_INTERFACE_BARELY_ADVANCES')
    elif tip_mean > 0.005:
        print('movingWallHypothesis=Q6_PREDICTS_OUTWARD_TIP_AND_INTERFACE_ALREADY_ADVANCES')
    else:
        print('movingWallHypothesis=NOT_SUPPORTED_PREWALL_Q6_TIP_SPEED_NOT_CLEARLY_OUTWARD')

print('physicsModification=NONE_PASSIVE_DIAGNOSTICS_ONLY')

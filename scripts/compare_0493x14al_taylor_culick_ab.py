#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--liquid-root", type=Path, required=True)
ap.add_argument("--liquid-gas-root", type=Path, required=True)
a = ap.parse_args()

def load(root):
    p = root/"analysis_0493x14al"/"taylor_culick_summary.json"
    if not p.exists():
        raise SystemExit(f"missing {p}")
    return json.loads(p.read_text())

L, LG = load(a.liquid_root), load(a.liquid_gas_root)

def meta(root):
    js=list((root/'init').glob('*.smpcd.json'))
    if len(js)!=1: raise SystemExit(f'expected one init metadata JSON under {root}/init')
    return json.loads(js[0].read_text())
mL,mLG=meta(a.liquid_root),meta(a.liquid_gas_root)
shaL=mL.get('liquidInitialCanonicalSHA256'); shaLG=mLG.get('liquidInitialCanonicalSHA256')
if not shaL or shaL!=shaLG:
    raise SystemExit(f'PAIRING FAILURE: liquid initial SHA differs: {shaL} vs {shaLG}')
gL = float(L["mainQ50"]["Gtc"]); gLG = float(LG["mainQ50"]["Gtc"])
uL = float(L["mainQ50"]["uMean"]); uLG = float(LG["mainQ50"]["uMean"])
ratio = gLG/gL
hist = float(L["historicalQualifiedGtc"])
out = {
    "GtcLiquidCurrentCodeHistoricalPoint": gL,
    "GtcLiquidGasSameLiquidPoint": gLG,
    "pairedGasToLiquidRatio": ratio,
    "pairedGasEffectPercent": 100*(ratio-1),
    "Uliquid": uL, "UliquidGas": uLG,
    "historicalQualifiedGtc": hist,
    "liquidInitialCanonicalSHA256": shaL,
    "liquidVsHistoricalPercent": 100*(gL/hist-1),
}
root = a.liquid_gas_root.parent
p = root/"0493x14al_tc_historical_ab_comparison.json"
p.write_text(json.dumps(out, indent=2)+"\n")
print("===== 0493x14al PAIRED TC COMPARISON =====")
print(f"liquid initial SHA256                            = {shaL} (IDENTICAL A/B)")
print(f"G_TC liquid(current code, historical x13h point) = {gL:.9g}")
print(f"G_TC liquid+gas(same liquid point)               = {gLG:.9g}")
print(f"historical qualified liquid G_TC                 = {hist:.9g}")
print(f"liquid/current vs historical                     = {100*(gL/hist-1):+.4f}%")
print(f"paired (liquid+gas)/liquid                       = {ratio:.9g}")
print(f"paired gas effect                                = {100*(ratio-1):+.4f}%")
print(f"comparison JSON                                  = {p}")

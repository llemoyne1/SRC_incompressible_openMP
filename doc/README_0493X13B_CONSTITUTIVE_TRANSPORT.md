# 0493x13b — constitutive SRC transport map

Purpose: characterize transport coefficients independently of any splash/JFM application and independently of turbulence in later simulations. **No solver/source modification.**

## H — transverse constitutive viscosity

Pure mode `u_x(y)=U0 sin(2 pi y/Ly)`, so `div u=0` and `(u.grad)u=0` identically. Default amplitudes are 0.05, 0.025, 0.0125 at 64 cells/wavelength. The measured `nuT` is the coefficient used in `Re=UL/nuT` once amplitude/wavelength plateaux are established.

Default grid: 32x64 cells. Optional non-locality check: `SHEAR_NY_LIST=64,128`; physical duration scales linearly (12 -> 24) rather than quadratically to keep the qualification affordable.

## C — longitudinal response

Standing density modes use the x13b-C fractional/conservative state generator `generate_0493x13b_sound_state_fractional.py` and the existing 0493w1 cumulative continuity/momentum regression. It returns `c_s` and `nuL`. Default density amplitudes: 0.02, 0.04, 0.08, wavelength 64 cells. Replicate count is scaled as `max(3,ceil(60/gamma))`, so low-gamma cases receive more thermal realizations at nearly constant aggregate particle count. The generator preserves the exact global particle count while resolving weak x-density amplitudes through integer column populations rather than deterministic per-cell rounding.

Optional wavelength check: `SOUND_NX_LIST=64,128`; physical observation time scales linearly with wavelength to preserve acoustic cycles.

## Gamma axis

At the A1 point `(angle=120 deg, lambda/h=0.48)`, x13b adds gamma = 6, 8, 10, 14 to the existing gamma=20 reference. This is a cost/physics axis: SRD positioning predicts almost unchanged viscosity across this range, so gamma=6 would be especially valuable if the measured constitutive coefficients remain valid.

## Recommended execution order

1. `bash scripts/check_0493x13b_constitutive_transport.sh`
2. Preflight H: `PREFLIGHT_ONLY=1 bash scripts/run_0493x13b_H_constitutive_shear.sh`
3. Run H default (64-cell wavelength): `LIVE_PROGRESS=1 bash scripts/run_0493x13b_H_constitutive_shear.sh`
4. Preflight/run C default (64-cell wavelength).
5. Inspect `runs/0493x13b_constitutive_transport/analysis/` before requesting 128-cell wavelength tests. Do not launch the 128-cell H branch blindly: shear relaxation cost grows rapidly with wavelength.

Outputs: `shear_runs`, `shear_summary`, `longitudinal_runs`, `longitudinal_summary`, and `constitutive_transport_map` CSVs.

## Default campaign size

The default 64-cell H+C campaign is about `1.84e9` particle-steps in total. H durations are not fixed blindly: they target about 1.4 SRD-predicted e-folds, clipped to 4--28 physical time units. This keeps A0 and the low-gamma A1 family inexpensive while preserving enough decay for the high-flight probes. The exact planning table is `doc/0493x13b_default_cost_plan.csv`.

## x13b-C fix1 — low-gamma fractional sound initialization

The first C run exposed deterministic occupancy quantization in the legacy 0493w1 sound-state generator: weak requested amplitudes could become exactly zero at low gamma. x13b-C now uses `generate_0493x13b_sound_state_fractional.py`, which performs conservative systematic residual rounding on x-column populations and records the realized Fourier stimulus in per-replicate JSON metadata. The C summary reports the smallest **usable** PASS/REVIEW amplitude rather than blindly treating the smallest requested amplitude as valid. The C runner also emits an explicit `CAMPAIGN COMPLETE` marker after final analysis.

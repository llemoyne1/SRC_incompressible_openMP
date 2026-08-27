# 0493x13f — G08 local transport optimization

SRC-only campaign tooling. No `src/` or `include/` modification.

## Goal
Reduce the long-wave transverse viscosity below the qualified G08 anchor
`gamma=8, alpha=120 deg, lambda/h=0.48`, while preserving clean Newtonian
transverse decay and wavelength convergence.

The x13d anchor is approximately:
- `nuT = 5.3285e-4` at Ny256,
- `cs = 0.355448`,
- `H_h = cs*h/nuT ≈ 2.606`.

The local screen covers:
- alpha = 120,130,140,150 deg
- lambda/h = 0.48,0.56,0.64,0.72,0.80
- gamma = 8
- U0 = 0.05
- Ny = 128
- 2 paired seeds.

The SRD proxy predicts a possible minimum near alpha=150 deg, lambda/h=0.80,
`nuSRD ≈ 3.94e-4`, but this is only a positioning model. x13a already showed
that large-angle/large-flight transport can depart strongly from the SRD proxy,
so measured shear response decides.

## Stage 1
Run:
```bash
PREFLIGHT_ONLY=1 bash scripts/run_0493x13f_S1_G08_local_screen.sh
LIVE_PROGRESS=1 bash scripts/run_0493x13f_S1_G08_local_screen.sh
```
Outputs:
- `analysis/S1_runs_0493x13f.csv`
- `analysis/S1_screen_summary_0493x13f.csv`
- `analysis/S1_shortlist_0493x13f.csv`

The shortlist contains the anchor plus the three cleanest low-viscosity points.
Selection uses measured `nuT`, paired seeds versus the anchor, fit quality, CV,
and a broad measured/SRD consistency guard. It does not assume the SRD proxy is
physically exact.

## Stage 2
Run only after S1:
```bash
PREFLIGHT_ONLY=1 bash scripts/run_0493x13f_S2_G08_local_qualification.sh
LIVE_PROGRESS=1 bash scripts/run_0493x13f_S2_G08_local_qualification.sh
```
Stage 2 uses four paired seeds at Ny128 and Ny256. The first two Ny128 seeds are
reused from S1; only the missing Ny128 seeds and all Ny256 runs are executed.

Outputs:
- `analysis/S2_runs_0493x13f.csv`
- `analysis/S2_wavelength_summary_0493x13f.csv`
- `analysis/S2_final_qualification_0493x13f.csv`

The final table includes long-wave locality, viscosity gain versus the anchor,
an `H_h` proxy using the x13d anchor sound speed, and the characteristic-cell
count required for Re=1e4 at several Mach numbers.

## Important compressible caveat
`H_h` in x13f is initially a proxy because `cs` is held at the x13d G08-anchor
value. If the winning `(alpha,lambda/h)` differs from the anchor, requalify
`cs` and `nuL` with the damped-mode protocol before using that point as a
compressible reference or before rerunning the x13e Mach-reach campaign.

# Prompt for next chat — SRC/MPCD inlet/outlet continuation

We continue development of the C++ SRC/MPCD repository `SRC_incompressible_openMP`, currently on branch `feature/inlet-outlet` unless explicitly stated otherwise.

Imperative constraints:

- Never provide `.patch` files.
- Provide only differential archives named `*_files_only.zip`, containing modified/added files only.
- For any code modification, start only from a zip or commit explicitly provided in the current chat.
- Keep the classic compressible mode available.
- Do not break existing periodic/channel validations.
- Prefer the existing generic elliptic operator; do not add FFT-specific inlet/outlet paths.
- New markdown documentation belongs in `doc/`, except root `README.md` if explicitly requested.

Validated inlet/outlet state at the end of the previous chat:

1. Hard-cell-density inlet and passive/free outlet can be stable in open channels.
2. Q6/Q9/virial inlet/outlet must remain active up to the open boundaries:
   - `q9OpenBoundaryExclusionCells = 0`
   - `virialOpenBoundaryExclusionCells = 0`
   Historical nonzero open-boundary exclusion created an active/inactive interface behaving like a numerical wall near the outlet.
3. The nominal Q9 correction limiter is:
   - `q9CorrectionLimiterMode = thermal_soft`
   - `q9CorrectionVelocityLimiterOverThermal = 0.5`
   This gives `dU_limit = 0.025` for `kBT = 0.0025` and prevents ballistic Q9 kicks without suppressing Q9.
4. Q9 low-mass thresholds are gamma-relative:
   - `q9LowMassRampStartOverGamma = 0.05`
   - `q9LowMassRampEndOverGamma = 0.40`
   - `q9MassFloorForCorrectionOverGamma = 0.40`
   - `q9MinCellMassForCorrectionOverGamma = 0.40`
5. Inlet velocity ramping is part of the nominal setup:
   - `inletVelocityRampEnable = true`
   - `inletVelocityRampProfile = smoothstep`
   - ramp applied coherently to particle hard inlet, Q6 flux, and Q9 mass flux.
6. Validated configurations without immersed internal solids:
   - full inlet/outlet + slip/specular top/bottom walls + Q9+virial excl0: clean plug-flow baseline;
   - full inlet/outlet + VP/no-slip top/bottom walls + `inletVelocitySpatialProfile = poiseuille_y_mean`: strong validation, stable mass/flux/temperature and high-quality parabolic profile;
   - full inlet/outlet + VP/no-slip + `inletVelocitySpatialProfile = flat_taper_y`, `inletVelocityWallTaperCells = 2.0`: stable developing-flow variant; wall pockets reduced and outlet band absent.
7. Strict flat inlet with VP/no-slip walls is stable but produces wall-attached pockets that degrade global statistics; treat it as a stress test, not nominal validation.
8. Segmented inlet/outlet apertures are implemented and useful for future slot/nozzle cases, but they are physical partial-open geometries and should not be used to fix canonical Poiseuille validation.
9. Immersed-solid/obstacle runs revealed a separate problem: Q9/virial around solids needs a dedicated face/cell masked treatment. The next solid-focused work should be on a separate branch such as `feature/q9-immersed-solid-boundary`.

Most recent documentation patch proposed:

- `doc/README_0090_INLET_OUTLET_VALIDATION_STATUS.md`
- `doc/NEXT_CHAT_PROMPT_0090.md`

Suggested commit for closing this inlet/outlet validation step:

```bash
git add doc/README_0090_INLET_OUTLET_VALIDATION_STATUS.md doc/NEXT_CHAT_PROMPT_0090.md
git commit -m "0090 document validated inlet-outlet configuration"
```

Likely next tasks:

- final root `README.md` update if desired;
- optional cleanup of runner naming so tapered-flat and Poiseuille-profile cases have distinct labels;
- create a dedicated branch/chat for immersed-solid Q9/virial boundary treatment;
- or implement a physically documented slot/nozzle validation using segmented apertures, separate from canonical full-channel validation.

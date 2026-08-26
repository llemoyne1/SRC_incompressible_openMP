# 0491h runner refresh: run_ok, segmented injection livevis and full campaign

Scope:
- `scripts/src_mpcd_run_common_0434.sh` keeps the existing `run_ok*` structure but
  now selects the livevis 0486 build helper when the target binary name is livevis.
- Default livevis control files are written under the run root, unless
  `LIVE_VIS_CONTROL_FILE` is set explicitly by the user.
- CUDA flags are cleared more completely between modes, including Q6 resident
  thermostat and legacy inlet/outlet flags.

Segmented liquid/gas injection:
- `scripts/run_injection_type1_into_type2_segmented_0431_livevis.sh` defaults to
  a liquid species `type=1` injected into a gas species `type=2`.
- Default mass ratio is `LIQUID_TO_GAS_MASS_RATIO=10`, with gas mass `1.0` and
  liquid mass inferred as `10.0`.
- The Q6 species defaults are liquid incompressible and gas compressible:
  `LIQUID_Q6_STRENGTH=1.0`, `GAS_Q6_STRENGTH=0.0`.
- Useful overrides:
  `INTEG_PATH=src-q6`, `INTEG_PATH=src-q6-resampling`,
  `LIQUID_TYPE`, `GAS_TYPE`, `GAS_PARTICLE_MASS`, `INJECT_MASS`,
  `LIQUID_Q6_STRENGTH`, `GAS_Q6_STRENGTH`, `RIGHT_OUTLET_STYLE=segmented`.

0491h full validation:
- `scripts/run_0491h_species_q6_full_campaign.sh` launches the existing 0491h
  validator with `VALIDATION_PROFILE=full` by default.
- The full profile runs the path matrix on three seeds at 1000 steps and the
  long `src-q6` / `src-q6-resampling` checks at 10000 steps.
- For a short wrapper smoke test only, override `VALIDATION_PROFILE=software`.

Validation performed for this refresh:
- `bash -n` on the common helper, all `scripts/run_ok*.sh`, the 0431 livevis
  injection runner, and both 0491h launchers.
- Short `src-q6` smoke of the 0431 segmented liquid/gas injection with
  `NX=8 NY=4 GAMMA=4 STEPS=1`.
- Short software-profile smoke of `run_0491h_species_q6_full_campaign.sh`.

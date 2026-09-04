# 0493x14ah — corrected dynamic gas-drag benchmark

`0493x14ag` is retained as a rejected benchmark: the segmented hard-cell inlet/outlet did not maintain a physically usable compressible-gas carrier and the global gas velocity reversed.

`0493x14ah` changes **runner/tooling only**.  There is no C++/CUDA modification.

## Geometry and forcing

- `Lx x Ly = 2 x 1`, `512 x 256`, `h=1/256`.
- `x` periodic.
- solid stationary walls in `y`.
- no open boundary segments.
- no body acceleration.
- gas initialized with `u_x(y)=Umax0[1-(2y/Ly-1)^2]`, `Umax0=0.075`, nominal parabolic mean `0.05`.
- liquid drop `R/h=40` at `(1,0.5)`, initially at rest.
- x14ad physics unchanged.

This is intentionally a **transient Poiseuille carrier**, not a maintained steady solution.  With no inlet/outlet there is no reservoir capable of imposing the x14ag sign reversal.  Wall friction may decay the carrier.  The qualification asks whether the gas remains downstream long enough to transfer positive streamwise momentum to the drop.

## Run

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o 0493x14ah_corrected_dynamic_drag.zip -d .

bash -n scripts/run_ok_0493x14ah_drop_gas_transient_poiseuille_drag.sh
python3 -m py_compile \
  scripts/generate_0493x14ah_drop_gas_transient_poiseuille.py \
  scripts/analyze_0493x14ah_drop_gas_transient_poiseuille.py

bash scripts/run_ok_0493x14ah_drop_gas_transient_poiseuille_drag.sh
```

Default run is 4000 steps (`t=8`), `SUMMARY_EVERY=25`, restart dump every 1000 steps, LiveVis every step and WYSIWYR recording every 100 steps.

The analyzer reports:

- unwrapped `xCM(t)` and `dx/R`;
- `UdropX`, global `UgasX`, gas retention and any sign-reversal time;
- transverse migration;
- axis ratio;
- `PASS_DYNAMIC_DRAG`, `FAIL_CARRIER_REVERSAL`, `FAIL_UPSTREAM_OR_NONADVECTED_DROP`, or `REVIEW_TRANSVERSE_MIGRATION`.

The compact to return is:

```text
runs/0493x14ah_drop_gas_transient_poiseuille_drag_seed493191/
  0493x14ah_drop_gas_transient_poiseuille_drag_compact.tar.gz
```

## Optional x14af balance audit

The normal drag run keeps x14af OFF for representative timing.  If a short synchronous balance is later needed and x14af is already applied:

```bash
MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=1 \
STEPS=400 SUMMARY_EVERY=1 \
LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
bash scripts/run_ok_0493x14ah_drop_gas_transient_poiseuille_drag.sh
```

## Runner prerequisite fix

The runner explicitly defines the complete surface-interface parameter block before `suite_defaults_common_0434` / the common surface validation, including `PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION`, evaporation target, contact angle, x12a local radius and phase selectors. This avoids the preflight error `runner did not define required surface parameter` and keeps the physical values visible in the case-specific runner.

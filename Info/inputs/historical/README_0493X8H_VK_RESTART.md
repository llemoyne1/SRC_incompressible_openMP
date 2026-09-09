# 0493x8h — runner-only restart for long VK runs

This change deliberately **does not modify C++/CUDA** and **does not modify the
existing x8f runner**.

`tools/make_0493x8h_vk_restart_runner.py` reads the exact current local x8f
runner and creates `scripts/run_0493x8h_q6gf_vk_restart.sh`. This preserves any
local domain edits (for example `NX=1200`, `Lx=4.6875`) instead of replacing
them with an older generated copy.

## Restart contract

Set:

```bash
RESTART_STATE=/path/to/state_step_00003000.smpcd
```

The x8h runner then:

- uses the dump directly as `inputState` (no particle-state regeneration);
- auto-finds `params_used.kv` beside the dump unless `RESTART_PARAMS` is supplied;
- reads `darcyChiFile` from those source params unless `RESTART_CHI` is supplied;
- validates source `Lx`, `Ly`, `Nx`, `Ny`, and `dt`;
- validates the `.smpcd` header;
- validates every chi cell against current `(cx,cy,r)` and the current grid;
- copies only the small chi field into the new run root;
- infers `RESTART_FROM_STEP` from the dump filename; if the source is itself an x8h continuation, it automatically adds the previous global origin;
- records restart metadata/global end step in the new logs.

The executable still starts its local step/time counter from zero. This is a
**hydrodynamic restart**, not a bitwise-continuous RNG restart.

## Install

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
mkdir -p tools
cp make_0493x8h_vk_restart_runner.py tools/
python3 tools/make_0493x8h_vk_restart_runner.py
bash -n scripts/run_0493x8h_q6gf_vk_restart.sh
```

## Example continuation

```bash
RESTART_STATE=runs/<OLD_ROOT>/src-q6-g-f/output/state_step_00003000.smpcd \
STEPS=2000 \
BASE_RUN_ROOT=runs/<NEW_ROOT> \
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=1 \
bash scripts/run_0493x8h_q6gf_vk_restart.sh
```

If the current x8f runner contains `NX=1200`, `Lx=4.6875`, those values are
preserved automatically. If they were supplied only as environment overrides,
supply them again; strict validation rejects mismatches before launch.

Always use a new `BASE_RUN_ROOT` when `CLEAN_RUN_ROOT=1`.

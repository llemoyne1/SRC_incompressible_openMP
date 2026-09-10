0493x14av unified air-assisted atomizer runner — Neumann x9c/x9d-fix1/x9e

Purpose
-------
Replace the stack of experiment wrappers with one base runner selector.
No C++/CUDA code is modified by this package.

Default
-------
NEUMANN_PROFILE=x9e

Supported profiles
------------------
x9c       reference boundary physics, legacy workspace/pool path
x9d-fix1  same x9c physics + conservative resident workspace optimization
x9e       same x9c physics + x9d-fix1 + deleted-slot recycle/prefix fast path

Common physical closure for all three profiles
-----------------------------------------------
- gas: x8y pressure reservoir, 2 virtual layers by default
- coarse kinetic moments: 8 inward layers by default
- x8z no-macroscopic-backflow guard
- x9a zero full reservoir drift on backflow
- x9b liquid strict outflow (no incoming virtual liquid reservoir)
- x9c phase-support continuation at Neumann outlet

User knobs
----------
NEUMANN_PROFILE=x9c|x9d-fix1|x9e
NEUMANN_VIRTUAL_LAYERS=2
NEUMANN_COARSE_LAYERS=8
NEUMANN_TARGET_OCCUPANCY=""  # empty => resolved inletTargetOccupancy (= GAMMA)

The runner sanitizes historical experiment environment variables before setting
its own closure.  Default CASE_LABEL and run root include NEUMANN_PROFILE so
switching profiles with CLEAN_RUN_ROOT=1 cannot silently delete another profile.

Apply from repository root
--------------------------
git apply --check /path/unify_base_runner_neumann_x9e.patch
git apply /path/unify_base_runner_neumann_x9e.patch
bash -n scripts/run_ok_air_assisted_atomizer.sh

Examples
--------
# optimized candidate (default)
CLEAN_RUN_ROOT=1 bash scripts/run_ok_air_assisted_atomizer.sh

# explicit optimized 400x400 long run
NEUMANN_PROFILE=x9e Lx=1.5625 Ly=1.5625 NX=400 NY=400 STEPS=3000 \
DUMP_STATE_EVERY=500 RECORD_EVERY=100 CLEAN_RUN_ROOT=1 \
bash scripts/run_ok_air_assisted_atomizer.sh

# reference x9c with same physics
NEUMANN_PROFILE=x9c Lx=1.5625 Ly=1.5625 NX=400 NY=400 STEPS=3000 \
DUMP_STATE_EVERY=500 RECORD_EVERY=100 CLEAN_RUN_ROOT=1 \
bash scripts/run_ok_air_assisted_atomizer.sh

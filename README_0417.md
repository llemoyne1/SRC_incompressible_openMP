# 0417 initialInactiveSlots patch

Files-only archive. Copy/unzip at the repository root.

## Changed files

```text
include/simulation_params.h
include/particle_state.h
src/params_io_base.cpp
src/particle_state.cpp
src/main_src_mpcd_base.cpp
doc/INITIAL_INACTIVE_SLOTS_0417.md
```

## New parameter

```text
initialInactiveSlots = 0
```

Semantics are fixed to `ensure`: after `inputState` is read, the code ensures
that at least this many `Inactive` slots exist. Existing full `.smpcd` files are
not inflated if they already contain enough inactive slots.

## Build

Typical CUDA/livevis build:

```bash
MPCD_ENABLE_LIVE_VIS=1 OUT=build/src_mpcd_base_cuda_q6_resident_0400_livevis bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

Non-livevis build:

```bash
OUT=build/src_mpcd_base_cuda_q6_resident_0400 bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

## Run/restart usage

For inlet/outlet cases using compact active-only `.smpcd` inputs or dumps, add:

```text
initialInactiveSlots = ${INACTIVE_SLOTS}
dumpRoleFilter = fluid
summaryRoleFilter = fluid
```

Then a `dumpRoleFilter=fluid` dump can be used as the next `inputState` while
retaining a regenerated inactive reservoir at load time.

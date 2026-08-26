# 0435c equivalence override fix

The first equivalence matrix failed because the 0434 common helper overwrote
the environment override:

```bash
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
```

The pre-0435c reference binary then ran with shared_0251 thermostat consumption
enabled and correctly hit the stale-state guard.

This patch does not add a new flag. It only makes the existing environment
variables respect explicit user overrides by changing hard-coded exports like:

```bash
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
```

to:

```bash
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="${MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260:-1}"
```

Apply from repo root:

```bash
python3 apply_0435c_equivalence_override_fix.py
```

Then rerun the matrix and summary.

# 0492 / 0492a — refresh of `run_ok*.sh`

Base: `2fb9c30` (`0491h-fix1: deepen species-sensitive Q6 qualification`).

These patches update the interactive runners without changing C++/CUDA dynamics.

## Common contract

- default binary: `build/src_mpcd_base_cuda_q6_resident_livevis_0486`;
- `LIVE_PROGRESS=1` is exported even when it is only the script default;
- LiveVis controls are generated per run, including `particleTypeFilter`;
- `PREFLIGHT_ONLY=1` generates state, params, LiveVis and environment files, validates them, and skips the binary;
- every launch prints a topology-aware `[0492a-run-ok] preflight=PASS` line.

## Species-aware resampling

`SPECIES_RESAMPLING_ENABLE=true` activates, in resampling modes:

- mass closure CPU contract + CUDA implementation;
- typed population guard;
- species-composition empty refill;
- typed transfer planning on CUDA;
- generic mass recondition 0296 disabled;
- thermal renormalization disabled;
- legacy mass guard disabled.

The resident orchestration is selected by `SPECIES_RESIDENT_MODE`:

- `auto` (default): `fast` for fully periodic topology, `compatible` otherwise;
- `fast`: 0490m/0490n/0490p fast path, resident deposits, resident pool and strict device cell policy; rejected unless the topology is fully periodic;
- `validation`: 0490l strict CUDA plan/materializer/apply path, intended for reduced correctness tests;
- `compatible`: topology-compatible 0490h/i/j/k CUDA species modules with the legacy host orchestration retained around particle edits.

This distinction is required because the validated 0490m/0490n/0490p safety envelope is fully periodic. Wall, full-face I/O and segmented I/O runners must not silently enable that fast path.

Mono-species runners retain their previous generic resampling behavior because `SPECIES_RESAMPLING_ENABLE` defaults to `false`.

## Injection runner

`run_ok_injection_type1_into_type2_empty.sh` defaults to `src-q6-resampling`, registers both species, uses mass-closure strength 1 for both species, enables cell diagnostics, and keeps weighted species-Q6.

Its topology is `segmented`; therefore the default resolved resident mode is `compatible`, not 0490p `fast`. A reduced strict-CUDA test can be requested explicitly with:

```bash
SPECIES_RESIDENT_MODE=validation
```

Because this runner is explicitly named `_empty.sh`, its initial-domain default is now `empty`. Use `INITIAL_DOMAIN_MODE=full` to request the pre-filled liquid-into-gas case. Empty mode rejects non-resampling paths at preflight.

Live visualization can show total or one species by setting:

```bash
PARTICLE_TYPE_FILTER=-1  # total
PARTICLE_TYPE_FILTER=1   # injected liquid
PARTICLE_TYPE_FILTER=2   # background gas
```

## Recommended smoke

```bash
LIVE_PROGRESS=1 STEPS=20 NX=120 NY=40 GAMMA=6 \
INITIAL_DOMAIN_MODE=empty \
PREFLIGHT_ONLY=1 \
bash scripts/run_ok_injection_type1_into_type2_empty.sh
```

The preflight must report `topology=segmented speciesResident=compatible`. Then run the same reduced command with `PREFLIGHT_ONLY=0`.

## 0492b — separate vacuum fill from true liquid-into-gas injection

The former `run_ok_injection_type1_into_type2_empty.sh` starts with zero active
fluid particles. Inactive slots tagged as type 2 are storage only; they are not
an active gas phase. Therefore this runner now advertises and checks the actual
scenario: type-1 liquid injected into an empty domain.

A new wrapper provides the true two-species experiment:

```bash
LIVE_PROGRESS=1 bash scripts/run_ok_injection_type1_into_type2.sh
```

It starts from a type-2 gas-filled domain and injects type 1. The default phase
closure is now physically consistent with the labels:

- liquid type 1: closure strength 1;
- gas type 2: closure strength 0.

`check_injection_species_0492b.py` validates the initial state and the first/last
species-runtime rows. Optional mixed-cell qualification is enabled on compact
runs with:

```bash
SPECIES_CELL_DIAGNOSTICS_ENABLE=true \
REQUIRE_MIXED_CELL_AT_END=true \
bash scripts/run_ok_injection_type1_into_type2.sh
```

Cell diagnostics are disabled by default because their row count is
`summary_frames * Nx * Ny * speciesCount`; at 900x300 they can become very
large. The compact species runtime CSV remains enabled by default.

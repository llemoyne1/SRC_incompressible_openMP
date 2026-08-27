# 0493x13b-C fix1 — fractional/conservative longitudinal stimulus

Scope: **scripts and campaign tooling only**. No file under `src/` or `include/` is modified.

## Why this fix exists

The legacy 0493w1 sound-state generator allocates an integer number of particles in every collision cell. At low `gamma`, requested density amplitudes 0.02/0.04 can therefore be quantized to exactly zero. This was observed in the first x13b-C campaign (for example G06 produced identical states for 0.02, 0.04 and 0.08).

## New state generator

`scripts/generate_0493x13b_sound_state_fractional.py`

For each x-column it first targets

`Ncol_i = Ny * gamma * [1 + eps cos(k x_i)]`.

Column totals are converted to integers by unbiased systematic residual rounding while enforcing exactly

`sum_i Ncol_i = Nx * Ny * gamma`.

Each integer column population is then distributed as evenly as possible over `y`, with randomized placement of the remainder. Thus the weak x-density mode has resolution `1/(Ny*gamma)` rather than `1/gamma`, while global mass is exact and no coherent y-stripe is imposed.

The generator writes `sound_0493x13b.meta.json` beside each state. It records requested and realized Fourier amplitudes, total population, and min/max cell populations.

The guard in `check_0493x13b_constitutive_transport.sh` verifies that G06 at eps=0.02 is non-zero, conservative, and reproduced within 2% before any solver run.

## C runner changes

The default rerun is intentionally limited to the six fluids needed to repair the first C qualification:

`A0,A1,G06,G08,G10,G14`

with requested amplitudes `0.02,0.04,0.08`.

The solver's own `done` line still appears at the end of every sub-run. The campaign now emits a unique final line only after all groups, all replicates, and the final analysis:

`[0493x13b-C] CAMPAIGN COMPLETE ...`

and creates:

`runs/0493x13b_constitutive_transport/C_longitudinal/CAMPAIGN_COMPLETE_0493x13b_C`

## Analyzer changes

The longitudinal run CSV now includes the realized stimulus amplitude from every replicate. The longitudinal summary no longer labels an invalid smallest requested amplitude as the constitutive low-amplitude result: it reports both `requestedLowestAmplitude` and `lowestUsableAmplitude`, selecting the smallest PASS/REVIEW result for the latter.

## Recommended rerun

Because the old C states are not physically the requested weak perturbations, rerun C with the corrected generator rather than mixing old and new C results:

```bash
bash scripts/check_0493x13b_constitutive_transport.sh
PREFLIGHT_ONLY=1 bash scripts/run_0493x13b_C_longitudinal_response.sh
LIVE_PROGRESS=1 bash scripts/run_0493x13b_C_longitudinal_response.sh
```

`CLEAN_ROOT=1` remains the default for C only; it does not erase `H_shear`.

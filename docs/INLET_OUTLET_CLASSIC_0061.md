# 0061 — classic particle-only inlet/outlet boundaries

This patch introduces the first inlet/outlet layer for the C++ SRC/MPCD core. It is intentionally restricted to `method=classic` and does not modify the Q6, Q9 or virial paths.

## Scope

Implemented boundary pairs:

- `bcLeft=inlet`, `bcRight=outlet` or the reversed x-pair;
- `bcBottom=inlet`, `bcTop=outlet` or the reversed y-pair;
- exactly one open axis at a time;
- the transverse axis may remain `periodic` or use a wall pair such as `solid/solid`.

The aliases `input` and `output` are accepted. `open` is treated as an outlet-like boundary.

When a particle crosses an outlet, it is recycled at the paired inlet. When a particle exits through the inlet side because of thermal backflow, it is also reset from the inlet reservoir. The particle count therefore remains constant. The inlet velocity is prescribed by face-specific parameters such as `inletUxLeft` and `inletUyLeft`. With `inletThermalNoise>0`, a Maxwellian fluctuation is sampled around this mean velocity using `inletKBT` or, if negative, `kBT`.

## Explicit non-scope

Open boundaries with Q6, Q9 and virial closure are deliberately rejected at validation time. They need prescribed normal fluxes and reservoir/sponge handling in the elliptic operators, which is the planned 0062–0064 work.

## Smoke validation

Generate the initial state from `matlab/`:

```matlab
generate_open_channel_classic_state('output','../initial_state_open_channel_64x32_g20_kbt0p01.smpcd');
```

Then run:

```bash
./scripts/run_open_channel_classic_inlet_outlet_smoke.sh
```

Basic acceptance criteria for 0061 are conservative:

- the executable starts with `bc=[L:inlet, R:outlet, B:solid, T:solid]`;
- `Np` and `totalMass` remain constant;
- `meanN` remains equal to the reference occupancy;
- `kBTEstimate` remains controlled when the thermostat is enabled;
- `hitsRight` becomes non-zero once particles reach the outlet, and those particles are recycled at the inlet without leaving the active domain.

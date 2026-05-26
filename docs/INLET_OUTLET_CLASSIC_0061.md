# 0061/0061b — classic particle inlet/outlet boundaries

## Scope

Patch 0061 introduced the first classic-only open-boundary path for the
`src_mpcd_base` executable. Patch 0061b updates that path to match the useful
legacy CUDA behaviour more closely:

- one open axis at a time;
- inlet/outlet pair only, e.g. `bcLeft=inlet`, `bcRight=outlet`;
- `method=classic` only;
- Q6, Q9 and virial open boundaries remain explicitly disabled until the later
  elliptic face-flux patches;
- particle count and total mass remain constant by recycling particles exiting
  the outlet back into the inlet reservoir.

This is intentionally a particle-level boundary condition. It does not yet set
an elliptic prescribed normal flux and must not be used as a Q6/Q9 validation.

## CUDA-like recycling model added in 0061b

The legacy CUDA VK path did not inject new particles from an infinite reservoir.
Instead, particles crossing the downstream outlet were recycled into a thin
upstream slab:

```text
x >= xMax  -> x = xMin + random(0, inletSlabCells*dx)
              y = random(yMin, yMax) if inletRandomizeTangential=true
              v = prescribed inlet velocity + optional thermal noise
```

The C++ path now implements the same idea for both possible open axes and inlet
orientations:

- left inlet / right outlet;
- right inlet / left outlet;
- bottom inlet / top outlet;
- top inlet / bottom outlet.

The parameter `inletReinjectBackflow` controls particles that cross back through
the inlet face. When true, they are re-injected into the inlet slab. When false,
they are simply clamped back inside the domain, matching the CUDA option used in
some VK runs.

## New parameters

```text
inletInjectionMode = cuda_recycle
```

Selects the current particle-only recycling strategy. `cuda_recycle` and its
alias `thin_slab` both mean thin-slab reinjection; the explicit key is present
so future alternatives can be added without changing parameter-file structure.

```text
inletSlabCells = 1.0
```

Thickness of the injection slab in local grid-cell units. For an x-open domain,
the physical slab thickness is approximately
`inletSlabCells * (xMax-xMin)/Nx`.

```text
inletRandomizeTangential = true
```

If true, randomizes the transverse coordinate on injection. This is recommended
for homogeneous inlet density and is equivalent to the CUDA `injectRandomY=1`
for an x-open domain.

```text
inletReinjectBackflow = true
```

If true, re-injects particles that cross the inlet face in the wrong direction.
If false, these particles are clamped at the inlet boundary without resetting
velocity.

Existing inlet velocity and temperature parameters remain available:

```text
inletUxLeft, inletUyLeft
inletUxRight, inletUyRight
inletUxBottom, inletUyBottom
inletUxTop, inletUyTop
inletKBT = -1.0
inletThermalNoise = 0.0 or 1.0
```

For a strict CUDA-like injection, use `inletThermalNoise=0.0`: particles are
injected with exactly the prescribed inlet velocity. The SRC collision and
optional thermostat then rebuild the thermal population inside the domain.

## Example cases

Two examples are provided.

```text
examples/params_open_channel_classic_inlet_outlet_smoke_64x32.kv
```

Pure recycling smoke test, without global mean-flow forcing. This primarily
checks conservation, temperature stability and population behaviour.

```text
examples/params_open_channel_classic_inlet_outlet_keepmean_64x32.kv
```

CUDA-like driven diagnostic with `keepMeanFlowEnable=true`. This is useful to
exercise the outlet quickly on a short run, but it is not by itself a physical
inlet validation because the mean velocity is enforced globally.

## MATLAB initialization

From the repository root:

```matlab
cd matlab
generate_open_channel_classic_state( ...
    'output', '../initial_state_open_channel_64x32_g20_kbt0p01.smpcd');
cd ..
```

## Bash execution

```bash
chmod +x scripts/run_open_channel_classic_inlet_outlet_smoke.sh
./scripts/run_open_channel_classic_inlet_outlet_smoke.sh
```

The script builds the executable and runs both 0061b examples.

## Expected first checks

For both examples:

- `Np` constant;
- `totalMass` constant;
- `method=classic`, `q6Applied=0`, `q9Applied=0`;
- controlled `kBTEstimate` if the thermostat is enabled;
- no monotone population blow-up in `stdN`, `minN`, `maxN`.

For the pure recycling smoke, the mean velocity can still decay if the run time
is short compared with the convective time `Lx/Uin`. The keep-mean diagnostic
should instead keep `meanVx` close to `targetMeanUx`, while exercising the same
recycling boundary.

## Negative validation

A Q6/Q9/virial open-boundary configuration must still fail validation in 0061b.
For example, changing `method=classic` to `method=q6` in one of the open-channel
files should stop with an explicit message that inlet/outlet is currently
particle-only and classic-only.

The next patch, 0062, should add the corresponding prescribed-normal-flux logic
inside the generic elliptic operator rather than bypassing it with an FFT or a
case-specific path.

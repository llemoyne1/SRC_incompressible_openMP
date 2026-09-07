# 0493x14an — planar gas jet normal to a liquid bath (2-D)

Tooling only. No C++/CUDA file is modified.

Files installed under `scripts/`:
- `run_0493x14an_planar_gas_jet_liquid_bath.sh` — runner;
- `generate_gas_jet_liquid_bath_2d.py` — initial liquid bath + barometric gas headspace;
- `analyze_gas_jet_liquid_bath_2d.py` — offline cavity depth/width/profile analysis from existing `.smpcd` dumps.

Default physical point uses the same resolved liquid/gas microscopic fluid as the successful multi-radius drop campaign:
- grid `512 x 256`, `h=1/256`, `gamma=20`;
- `dt=0.002`;
- liquid: `m=1`, `kBT=0.02`, projected by Q6-g-f;
- gas: `m=0.1`, `kBT=0.08`, compressible (`q6Strength=0`);
- surface tension `sigma=2560`;
- gravity `g_y=-0.5`;
- bath height `0.5`;
- top planar gas jet: width `32h=0.125`, speed `0.25`;
- jet velocity ramp from `t=1` to `t=2`;
- two side outlets on the same top face use Q6-g-f-supported `balanced_flux`;
- gas headspace starts from the isothermal barometric occupancy profile rather than a uniform gas.

The runner prints before launch:
- gas thermal flight per step;
- directed jet flight per step;
- their sum (hard stop above 0.8 cell/step);
- barometric scale height and top/bath density ratio;
- gas Weber number, liquid Bond number and jet Froude number based on jet width.

Coupling enabled, with explicit meanings in the runner:
- thermodynamic gas pressure;
- Laplace surface tension;
- qualified liquid-side kinetic support/relocalization;
- specular normal gas reflection;
- gas excess normal kinetic impulse transferred to liquid;
- local gas-traction projection onto the interface.

The global Q6-resultant closure is forced OFF because the bath is connected to solid/open boundaries.

## Install

From the repository root:

```bash
unzip -o 0493x14an_planar_gas_jet_liquid_bath_runner.zip
chmod +x scripts/run_0493x14an_planar_gas_jet_liquid_bath.sh \
         scripts/generate_gas_jet_liquid_bath_2d.py \
         scripts/analyze_gas_jet_liquid_bath_2d.py
```

## Fix1 note

`equilibrium_flux` is a SRC-classic outlet mode but is not accepted by the Q6-g-f segmented resident boundary family. Fix1 therefore uses `balanced_flux`, which is accepted by the Q6-g-f segmented path. The runner also rejects unsupported outlet modes before launching the binary.

## Preflight

```bash
PREFLIGHT_ONLY=1 bash scripts/run_0493x14an_planar_gas_jet_liquid_bath.sh
```

## First run

```bash
bash scripts/run_0493x14an_planar_gas_jet_liquid_bath.sh
```

Expected output root:

```text
runs/0493x14an_planar_gas_jet_liquid_bath_seed493205/
```

Return the compact archive printed at the end:

```text
0493x14an_planar_gas_jet_liquid_bath_compact.tar.gz
```

The compact archive deliberately excludes the large `.smpcd` restart states.

`./livevis_control.kv` is never generated, rewritten, copied or modified by these scripts.


## fix2 — segmented outlet compatibility

The default outlet mode is `neumann`. This is intentional: in the current source, the 0143 segmented-outlet parser accepts `neumann|hybrid|equilibrium_flux|forced_flux`, while the 0493x7f Q6-g-f segmented topology gate accepts `neumann|balanced_flux|balanced|hybrid`. The compatible intersection for this passive benchmark is therefore `neumann|hybrid`; `neumann` is selected to avoid adding a feedback/controller closure to the gas-jet qualification.


## fix3 — resident segmented boundary contract

The first runner versions used specular side/top faces. The CUDA persistent
segmented SRC collision subset requires static wall coupling on all four base
faces. The benchmark now follows the already-exercised top-same-face segmented
layout used by the existing dripping runner:

- `bcLeft=bcRight=bcBottom=bcTop=solid`;
- central top gas inlet and two top side outlets;
- `openBoundaryOutletMode=hybrid`, blend=0 and feedback=0;
- `inletThermalNoise=0`, required by the resident segmented path;
- `wallAccommodation=0`, so the solid faces are geometrically reflecting but
  collisionally slip/specular-like. This avoids imposing one arbitrary wall VP
  mass on both the liquid-contacting bottom and gas-contacting side/top walls.

No C++/CUDA code is modified.

## fix4 — local gas/impact analysis only

The physics and boundary conditions are unchanged from fix3.  The offline
analyzer no longer uses any whole-domain gas mean as a qualification observable.
It measures gas only in:

- an **incident-core band** one nozzle width wide, located by default at
  `etaFar + 1.5*Wjet`, to verify that a downward jet reaches the bath region;
- an **impact control volume** centred on the nozzle, total width `3*Wjet`,
  extending from one grid cell above the reconstructed interface to
  `1.5*Wjet` above it.

The new `analysis/gas_local_history.csv` reports local mean velocity, downward
mass fraction, local occupancy, nominal ideal-gas pressure proxy, normal thermal
and advective stresses, and separate downward/upward momentum-flux proxies.
The signed `DirectionalMomentumFluxProxy` is defined as downward minus upward,
so positive means downward-directed transport dominates locally.

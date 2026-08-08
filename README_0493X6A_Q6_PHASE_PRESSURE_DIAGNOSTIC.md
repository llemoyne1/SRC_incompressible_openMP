# 0493x6a — phase-aware gas-pressure diagnostic for Q6-g

## Purpose

0493x6a is the first implementation step after the 0493x5b liquid-gas
qualification.  It **does not change the Q6 physics**.  In particular,
`free_surface_masked` still solves with the historical zero-gauge Dirichlet
condition on liquid/exterior faces.

The patch formalizes the scalar solved by Q6 and constructs, on the resident
CUDA species-cell state, the gas pressure variable that a later coupled
interface condition can consume.

## Q6 variable

The resident Q6 solve is

```
Laplacian(phi) = -div(u*)
du = -grad(phi)
```

Therefore, for a constant-density incompressible phase,

```
phi = dt * p / rho_ref
```

up to an arbitrary pressure gauge constant.  A thermodynamic gas pressure must
be converted to this pressure potential before it is inserted into Q6.

## 0493x6a gas field

The existing species registry already distinguishes `phaseFamily=gas` and
`phaseFamily=liquid`.  0493x6a uploads that phase metadata into the Q6 resident
species workspace and, when the temporary diagnostic environment switch

```
MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=1
```

is enabled, aggregates every gas species in each cell.

The first pressure model is deliberately the equilibrium ideal-gas EOS:

```
p_g = N_g * kBT / A_cell
```

For the projected liquid reference density

```
rho_l,ref = M_l,ref / A_cell
```

the CUDA field is

```
phi_g = dt * p_g / rho_l,ref
      = dt * N_g * kBT / M_l,ref
```

The cancellation of `A_cell` is useful: the potential is constructed directly
from resident gas counts and the liquid reference-cell mass.

For several registered gas species, `N_g` is the sum of their particle counts.
The projected liquid reference mass is currently the sum of reference-cell
masses of registered liquid species with `q6StrengthDeclared>0`.  The current
0493x5b contract still requires a single directly projected liquid species, so
this aggregation is scaffolding for the later phase-aware path and does not
change present results.

## Interface audit

For every face separating the regularized liquid support from an in-domain
inactive liquid cell, the diagnostic evaluates the gas pressure potential at
the same half-cell interface used by the current free-surface operator, using
a centred interpolation of the two adjacent cell-centred gas values.  This
therefore also accounts for gas already present in a mixed active liquid cell.
Physical box-wall faces are not counted as liquid-gas faces.

It writes

```
output/cuda_phase_interface_pressure_0493x6a.csv
```

with face-weighted statistics for:

- gas particle count;
- EOS gas pressure;
- Q6 pressure potential `phi_g`;
- number of liquid/exterior faces.

This is intentionally an EOS diagnostic, not yet the full MPCD normal stress.
A later step will compare it to a kinetic/collisional stress estimator before
any final stress-based interface condition is adopted.

## Non-regression contract

With the diagnostic switch disabled, the only runtime change is upload of one
`phaseFamily` byte per registered species into the already allocated resident
species workspace.  No Q6 operator, support mask, force ordering, particle
correction, collision, boundary condition, Darcy/chi term, thermostat or
resampling rule is modified.

With the diagnostic enabled, one cell kernel builds `phi_g`, one interface
reduction is performed, and compact scalar statistics are downloaded.  The
field is **not consumed by the projection**.

## Qualification runner

Build the existing CUDA target, then run a short smoke first:

```bash
LIVE_PROGRESS=1 STEPS=20 \
  bash scripts/run_0493x6a_phase_pressure_diagnostic.sh
```

The 200-step comparison matching 0493x5b is:

```bash
LIVE_PROGRESS=1 STEPS=200 \
  bash scripts/run_0493x6a_phase_pressure_diagnostic.sh
```

The runner reuses the validated 0493x5b physical case and its existing liquid-
gas analyzer, then validates the pressure-potential identity with
`scripts/analyze_0493x6a_phase_pressure.py`.

## Next gate

If 0493x6a reproduces the x5b dynamics and the pressure-potential audit is
consistent, the next physical patch can use the resident `phi_g` field to test
an interface condition of the form

```
phi_liquid|Gamma = phi_g|Gamma
```

first in controlled static/weakly dynamic cases.  The SRC inter-species
momentum transfer must then be audited explicitly before that coupling is
accepted, to exclude double counting of the normal gas traction.

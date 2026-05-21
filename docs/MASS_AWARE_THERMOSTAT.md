# Mass-aware relative thermostat

This document describes the first thermostat implemented in the base SRC/MPCD
C++ executable. It is intended primarily for forced channel/Poiseuille runs,
where body acceleration and wall coupling inject heat into the particle
fluctuations.

## Runtime parameters

```text
thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0   # negative => inherit kBT
thermostatMinParticles = 3
thermostatEpsilon = 1.0e-30  # optional numerical guard
kBT = 0.01
```

`thermostatEnable = false` leaves the dynamics unchanged.

## Algorithm

After streaming, boundary handling and SRC/MPCD collision, the thermostat uses
the same shifted collision cell assignment as the just-completed collision. For
each cell, it computes the real-particle, mass-weighted center-of-mass velocity:

```text
u_c = sum_i(m_i v_i) / sum_i(m_i)
```

Only real particles are used in this thermostat average. Wall virtual particles
are not included in the thermostat center-of-mass velocity, because the
thermostat should not add or remove real-fluid momentum through the wall bath.

The relative kinetic energy in the cell is

```text
K_c = 0.5 * sum_i m_i |v_i - u_c|^2
```

For a two-dimensional cell with `N_c` real particles, the target kinetic energy is

```text
K_target = 0.5 * 2 * (N_c - 1) * kBT_target
```

where one translational degree of freedom per direction is removed by the local
center-of-mass constraint. Cells with fewer than `thermostatMinParticles` are
left unchanged.

The velocity fluctuations are then rescaled as

```text
v_i <- u_c + lambda_c * (v_i - u_c)
lambda_c = sqrt(K_target / K_c)
```

This conserves the real-particle mass-weighted momentum of each thermostatted
cell exactly, while controlling the local fluctuation temperature. This is
essential when particle masses are not all identical.

## Diagnostics

`summary_runtime.csv` includes the following thermostat columns:

```text
thermostatApplied
thermostatCells
thermostatParticles
thermostatKBTBefore
thermostatKBTAfter
thermostatScaleMean
thermostatScaleMin
thermostatScaleMax
```

`thermostatKBTBefore` and `thermostatKBTAfter` are computed over the cells that
were actually rescaled. The global `kBTEstimate` column is still computed from
all real particles using global mean velocity removal, so it is a broad runtime
control rather than the exact cell-thermostat objective.

## Notes

This deterministic cell-relative rescaling thermostat is a calibration/control
option, not a final claim about the physical thermalization model. It should be
used to stabilize forced validation runs before extracting effective viscosity
from Poiseuille profiles. The thermostat can be replaced or complemented later
by stochastic or cell-wise Maxwellian thermostats if needed.

# 0493x6g — gas pressure on the resident phase interface

## Purpose

0493x6f separated the numerical Q6 carrier from the physical pressure domain
and prepared an `alpha=0.5` interface stencil once per solve. 0493x6g is the
first physical consumer of the interfacial Dirichlet value:

```text
p_l|Gamma = p_g
phiGamma = dt * (p_g - p_ref) / rho_l,ref
```

The subtraction `p_ref` is a pressure gauge. It does not change pressure
gradients; it avoids carrying a large uniform ambient pressure through the CG
solve. The exact same face-value buffers are intended to receive
`p_g + sigma*kappa` in the capillary stage.

## Architecture

The x6f matrix is unchanged. The production path is:

```text
species-cell deposit
    |
    +-- liquid raw fill ------------------------+
    |                                           |
    +-- gas EOS pressure potential (fused)      |
                                                v
                                      conservative alpha filter
                                                |
                                                v
                              x6f interface-stencil preparation
                                  |                         |
                                  |                         +-- phiGamma per face
                                  +-- pressure mask/coefficients
                                                |
                              +-----------------+-----------------+
                              |                                   |
                         RHS Dirichlet term                    CG matrix
                              |                              (unchanged)
                              +-----------------+-----------------+
                                                |
                                                v
                                  face velocity correction
```

No gas-pressure calculation is performed inside a CG iteration.

## Gas pressure source

Two experimental source modes are available through environment variables:

```text
MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos|constant
```

`eos` is the physical mode:

```text
p_g(c) = N_g(c) kBT / A_cell
```

where all registered species with `phaseFamily=gas` contribute to `N_g`.
The pressure trace at a crossing uses the `alpha<0.5` cell. This first-order
one-sided trace deliberately avoids averaging with a liquid-side cell where
gas can be absent. It works for both x6e `active-active` and
`active-inactive` carrier topologies.

`constant` exists for the pressure-gauge validation and is not a new simulation
parameter.

The remaining experimental controls are:

```text
MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=<p_ref>
MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=<p_const>
MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=<scale>
```

The scale defaults to one and must be non-negative. `scale=0` is a strict
production no-op: x6g keeps its audit row, but skips gas-pressure field
construction, face-value buffers, RHS additions and correction-side pressure
branches.  This makes the null-path validation exercise the exact x6f numerical
trajectory rather than merely an algebraically equivalent zero contribution.

## Discrete Dirichlet contribution

For an x6f represented interface face with coefficient `c_f` and stored
`phiGamma`, the unknown-side operator remains

```text
A_f(phi_c) = c_f phi_c / h^2
```

and the boundary value is moved to the RHS:

```text
rhs_c += c_f phiGamma / h^2.
```

The velocity correction uses the same coefficient and the same boundary value:

```text
Delta u_f = -c_f (phiGamma - phi_c) / h.
```

Therefore the small-theta fallback remains algebraically consistent: when x6f
uses the stabilized half-cell coefficient 2, RHS and velocity correction both
use that same effective distance.

## CUDA cost contract

The gas EOS is fused into the existing x6c raw-geometry grid pass. x6g adds no
particle pass and no gas-pressure kernel. The x6f stencil preparation also
writes two resident face values. The x6g-specific resident storage used by the
active path is one cell gas-potential field plus two face-value fields, i.e.
`3 * Ncells * sizeof(double)` (about 1.03 MiB at 300x150). The CG matrix-vector
product is unchanged from x6f.

## Audits

`cuda_phase_interface_pressure_0493x6g.csv` records on the normal sparse audit
cadence:

- pressure source mode and gas-species count;
- pressure gauge/reference and scale;
- represented and non-zero pressure faces;
- mean/std of `phiGamma`;
- mean/std pressure difference reconstructed from `phiGamma`;
- stencil preparation time and resident bytes.

The analyzer checks the exact conversion
`phiGamma = dt * Delta p / rho_l,ref`. In `constant` mode it additionally
checks the expected constant pressure and vanishing spatial standard deviation.

## Robust validation sequence

`scripts/run_0493x6g_validation.sh` executes three short matched cases:

1. x6f zero-pressure reference;
2. x6g enabled with EOS `scale=0` (strict null-path equivalence);
3. x6g with a non-zero spatially constant pressure shift.

The final particle states are compared directly. The first comparison is very
strict; the second verifies gauge invariance within a tolerance compatible with
the finite CG stopping criterion.

## Final dam-break qualification

`scripts/run_0493x6g_final_dam_break.sh` defaults to 1000 steps, live
visualization disabled, and runs a matched pair:

- x6f `pGamma=0` reference;
- x6g EOS pressure with the initial uniform-gas EOS pressure used as gauge
  reference.

The pair shares grid, state generator, seed and physical parameters. The final
comparison reports physics deltas and wall-time ratio. Set
`RUN_ZERO_REFERENCE=0` to run only the EOS case when a matched baseline is
already available.

## Scope and next step

0493x6g still uses the scalar ideal-gas EOS. It does not yet use the full MPCD
normal stress and does not add surface tension. The intended next stage is to
construct resident normals/curvature from the same x6c `alpha` field, qualify
`kappa` on a plane and circle, then change only the prepared face value to

```text
phiGamma = dt * (p_g + sigma*kappa - p_ref) / rho_l,ref.
```

No new pressure operator should be required for that capillary step.

# 0493x6e — physical phase-interface topology diagnostic

0493x6e is a **diagnostic-only geometry stage** built on top of the resident
phase field introduced in 0493x6c and the guarded cut-face experiment 0493x6d.
It does not change the Q6 operator, the carrier support, gas pressure, SRC,
streaming, thermostatting, boundary conditions, Darcy/chi, resampling, or any
particle velocity.

## Question addressed

0493x6d can reconstruct the alpha=0.5 location only on faces that are already
active/inactive faces of the Q6 carrier mask.  The x6b/x6c/x6d results showed
that the physical phase boundary and the carrier boundary do not generally
coincide.

0493x6e therefore scans **all unique grid faces** crossing

    alpha = 0.5

independently of the carrier mask and classifies each crossing as:

- active-active: both cell centers belong to the Q6 carrier;
- active-inactive: the crossing lies on the carrier boundary;
- inactive-inactive: neither cell center belongs to the carrier.

The active-inactive class is split again according to whether the active cell
is on the liquid side (alpha >= 0.5) or on the exterior side.  This makes the
coverage of the present x6d construction explicit.

## Cost contract

No new production field and no new production CUDA pass are added.  The x6e
scan is fused into the already sparse 0493x6c audit kernel, which runs only at
step 1 and at `SUMMARY_EVERY`.  The production path between audits is exactly
0493x6d.

## Audit columns

The existing `cuda_phase_geometry_resident_0493x6c.csv` is extended with:

- `phaseInterfaceTopologyEnabled`
- `alphaHalfCrossingFaces`
- `alphaHalfCrossingActiveActiveFaces`
- `alphaHalfCrossingActiveInactiveFaces`
- `alphaHalfCrossingInactiveInactiveFaces`
- `alphaHalfCrossingAIActiveLiquidSideFaces`
- `alphaHalfCrossingAIActiveExteriorSideFaces`
- `alphaHalfThetaMin`, `alphaHalfThetaMean`, `alphaHalfThetaStd`,
  `alphaHalfThetaMax`

For each physical crossing, theta is measured from the high-alpha (liquid)
cell center toward the low-alpha (exterior) cell center:

    theta = (alpha_high - 0.5) / (alpha_high - alpha_low)

The current x6d guarded cut-face count should be a subset of
`alphaHalfCrossingAIActiveLiquidSideFaces`; the difference is exactly the
small-theta guard population.

## Purpose of the next decision

If a significant fraction of alpha=0.5 crossings is active-active, the physical
pressure boundary must be represented independently from the carrier-mask
boundary.  This is the expected basis for a later single phase-aware operator
supporting p_Gamma=0, gas pressure, and eventually sigma*kappa on the same
geometric interface.

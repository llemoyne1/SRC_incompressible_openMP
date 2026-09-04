# 0493x14ab — hybrid x10n reference pressure + x6g gauge-face traction

## Purpose

Qualification variant only.  The production default remains unchanged.

The x14aa experiment moved the full absolute gas pressure from x10n/CIC
segments to represented x6g/Q6 faces.  That improved global momentum closure
but degraded the n=2 capillary frequency.  Source inspection shows that x6g
actually carries only the gauge component `(p_g-p_ref)` through its Dirichlet
potential.  x14ab therefore separates the two components:

    J_excess = J_refl[x10n/CIC]
             - J_ref[x10n/CIC]
             - J_gauge[x6g represented faces]

with

    J_ref   = p_ref n_x10n ds dt
    J_gauge = (p_g-p_ref) n_Q6 ds dt

The large uniform equilibrium pressure remains on exactly the same x10n/CIC
geometry as the molecular reflection impulse, preserving local cancellation.
Only the signed gauge component actually represented by x6g is moved to the
same represented Q6 faces as x6g.

For `eos_accessible_volume`, x14ab reuses the same x14s correction of the x6g
gauge potential.  The reconstructed gauge pressure is deliberately signed:
negative `(p_g-p_ref)` must not be clamped.

## Runtime gate

    MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=1

The gate defaults to 0.  x14aa absolute-face mode and x14ab hybrid mode are
mutually exclusive.  For x14ab qualification use:

    MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
    MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=1
    MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0

## Cost contract

x14ab is intentionally constrained to the existing x14v/x14aa execution path:

- new CUDA kernel launches: 0
- new O(Ncell) passes: 0
- new O(Nparticle) passes: 0
- new resident buffers: 0 bytes
- host/device transfers: 0
- additional CG solves: 0

The existing x14v cell kernel already reads the represented x6g east/north
faces.  x14ab changes only the pressure component used there.  On x10n
segments, the expensive segment-to-Q6 gas-cell lookup is no longer needed:
only the scalar `p_ref` is subtracted.  Consequently the variant should be
cost-neutral relative to x14aa and cheaper in arithmetic than the original
segment-wise absolute-pressure reconstruction.

No liquid law x10u/x10v/x12a is modified.  No `livevis_control.kv` file is
modified.

## Preimage

Apply after x14aa.  The installer is semantic/idempotent and verifies that the
current source contains the x14aa markers before modification.

# 0493x14aa — x14v thermodynamic traction on represented x6g faces

Purpose: validate a low-cost discrete coupling between x14v and x6g on curved/moving interfaces.

## Physics

The raw gas reflection impulse remains the actual x14l/x10n/CIC aggregate.  Only the
thermodynamic subtraction changes.  In x14aa:

    J_excess = J_refl,x14l - J_thermo,x6g-faces

`J_thermo` is no longer reconstructed on x10n segments.  It is evaluated on the east/north
alpha=0.5 faces already represented by x6f/x6g, using the same gas-side Q6 cell, the same
resident gas pressure potential and the same x14s `eos_accessible_volume` correction.
The face pressure impulse is scattered conservatively into the existing x14v liquid-CIC
kick buffers.  Capillary sigma*kappa is not included in this subtraction.

## Cost contract

The implementation deliberately avoids exact post-CG momentum accounting:

- 0 new CUDA kernel launches;
- 0 new O(Ncell) passes;
- 0 new O(Np) passes;
- 0 new resident buffers;
- 0 host transfers;
- 0 additional CG solves.

The already-existing x14v cell kernel reads the two current x6f face coefficients.  Only
represented interface faces perform the extra pressure/scatter work.  Axis-aligned face
impulses skip atomic adds on their exactly-zero component.  The old x10n->Q6 nearest-gas-cell
lookup is skipped when x14aa is enabled.  x14z reference-pressure closure is automatically
bypassed in x14aa mode.

## Gate

    MPCD_X14V_X6G_FACE_THERMO_TRACTION=1

Default is 0 until qualification.  x14v and the thermodynamic subtraction must remain ON.

## Qualification target

Use the paired n=2 oscillating-drop case (seed 493180, 2000 steps) with x14z OFF.  Compare
against the already measured nominal x14v case on the same 0..4 time window:

- total barycentric acceleration / droplet COM drift;
- n=2 omega and G_omega;
- fit R2 and damping;
- internal wall time per step.

The desired result is simultaneous retention of the nominal frequency (~few-percent
agreement with the two-fluid reference) and strong suppression of the secular total-momentum
drift, without a measurable step-cost penalty.

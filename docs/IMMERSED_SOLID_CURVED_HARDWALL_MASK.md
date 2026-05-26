# Curved immersed-solid hard-wall projection mask

## Purpose

The first immersed-solid Q6/Q9 mask was sufficient for axis-aligned rectangles:
a face was closed whenever one of the two adjacent cell centres was classified as
solid.  A circular cylinder is more subtle.  Two neighbouring cell centres can
both be fluid while the face segment between them is still cut by the analytic
circle.  If that face remains open, the elliptic projection can communicate
through the cylinder even though particle reflections keep particles out of the
solid.

This patch adds a stricter curved-solid rule and a diagnostic split for the
resulting closed faces.

## New rule

When `projectionImmersedSolidMaskEnable=true`, the mask now closes a face when:

```text
1. one of the adjacent cells is inactive/solid, or
2. projectionImmersedSolidCloseCutFaces=true and the face segment intersects the
   analytic immersed solid while both adjacent cells are active.
```

The default is:

```text
projectionImmersedSolidCloseCutFaces = true
```

For `circle`, the face/solid intersection is analytic: the closest point of the
axis-aligned face segment to the circle centre is tested against `R`.  For
`rectangle`, a Liang-Barsky style segment/box intersection test is used.  This
keeps the mask compact and shape-driven inside the existing `immersed_solid`
module.

## Elliptic hard-wall consequence

The elliptic core now treats any face with `alpha_face=0` as an internal no-flux
face, even when both adjacent cell centres are active.  In `project_face_field`,
such a face is removed from the solve RHS and the returned projected flux is set
to zero:

```text
alpha_face = 0  =>  correctionFlux = -baseFlux, projectedFlux = 0
```

This is the key change required for curved cut faces.  Previously, if both
neighbouring cells were active, `alpha=0` only suppressed the pressure-gradient
correction; the base flux through the cut face could remain in the projected
field.

## Diagnostic split

The runtime CSV still keeps the aggregate leak columns:

```text
q6ImmersedSolidLeakProjectedFluxRms
q9ImmersedSolidLeakMassFluxRms
```

and appends a split between cell/boundary-closed faces and cut-closed faces:

```text
q6ImmersedSolidCellClosedXFaces
q6ImmersedSolidCellClosedYFaces
q6ImmersedSolidCutClosedXFaces
q6ImmersedSolidCutClosedYFaces
q6ImmersedSolidLeakCellClosedProjectedFluxRms
q6ImmersedSolidLeakCellClosedProjectedFluxMaxAbs
q6ImmersedSolidLeakCutProjectedFluxRms
q6ImmersedSolidLeakCutProjectedFluxMaxAbs

q9ImmersedSolidCellClosedXFaces
q9ImmersedSolidCellClosedYFaces
q9ImmersedSolidCutClosedXFaces
q9ImmersedSolidCutClosedYFaces
q9ImmersedSolidLeakCellClosedMassFluxRms
q9ImmersedSolidLeakCellClosedMassFluxMaxAbs
q9ImmersedSolidLeakCutMassFluxRms
q9ImmersedSolidLeakCutMassFluxMaxAbs
```

For a curved cylinder validation, the expected result is:

```text
cutClosedX/YFaces > 0
q6/q9 leak on cut faces ≈ 0
aggregate q6/q9 solid leak ≈ 0
```

If the aggregate leak remains non-zero, the split tells whether the problem is
still located on cut faces or on cell/boundary closed faces.

## Von Karman usage

The von-Karman long comparison script now writes explicitly:

```text
projectionImmersedSolidCloseCutFaces = true
```

for the liquid-closure run.  After relaunching a short Q9/virial von-Karman
preflight, check in `summary_runtime.csv` that:

```text
q6ImmersedSolidLeakProjectedFluxRmsLate ~ 0
q9ImmersedSolidLeakMassFluxRmsLate ~ 0
q6ImmersedSolidLeakCutProjectedFluxRmsLate ~ 0
q9ImmersedSolidLeakCutMassFluxRmsLate ~ 0
```

The MATLAB validator `validate_von_karman_long_comparison` now also reports and
plots the cut-face leak split when these columns are available.

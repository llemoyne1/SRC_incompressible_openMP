#!/usr/bin/env python3
import math

P3_RADIUS = 3
SCHARR_RADIUS = 1
SUPPORT_RADIUS = P3_RADIUS + SCHARR_RADIUS
ANCHOR_LAYER = SUPPORT_RADIUS
ANCHOR_CENTER_H = ANCHOR_LAYER + 0.5
R_OVER_H = 50.0
ANGLES = (30.0,45.0,60.0,75.0,90.0,105.0,120.0,135.0,150.0)

print(
    f"[0493x9m-mapcheck] p3Radius={P3_RADIUS} scharrRadius={SCHARR_RADIUS} "
    f"supportRadius={SUPPORT_RADIUS} anchorLayer={ANCHOR_LAYER} "
    f"anchorCenter={ANCHOR_CENTER_H:.1f}h"
)
lo = ANCHOR_LAYER - SUPPORT_RADIUS
hi = ANCHOR_LAYER + SUPPORT_RADIUS
print(
    f"[0493x9m-mapcheck] anchor raw-normal scalar-support layers={lo}..{hi} "
    f"pass={int(lo >= 0)}"
)
all_ok = (lo >= 0)

# Verify the exact geometry used by the x9m closure on a circular sessile cap.
# Work in h=1 units with a bottom wall y=0.  The circle center is
# y_c=-R*cos(theta), so its contact angle measured through A is theta and
# kappa_exact=1/R.  Test the right contact branch; the left branch is its mirror.
R = R_OVER_H
for theta_deg in ANGLES:
    theta = math.radians(theta_deg)
    st, ct = math.sin(theta), math.cos(theta)
    if abs(st) <= 1e-14:
        ok = False
        print(f"[0493x9m-mapcheck] theta={theta_deg:g} unsupported-endpoint pass=0")
        all_ok = False
        continue

    # Search centering used by CUDA: planar contact-line continuation to y=4.5h.
    predicted = ANCHOR_CENTER_H * ct / st
    search_radius = min(48, max(8, math.ceil(abs(predicted)) + 8))

    yc = -R * ct
    y_anchor = ANCHOR_CENTER_H
    radial_y = y_anchor - yc
    inside = R*R - radial_y*radial_y
    if inside <= 0.0:
        ok = False
        print(
            f"[0493x9m-mapcheck] theta={theta_deg:g} anchorOutsideCircle=1 "
            f"predictedOffset={predicted:+.6f} searchRadius={search_radius} pass=0"
        )
        all_ok = False
        continue

    x_wall = R * st
    x_anchor = math.sqrt(max(0.0, inside))
    wall_n = (st, ct)
    anchor_n = (x_anchor / R, radial_y / R)
    chord = (x_anchor - x_wall, y_anchor)
    chord_len = math.hypot(*chord)
    dot = max(-1.0, min(1.0, wall_n[0]*anchor_n[0] + wall_n[1]*anchor_n[1]))
    cross = wall_n[0]*anchor_n[1] - wall_n[1]*anchor_n[0]
    delta = math.atan2(cross, dot)
    tangent0 = (-wall_n[1], wall_n[0])
    orient_dot = chord[0]*tangent0[0] + chord[1]*tangent0[1]
    orient = 1.0 if orient_dot >= 0.0 else -1.0
    kappa = 2.0 * math.sin(0.5*delta) / (orient*chord_len)
    exact = 1.0/R
    rel = (kappa-exact)/exact
    ok = (
        search_radius >= abs(predicted)
        and chord_len > 0.0
        and abs(rel) < 2.0e-12
    )
    all_ok &= ok
    print(
        f"[0493x9m-mapcheck] theta={theta_deg:g} "
        f"predictedOffset={predicted:+.6f}cells searchRadius={search_radius} "
        f"delta={math.degrees(delta):+.6f}deg secantKappa={kappa:.12g} "
        f"exact={exact:.12g} relErr={rel:+.3e} pass={int(ok)}"
    )

print(f"[0493x9m-mapcheck] status={'PASS' if all_ok else 'FAIL'}")
raise SystemExit(0 if all_ok else 2)

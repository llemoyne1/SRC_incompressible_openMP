#!/usr/bin/env python3
# 1D normal sanity check. n points from liquid to vacuum.
# v = U + c. The donor gate uses g=c, not absolute v.
U = 0.04
thermal = [-0.03, -0.01, 0.01, 0.03]

free_absolute_outward = 0
reflected_donors = 0
for c in thermal:
    v = U + c
    g = c
    if g > 0:
        v2 = v - 2.0*g
        assert abs(v2 - (U-c)) < 1e-15
        reflected_donors += 1
    else:
        if v > 0:
            free_absolute_outward += 1

if free_absolute_outward == 0:
    raise SystemExit("FAIL: relative gate still pins translating interface")
if reflected_donors == 0:
    raise SystemExit("FAIL: no thermal donors reflected")

print(f"bulkNormalVelocity={U}")
print(f"freeAbsoluteOutwardNonDonors={free_absolute_outward}")
print(f"reflectedRelativeThermalDonors={reflected_donors}")
print("status=PASS")

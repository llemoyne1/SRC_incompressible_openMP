#!/usr/bin/env python3
import math

def reflect_endpoint(xg, yg, xe, ye, nx, ny):
    dx, dy = xe-xg, ye-yg
    dn = dx*nx + dy*ny
    return xe-2*dn*nx, ye-2*dn*ny

worst_len = 0.0
worst_normal = 0.0
for ang in [i*math.pi/37.0 for i in range(74)]:
    nx, ny = math.cos(ang), math.sin(ang)
    tx, ty = -ny, nx
    for normal in (1e-6, 0.01, 0.2, 1.0):
        for tangent in (-0.7, -0.1, 0.0, 0.3, 0.9):
            xg, yg = 0.13, -0.27
            xe = xg + normal*nx + tangent*tx
            ye = yg + normal*ny + tangent*ty
            xr, yr = reflect_endpoint(xg, yg, xe, ye, nx, ny)
            li = math.hypot(xe-xg, ye-yg)
            lr = math.hypot(xr-xg, yr-yg)
            nr = (xr-xg)*nx + (yr-yg)*ny
            worst_len = max(worst_len, abs(li-lr))
            worst_normal = max(worst_normal, abs(nr + normal))
            if nr >= 1e-12:
                raise SystemExit('FAIL reflected endpoint not inward')
print(f'maxResidualLengthError={worst_len:.3e}')
print(f'maxNormalMirrorError={worst_normal:.3e}')
print('status=PASS')

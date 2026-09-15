#!/usr/bin/env python3
"""0493x18a fix2: align initial fluid exclusion with a rotated hinged plate.

The solver's x18a material contour is extracted from the initial *vertical* box
chi and then rigidly rotated by chiSolidHingedInitialAngle.  Legacy initial chi
deactivation acts earlier on the vertical box.  For a non-zero initial angle,
this helper instead marks particles inactive inside the *rotated* extracted
rectangle; the runner disables the legacy vertical deactivation.

Only the particle role array is changed.  read_smpcd_state() performs the normal
active-prefix compaction when the state is loaded.
"""
from __future__ import annotations
import argparse, math, os, struct, sys

HEADER_PREFIX = 16
HEADER_FMT = "<IIIIQIIII"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
RESERVED_SIZE = 8 * 8
ARRAY_BASE = HEADER_PREFIX + HEADER_SIZE + RESERVED_SIZE


def effective_box(Lx, Ly, nx, ny, xmin, xmax, ymin, ymax):
    dx, dy = Lx / nx, Ly / ny
    ix = [i for i in range(nx) if xmin <= (i + 0.5) * dx <= xmax]
    iy = [j for j in range(ny) if ymin <= (j + 0.5) * dy <= ymax]
    if not ix or not iy:
        raise RuntimeError("box selects no chi cells")
    # Marching-squares contour of a binary cell-centred rectangle lies halfway
    # between the last solid centre and the first fluid centre: on cell edges.
    return ix[0] * dx, (ix[-1] + 1) * dx, iy[0] * dy, (iy[-1] + 1) * dy


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--Nx", type=int, required=True)
    ap.add_argument("--Ny", type=int, required=True)
    ap.add_argument("--box-xmin", type=float, required=True)
    ap.add_argument("--box-xmax", type=float, required=True)
    ap.add_argument("--box-ymin", type=float, required=True)
    ap.add_argument("--box-ymax", type=float, required=True)
    ap.add_argument("--angle", type=float, required=True)
    args = ap.parse_args()

    path = args.state
    data = bytearray(open(path, "rb").read())
    if len(data) < ARRAY_BASE:
        raise RuntimeError("truncated .smpcd state")
    magic = bytes(data[:16]).split(b"\0", 1)[0]
    if magic != b"SRCMPCD_STATE":
        raise RuntimeError(f"unexpected state magic {magic!r}")
    hdr = struct.unpack_from(HEADER_FMT, data, HEADER_PREFIX)
    n = int(hdr[4])
    if n <= 0:
        raise RuntimeError("empty state")

    # Layout: x,y,vx,vy double; type uint32; mass double; role uint8.
    xoff = ARRAY_BASE
    yoff = xoff + 8 * n
    roleoff = ARRAY_BASE + (8 + 8 + 8 + 8 + 4 + 8) * n
    if roleoff + n != len(data):
        raise RuntimeError(
            f"unexpected state size: got={len(data)} expected={roleoff+n} Np={n}")

    xs = memoryview(data)[xoff:xoff + 8*n].cast("d")
    ys = memoryview(data)[yoff:yoff + 8*n].cast("d")
    roles = memoryview(data)[roleoff:roleoff+n]

    ex0, ex1, ey0, ey1 = effective_box(
        args.Lx, args.Ly, args.Nx, args.Ny,
        args.box_xmin, args.box_xmax, args.box_ymin, args.box_ymax)
    pivot_x = 0.5 * (ex0 + ex1)
    pivot_y = ey1
    rel_x0, rel_x1 = ex0 - pivot_x, ex1 - pivot_x
    rel_y0, rel_y1 = ey0 - pivot_y, 0.0

    c, s = math.cos(args.angle), math.sin(args.angle)
    before = sum(1 for r in roles if r == 1)
    deactivated = 0
    tol = 1e-14 * max(args.Lx, args.Ly, 1.0)
    for i in range(n):
        if roles[i] != 1:
            continue
        dx = xs[i] - pivot_x
        dy = ys[i] - pivot_y
        # Inverse rigid rotation R(-theta): world -> vertical reference plate.
        rx0 = c * dx + s * dy
        ry0 = -s * dx + c * dy
        if (rel_x0 - tol <= rx0 <= rel_x1 + tol and
                rel_y0 - tol <= ry0 <= rel_y1 + tol):
            roles[i] = 0
            deactivated += 1

    after = before - deactivated
    if deactivated <= 0:
        raise RuntimeError("rotated initial plate excluded zero particles")

    tmp = path + ".x18a_fix2.tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)

    print(
        "[0493x18a-init-fix2] rotated-fluid-exclusion=ON "
        f"angle={args.angle:.17g} pivot=({pivot_x:.17g},{pivot_y:.17g}) "
        f"referenceBox=[{ex0:.17g},{ex1:.17g}]x[{ey0:.17g},{ey1:.17g}] "
        f"deactivated={deactivated} activeBefore={before} activeAfter={after}")


if __name__ == "__main__":
    main()

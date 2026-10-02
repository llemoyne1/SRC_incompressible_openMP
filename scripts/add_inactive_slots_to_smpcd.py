#!/usr/bin/env python3

from array import array
import argparse
import os
import struct
import sys


HDR_FMT = "<IIIIQIIII"
HDR_SIZE = struct.calcsize(HDR_FMT)


def read_array(f, code, count):
    a = array(code)
    nbytes = a.itemsize * count
    raw = f.read(nbytes)

    if len(raw) != nbytes:
        raise RuntimeError(
            f"Truncated array {code}: expected {nbytes} bytes, got {len(raw)}"
        )

    a.frombytes(raw)

    if sys.byteorder == "big":
        a.byteswap()

    return a


def write_array(f, a):
    if sys.byteorder == "big":
        a.byteswap()
        f.write(a.tobytes())
        a.byteswap()
    else:
        f.write(a.tobytes())


def main():
    p = argparse.ArgumentParser(
        description=(
            "Add missing inactive slots to a SRC/MPCD v2 state "
            "without modifying any existing particle."
        )
    )
    p.add_argument("input_state")
    p.add_argument("output_state")
    p.add_argument("--target-inactive", type=int, required=True)
    p.add_argument("--inactive-type", type=int, required=True)
    p.add_argument("--inactive-mass", type=float, required=True)
    args = p.parse_args()

    if args.target_inactive < 0:
        raise SystemExit("target-inactive must be >= 0")

    if args.inactive_mass <= 0.0:
        raise SystemExit("inactive-mass must be > 0")

    src = args.input_state
    dst = args.output_state

    with open(src, "rb") as f:
        magic = f.read(16)

        if not magic.startswith(b"SRCMPCD_STATE"):
            raise SystemExit(f"ERROR: bad SRCMPCD_STATE magic in {src}")

        raw = f.read(HDR_SIZE)
        if len(raw) != HDR_SIZE:
            raise SystemExit("ERROR: truncated state header")

        version, endian, dim, ns, n, a, b, rsv_n, word = \
            struct.unpack(HDR_FMT, raw)

        if version != 2:
            raise SystemExit(f"ERROR: expected state version 2, got {version}")

        if endian != 0x01020304:
            raise SystemExit(
                f"ERROR: unsupported endian marker {endian:#x}"
            )

        if dim != 2:
            raise SystemExit(f"ERROR: expected dim=2, got {dim}")

        reserved_raw = f.read(8 * 8)
        if len(reserved_raw) != 8 * 8:
            raise SystemExit("ERROR: truncated reserved header")

        x    = read_array(f, "d", n)
        y    = read_array(f, "d", n)
        vx   = read_array(f, "d", n)
        vy   = read_array(f, "d", n)
        typ  = read_array(f, "I", n)
        mass = read_array(f, "d", n)
        role = read_array(f, "B", n)

        trailing = f.read()
        if trailing:
            raise SystemExit(
                f"ERROR: unexpected trailing data ({len(trailing)} bytes)"
            )

    # role == 0 : Inactive
    existing_inactive = sum(1 for r in role if r == 0)
    fluid = sum(1 for r in role if r != 0)

    add = max(0, args.target_inactive - existing_inactive)

    if add:
        x.extend([0.0] * add)
        y.extend([0.0] * add)
        vx.extend([0.0] * add)
        vy.extend([0.0] * add)

        # x24 gas hard-inlet reservoir:
        typ.extend([args.inactive_type] * add)
        mass.extend([args.inactive_mass] * add)

        # Inactive role
        role.extend([0] * add)

    new_n = n + add

    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)

    with open(dst, "wb") as f:
        f.write(magic)
        f.write(
            struct.pack(
                HDR_FMT,
                version, endian, dim, ns,
                new_n,
                a, b, rsv_n, word
            )
        )
        f.write(reserved_raw)

        for arr in (x, y, vx, vy, typ, mass, role):
            write_array(f, arr)

    print("===== ADD INACTIVE SLOTS =====")
    print(f"source              = {src}")
    print(f"output              = {dst}")
    print(f"source particles    = {n}")
    print(f"source fluid/nonzero= {fluid}")
    print(f"existing inactive   = {existing_inactive}")
    print(f"target inactive     = {args.target_inactive}")
    print(f"added inactive      = {add}")
    print(f"inactive type       = {args.inactive_type}")
    print(f"inactive mass       = {args.inactive_mass:.17g}")
    print(f"output particles    = {new_n}")
    print("status              = OK")


if __name__ == "__main__":
    main()
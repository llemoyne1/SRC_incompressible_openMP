#!/usr/bin/env python3
"""Append inactive MPCD slots to a V1/V2 .smpcd state for profiling active/fluid-slot paths."""
import os
import struct
import sys


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: augment_smpcd_inactive_bulk_0205a.py SRC DST INACTIVE_SLOTS|auto INACTIVE_FACTOR", file=sys.stderr)
        return 2
    src, dst, inactive_arg, inactive_factor_arg = sys.argv[1:]
    inactive_factor = float(inactive_factor_arg)
    magic_expected = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
    with open(src, "rb") as f:
        magic = f.read(16)
        if magic != magic_expected:
            raise SystemExit(f"invalid magic in {src}")
        version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = struct.unpack("<IIIIQIIII", f.read(40))
        _reserved = list(struct.unpack("<8Q", f.read(64)))
        if endian != 0x01020304 or dim != 2 or layout != 1 or has_type != 1 or has_mass != 1 or real_size != 8 or type_size != 4:
            raise SystemExit("unsupported .smpcd header")
        x = list(struct.unpack(f"<{n}d", f.read(8 * n)))
        y = list(struct.unpack(f"<{n}d", f.read(8 * n)))
        vx = list(struct.unpack(f"<{n}d", f.read(8 * n)))
        vy = list(struct.unpack(f"<{n}d", f.read(8 * n)))
        typ = list(struct.unpack(f"<{n}I", f.read(4 * n)))
        mass = list(struct.unpack(f"<{n}d", f.read(8 * n)))
        if version == 2:
            role = list(struct.unpack(f"<{n}B", f.read(n)))
        elif version == 1:
            role = [1] * n
        else:
            raise SystemExit(f"unsupported version {version}")

    if inactive_arg == "auto":
        extra = int(round(n * inactive_factor))
    else:
        extra = int(inactive_arg)
    if extra < 0:
        raise SystemExit("INACTIVE_SLOTS must be >= 0")

    if extra:
        x.extend([0.0] * extra)
        y.extend([0.0] * extra)
        vx.extend([0.0] * extra)
        vy.extend([0.0] * extra)
        typ.extend([0] * extra)
        mass.extend([1.0] * extra)
        role.extend([0] * extra)  # ParticleRole::Inactive

    n2 = len(x)
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    reserved = [0] * 8
    reserved[0] = 1  # V2 has role array
    reserved[1] = 1  # role byte size
    with open(dst, "wb") as f:
        f.write(magic_expected)
        f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n2, 1, 1, 8, 4))
        f.write(struct.pack("<8Q", *reserved))
        f.write(struct.pack(f"<{n2}d", *x))
        f.write(struct.pack(f"<{n2}d", *y))
        f.write(struct.pack(f"<{n2}d", *vx))
        f.write(struct.pack(f"<{n2}d", *vy))
        f.write(struct.pack(f"<{n2}I", *typ))
        f.write(struct.pack(f"<{n2}d", *mass))
        f.write(struct.pack(f"<{n2}B", *role))

    print(f"[0205a-state] active={n} inactive_added={extra} total={n2} output={dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

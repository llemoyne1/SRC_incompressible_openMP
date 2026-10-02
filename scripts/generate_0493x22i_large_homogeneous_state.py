#!/usr/bin/env python3
"""0493x22i: memory-bounded homogeneous .smpcd V2 state generator.

Designed for very large constant-gamma scaling tests where the historical
0493w1 Python-list generator would consume excessive host RAM.  The generated
state is a homogeneous fluid with exactly gamma particles per cell, deterministic
sub-cell positions, zero cell-mean velocity and exact cell thermal energy
N_cell*kBT (up to floating-point roundoff).  Data are streamed field-by-field in
chunks, so peak Python memory is O(chunk_cells*gamma), not O(Nparticles).
"""
from __future__ import annotations

import argparse
import math
import os
import struct
import sys
from pathlib import Path

try:
    import numpy as np
except Exception as exc:  # pragma: no cover
    raise SystemExit(f"[0493x22i-state] numpy is required: {exc}")

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
HEADER_BYTES = 16 + struct.calcsize("<IIIIQIIII") + struct.calcsize("<8Q")
BYTES_PER_PARTICLE = 5 * 8 + 4 + 1  # x,y,vx,vy,mass + type + role


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--Lx", type=float, required=True)
    p.add_argument("--Ly", type=float, required=True)
    p.add_argument("--Nx", type=int, required=True)
    p.add_argument("--Ny", type=int, required=True)
    p.add_argument("--gamma", type=int, required=True)
    p.add_argument("--kBT", type=float, required=True)
    p.add_argument("--mass", type=float, default=1.0)
    p.add_argument("--seed", type=int, default=4933501)
    p.add_argument("--chunk-cells", type=int, default=8192)
    p.add_argument("--force", action="store_true")
    return p.parse_args()


def validate(a):
    if a.Nx < 8 or a.Ny < 8 or a.gamma < 4:
        raise SystemExit("[0493x22i-state] Nx,Ny>=8 and gamma>=4 required")
    if min(a.Lx, a.Ly, a.kBT, a.mass) <= 0:
        raise SystemExit("[0493x22i-state] Lx,Ly,kBT,mass must be positive")
    if a.chunk_cells < 1:
        raise SystemExit("[0493x22i-state] chunk-cells must be >=1")


def header(stream, n):
    reserved = [0] * 8
    reserved[0] = 1  # role present
    reserved[1] = 1  # role byte width
    stream.write(MAGIC)
    stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
    stream.write(struct.pack("<8Q", *reserved))


def cell_chunks(ncells, chunk_cells):
    start = 0
    while start < ncells:
        stop = min(ncells, start + chunk_cells)
        yield start, stop
        start = stop


def slot_offsets(gamma):
    slot = np.arange(gamma, dtype=np.float64) + 0.5
    fx = np.mod(slot * 0.6180339887498949, 1.0)
    fy = np.mod(slot * 0.4142135623730950, 1.0)
    margin = 0.04
    return margin + (1.0 - 2.0 * margin) * fx, margin + (1.0 - 2.0 * margin) * fy


def write_position_field(stream, a, component):
    ncells = a.Nx * a.Ny
    fx, fy = slot_offsets(a.gamma)
    offs = fx if component == 0 else fy
    nside = a.Nx if component == 0 else a.Ny
    length = a.Lx if component == 0 else a.Ly
    for start, stop in cell_chunks(ncells, a.chunk_cells):
        cells = np.arange(start, stop, dtype=np.int64)
        base = np.mod(cells, a.Nx) if component == 0 else cells // a.Nx
        values = (base[:, None].astype(np.float64) + offs[None, :]) * (length / nside)
        np.asarray(values, dtype="<f8").reshape(-1).tofile(stream)


def normalized_thermal_chunk(rng, ncell, gamma, kbt, mass):
    q = rng.standard_normal((ncell, gamma, 2), dtype=np.float64)
    q -= q.mean(axis=1, keepdims=True)
    ss = np.sum(q * q, axis=(1, 2))
    # target KE = gamma*kBT in 2-D, so mass/2 * sum(q^2) = gamma*kBT.
    scale = np.sqrt((2.0 * gamma * kbt / mass) / ss)
    q *= scale[:, None, None]
    return q


def write_velocity_field(stream, a, component):
    # Reinitialize the RNG for each component.  Because chunking is identical,
    # vx and vy are extracted from the same deterministic 2-D samples.
    rng = np.random.default_rng(a.seed)
    ncells = a.Nx * a.Ny
    for start, stop in cell_chunks(ncells, a.chunk_cells):
        q = normalized_thermal_chunk(rng, stop - start, a.gamma, a.kBT, a.mass)
        np.asarray(q[:, :, component], dtype="<f8").reshape(-1).tofile(stream)


def write_constant_field(stream, n, dtype, value, chunk_particles=1_000_000):
    dt = np.dtype(dtype)
    block_n = min(n, chunk_particles)
    block = np.full(block_n, value, dtype=dt)
    done = 0
    while done < n:
        count = min(block_n, n - done)
        block[:count].tofile(stream)
        done += count


def main():
    a = parse_args()
    validate(a)
    n = a.Nx * a.Ny * a.gamma
    expected = HEADER_BYTES + BYTES_PER_PARTICLE * n
    if a.output.exists() and not a.force:
        actual = a.output.stat().st_size
        if actual == expected:
            print(f"[0493x22i-state] reuse path={a.output} bytes={actual} N={n}")
            return
        raise SystemExit(
            f"[0493x22i-state] existing file has wrong size path={a.output} "
            f"actual={actual} expected={expected}; use --force"
        )
    a.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = a.output.with_suffix(a.output.suffix + ".tmp")
    if tmp.exists():
        tmp.unlink()
    print(
        f"[0493x22i-state] generate grid={a.Nx}x{a.Ny} gamma={a.gamma} N={n} "
        f"expected_bytes={expected} ({expected/2**30:.3f} GiB) chunk_cells={a.chunk_cells}",
        flush=True,
    )
    try:
        with tmp.open("wb", buffering=8 * 1024 * 1024) as stream:
            header(stream, n)
            write_position_field(stream, a, 0)
            write_position_field(stream, a, 1)
            write_velocity_field(stream, a, 0)
            write_velocity_field(stream, a, 1)
            write_constant_field(stream, n, "<u4", 0)
            write_constant_field(stream, n, "<f8", a.mass)
            write_constant_field(stream, n, "u1", 1)
        actual = tmp.stat().st_size
        if actual != expected:
            raise RuntimeError(f"wrong output size actual={actual} expected={expected}")
        os.replace(tmp, a.output)
    except Exception:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass
        raise
    print(
        f"[0493x22i-state] PASS path={a.output} bytes={expected} "
        f"Np={n} gamma={a.gamma} kBT={a.kBT:.17g} cellMeanVelocity=0 cellKE=gamma*kBT",
        flush=True,
    )


if __name__ == "__main__":
    main()

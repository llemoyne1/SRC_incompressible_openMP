# 0443 counter fix — effective remap/thermal cell counters

The first 0443 smoke showed CPU/GPU identity for all physical invariants, but failed two
cases because the validator compared diagnostic cell counters too strictly.

The CPU production diagnostics report `cellsRemapped` and `cellsRenormalized` only when
the corresponding mass or velocity scale differs from one by more than `1e-13`. The CUDA
shadow implementation deliberately applied the remap and thermal kernels to every valid
cell in the remap/renormalization mask, including unit-scale cells, and initially reported
that broader touched-cell count.

This fix keeps the CUDA operations unchanged, but reports the effective cell counters with
the same convention as the CPU diagnostics: only cells with `abs(scale - 1) > 1e-13` are
counted. The pass criterion remains strict on physical state: roles, positions, masses,
velocities, total mass, momentum, and kinetic energy must match CPU within tolerance.

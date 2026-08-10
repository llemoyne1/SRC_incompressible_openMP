# 0493x7j — fully CUDA-resident Q6-g-f CG

## Motivation

The 0493x7i Taylor–Green performance audit isolated a structural performance
regression in `free_surface_masked` Q6-g-f.  At the same `1e-5` projection
tolerance, previous Q6 and Q6-g-f require essentially the same number of CG
iterations on the 128x128 full-domain TG case (~164), but the Q6-g-f masked CG
paid a host reduction / synchronization twice per iteration and cost about
44 ms/step in `solveSeconds` by itself.

This violated the resident-CUDA design objective of the Q6-g-f branch even
though the particle/cell state itself remained device resident.

## Change

0493x7j leaves the Q6-g-f physics unchanged and replaces only the iterative
masked-CG execution when the x6f prepared stencil is active.

The new default path is a single cooperative CUDA kernel covering the complete
Krylov recurrence:

- `A*p` and `p.A.p`;
- `phi += alpha*p` and `r -= alpha*A*p`;
- `r.r` and the convergence test;
- `p = r + beta*p`;
- the existing 25-iteration null-space mean removal for full-domain solves.

Grid-wide reductions use resident per-block scratch followed by
`cooperative_groups::grid_group::sync()`.  There is no GPU->CPU transfer inside
an iteration.  The RHS partial statistics are also collapsed on device before
the solve, so the host receives only one small CG-state structure after the
complete solve.

For cell counts covered by the already-proven 0407 single-block heuristic
(default `<=65536` cells), x7j launches one persistent block and reduces with
warp shuffles plus `__syncthreads()`, avoiding grid-wide barrier overhead.
Larger grids switch automatically to a cooperative multi-block launch.  Its
maximum grid size is chosen once per CUDA device from
`cudaOccupancyMaxActiveBlocksPerMultiprocessor * SM_count`, capped by the
number of cell blocks, so every block can remain simultaneously resident while
all SM capacity is available.

## Exact operator paths

`fullDomain=1` uses the standard finite-volume Laplacian.  This is algebraically
the same operator as the x6f prepared stencil when every pressure cell is
active and there is no interface.  The RHS, x7d density-restoration target,
force-aware prestream ordering and B1 application remain those of Q6-g-f.

`fullDomain=0` reads the x6f pressure mask plus prepared east/north face
coefficients.  Therefore the alpha=0.5 interface, theta factors, x6g Dirichlet
pressure values in the RHS, wall/open-boundary matrix semantics and all
free-surface topology rules are unchanged.

If cooperative launch is unavailable, the existing host-driven masked CG is
retained as a compatibility fallback.

## Gate

The resident CG is enabled by default.  A temporary qualification opt-out is
available:

```text
MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0
```

This gate changes execution only, not parameters or physics.

## Audit

`cuda_species_q6_independent_masked_0493w5.csv` gains two columns:

```text
residentCg0493x7j
residentCgBlocks0493x7j
```

A qualified Q6-g-f production run on a cooperative-capable CUDA GPU should
report `residentCg0493x7j=1` and a positive block count.

## First qualification

Use the already diagnosed TG case first, with `projectionTolerance=1e-5` and
x7d active.  Compare:

1. default x7j resident CG;
2. `MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0` legacy masked-CG fallback.

Requirements:

- both converge at the requested tolerance;
- comparable iteration counts and Q6 correction scale;
- resident path has `residentCg0493x7j=1`;
- no regression in `q6F`, `q6A`, mass, temperature or particle count;
- large reduction in `solveSeconds` and wall time.

Then repeat on the two-phase dam-break so the non-full x6f prepared-stencil
path is exercised before x7j is considered qualified.

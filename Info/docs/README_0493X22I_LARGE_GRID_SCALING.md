# 0493x22i — very-large-grid SRC vs Q6-G-F scaling

## Purpose

Short diagnostic extension of x22g/x22h to grids large enough to expose any
asymptotic change in the SRC/Q6-G-F cost ratio without launching hour-scale
runs.  No solver source or physics is modified.

Default matrix:

- gamma = 20, h = 1/256, kBT = 0.125, dt = nominal article value;
- fully periodic square domains;
- exact production paths: `SRC_PROD` and `Q6GF_PROD_X7J` (x7j=1, 0407=0);
- N = 512, 1024, 2048;
- steps = 96, 32, 12 respectively;
- one paired comparison per grid, alternating order across grids;
- internal profiles ON, LiveVis/recording/dumps OFF.

The projection tolerance remains `1e-5`.  The iteration cap is raised from the
x22g diagnostic value 2500 to 5000 only to avoid truncating the scaling study at
2048 if the unpreconditioned CG requires more iterations.  The analyzer records
final convergence, residual and iteration count.  If iterations exceed 2500,
that fact must be reported as part of the scaling result; it is not hidden.

## Why profile time is primary

At gamma=20, the homogeneous V2 state sizes are approximately:

- 512^2: 0.220 GiB;
- 1024^2: 0.879 GiB;
- 2048^2: 3.516 GiB.

For 12--96 step runs, process wall time would be contaminated by multi-GB state
I/O, initial host summaries and CUDA setup.  Therefore the primary comparison is
`phase_profile_0163.csv` ms/step, using the same chrono instrumentation audited
in x22h.  `/usr/bin/time` is retained only as ancillary information.

## Large-state generator

The historical 0493w1 state generator stores every particle field as Python
lists and is unsuitable for 80+ million particles.  x22i adds a generator that
streams the exact `.smpcd` V2 SoA fields in NumPy chunks.  Peak generator memory
is O(chunk_cells*gamma).  Each cell has deterministic sub-cell positions, zero
cell-mean velocity and exact 2-D thermal kinetic energy gamma*kBT.

Default `KEEP_STATES=0` removes each large state after its SRC/Q6-G-F pair to
avoid retaining several GiB of temporary data.

## Preflight

`PREFLIGHT_ONLY=1` does **not** generate the large states.  It validates the
frozen binary, NumPy availability, parameter files, expected state size, free
disk space and reports current GPU memory.  GPU memory is informational because
the exact Q6 workspace is allocated by the solver.

## Interpretation

This is diagnostic scaling evidence, not the publication timing campaign.  A
single pair per grid is intentional.  The questions are whether the ratio stays
near the x22g ~3 plateau, rises on large grids, or whether the 2048 solve reaches
a qualitatively different CG iteration regime.

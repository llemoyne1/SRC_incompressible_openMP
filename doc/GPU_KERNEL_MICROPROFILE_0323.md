# GPU kernel microprofile 0323

Script-only profiling harness.  It does not rebuild or modify the solver.  It
runs a short 0322-state SRC periodic cylinder benchmark and the VKKH comparator
under Nsight Compute (`ncu`) when available, falling back to `nvprof` or to
external timing only.

The goal is to identify the dominant CUDA kernels now that the previous measured
transfer/diagnostic bottlenecks have been removed.  In the 0322 profile the main
remaining SRC cost is the aggregate collision+thermostat kernel time; this script
is intended to split that aggregate by kernel name before any further solver
optimization.

Default run length is deliberately short (`STEPS=300`) because per-kernel GPU
profilers are expensive.  Increase only if the top-kernel ranking is noisy.

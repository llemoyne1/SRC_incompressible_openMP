# 0493a — Universal CUDA-resident species resampling routing

## Purpose

Use the already implemented 0490m/0490n/0490p resident species-resampling
chain with every boundary family supported by the CUDA solver.

Boundary conditions continue to select their own streaming and inlet/outlet
kernels. They no longer select a different resampling backend.

## Functional changes

- production species resampling is resident for periodic, wall, full-face IO,
  segmented IO, immersed-solid and Darcy/chi cases;
- the CUDA transfer plan is authoritative in production;
- the CPU passive-operation carrier is disabled;
- the sparse CPU/CUDA equivalence gate is disabled by default;
- the compact host patchback is disabled by default;
- detailed species diagnostics are disabled by default in the injection runner;
- explicit validation mode remains available.

## Physics deliberately unchanged

- Q6 projection operator, strength, species weighting and ordering;
- SRC collision and thermostat;
- mass-closure strengths;
- population thresholds and split/merge rules;
- inlet/outlet definitions;
- Darcy/Brinkman forcing and chi filtering;
- all particle masses, types and boundary parameters.

## Next patch

0493b introduces `speciesKResamplingEnable` and excludes disabled species from
all population/mass mutations while retaining them in SRC, Q6, Darcy, boundary
processing and barycentric deposits.

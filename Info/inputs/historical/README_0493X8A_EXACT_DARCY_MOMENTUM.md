# 0493x8a exact Darcy momentum diagnostic — HEAD 887181b

Runtime gate: `MPCD_DARCY_EXACT_MOMENTUM_DIAG_0493X8A=1` (default off).

The diagnostic reuses the existing Darcy cell mass/mean velocity and the exact
precomputed float lambda consumed by `apply_darcy_kick_kernel_0343`. For the
VK `darcyBrinkmanForcingMode=mean`, the accumulated diagnostic is therefore
exactly the streamwise particle momentum increment due to the Darcy mean kick,
up to reduction roundoff. Existing Darcy/topology CSV schemas are unchanged;
output is written separately to `darcy_exact_momentum_0493x8a.csv`.

# 0493x22a — article conservation rebuild

Purpose: regenerate the deleted `species_runtime_0493x14x.csv` source used for
Section 3.6 conservation reporting.

This is not a new physics campaign. It replays the qualified closed periodic
x14ai-fix1 oscillating-drop case on the frozen article binary with the same
physical parameters and seed, while disabling LiveVis, recording, and state
dumps. `SUMMARY_EVERY=10` is retained so the species diagnostics cadence matches
the historical qualification.

The article conservation analyzer reconstructs, from the species registry CSV:
- liquid and gas masses;
- liquid and gas momentum;
- total momentum and its drift norm;
- species-global 2-D peculiar kinetic-temperature proxies.

Kinetic energy is not tested as a conserved invariant because the phase-specific
thermostats act explicitly.

Run preflight first; do not launch timing benchmarks in the same operation.

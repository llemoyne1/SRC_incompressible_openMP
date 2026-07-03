# 0444 equivalence-only pass criterion fix

The 0444 end-to-end validator is a CPU/GPU equivalence validator for the clean resampling pipeline. It must not reject cases solely because the production CPU reference remap/thermal pipeline changes totals relative to the synthetic initial state.

In particular, variable-mass synthetic cases can be locally remapped toward the target cell mass, changing the total mass relative to the initial state. That is expected for this validator. The conservation residuals are kept in the CSV for auditing, but the pass criterion now uses final-state CPU/GPU equivalence only: roles, active prefix, extraction/insertion counts, remap/thermal counters, mass, momentum, kinetic energy, and fluid payload agreement.

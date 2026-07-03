# 0442 compare fix: ignore inactive-slot payload

The first 0442 smoke showed identical CPU/GPU roles, active prefix, extraction/insertion counts, total mass and momentum, but failed because the validator compared payload fields (`x/y/vx/vy/mass`) in inactive/free slots.

Inactive slot payload is not semantically meaningful after extraction/insertion: CPU and CUDA may leave different stale values as long as the slot role is inactive and the active prefix, pool accounting, and fluid totals remain consistent.

This fix changes the 0442 validator to compare payload values only for slots that are fluid on both CPU and GPU. It keeps strict checks on:

- role mismatches;
- type mismatches;
- fluid/inactive role counts;
- active-prefix validity;
- total fluid mass, momentum and kinetic energy;
- extraction/insertion counts and invalid-operation counters.

It also fixes the markdown runner report, which previously printed `{gpuApplyTotalSeconds}` literally instead of the CSV value.

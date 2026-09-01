0493x14f-fix1
===============
Corrected q6-g-f quick validation for the per-type thermostat.

Why:
The first x14f used a global apparent temperature K_rel/(N-1). In the injection
case that quantity contains resolved cell-to-cell hydrodynamic velocity variance
and is not the target of cell_relative_rescale. The liquid therefore failed a
20% band even though that does not demonstrate thermostat failure.

This runner sets gridShiftEnable=false intentionally and checks the exact
post-thermostat cell-local temperature of each type from the final .smpcd dump.
No C++/CUDA file is modified. ./livevis_control.kv is never modified.

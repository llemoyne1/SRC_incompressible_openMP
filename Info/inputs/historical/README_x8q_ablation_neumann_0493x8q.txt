x8q Neumann kinetic ablation — air-assisted atomizer
=====================================================

Purpose
-------
Keep openBoundaryOutletMode=neumann and the Q6/pressure Neumann treatment,
but disable only the 0493x8q kinetic exterior ghost continuation.

1) From the SRC_GPU-SURF repository root, apply:

   git apply --check /path/to/x8q_ablation_source.patch
   git apply /path/to/x8q_ablation_source.patch

2) Copy both wrappers into scripts/:

   cp /path/to/scripts/run_*x8q*_air_assisted_atomizer.sh scripts/
   chmod +x scripts/run_*x8q*_air_assisted_atomizer.sh

3) Rebuild the usual 0486 binary:

   bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

Recommended controlled A/B test
-------------------------------
Use the same pre-impact dump for both runs (state_step_4000.smpcd is a good
choice for the supplied movie). Run sequentially, not concurrently.

A — reference, x8q ON:

   RESTART=1 \
   RESTART_STATE=runs/<reference-run>/output/state_step_4000.smpcd \
   RESTART_TAG=from4000 \
   STEPS=1500 \
   CLEAN_RUN_ROOT=1 \
   bash scripts/run_reference_x8q_on_air_assisted_atomizer.sh

B — ablation, x8q OFF:

   RESTART=1 \
   RESTART_STATE=runs/<reference-run>/output/state_step_4000.smpcd \
   RESTART_TAG=from4000 \
   STEPS=1500 \
   CLEAN_RUN_ROOT=1 \
   bash scripts/run_ablate_x8q_air_assisted_atomizer.sh

The restart is a controlled A/B initial condition, but not necessarily a
bitwise continuation of the original trajectory because stochastic step/RNG
counters may restart. If the A/B result is ambiguous, repeat both cases from
the original initial state through the outlet-impact time.

Expected contract
-----------------
Reference wrapper:
- openBoundaryOutletMode remains neumann.
- x8q kinetic Neumann continuation remains ON.

Ablation wrapper:
- openBoundaryOutletMode remains neumann.
- Q6 predictor/pressure Neumann path remains enabled.
- only x8q kinetic Neumann ghosts are disabled.
- particles crossing the outlet are absorbed and are not replenished by x8q.

Interpretation
--------------
If the reference reproduces the large uy instability while the ablation stays
regular as the liquid front traverses the right outlet, x8q is causally
implicated. The x8q-OFF case is diagnostic only, not a production outlet BC.

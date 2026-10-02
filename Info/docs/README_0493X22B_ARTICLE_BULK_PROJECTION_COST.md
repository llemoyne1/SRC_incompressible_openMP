# 0493x22b — Article Section 3.6 bulk projection cost

Purpose: measure the computational cost of adding the qualified liquid particle/field projection to the nominal article SRC fluid, without free surface, gas, capillarity, Darcy, solids or resampling.

Fixed article point: 256x256, gamma=8, alpha=120 deg, lambdaMean/h=0.72, ell=0.5744768837780632, h=1/256, dt=0.0063471328149122585, kBT=0.125, m=1, seed=4933301.

A0: underlying SRC. A1: same initial state and seed, production single-phase Q6-G-F liquid projection.

Timing: two excluded 100-step warm-ups; five paired 1500-step measurements with AB/BA alternation; LiveVis/recording/state dumps disabled. Binary SHA is required to match the frozen article binary.

No solver/source modification is performed.

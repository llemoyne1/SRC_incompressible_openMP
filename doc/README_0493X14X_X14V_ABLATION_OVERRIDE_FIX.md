# 0493x14x x14v ablation override fix

Runner-only correction. No C++/CUDA change.

The original x14x runner unconditionally exported:
    MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
which overwrote an environment override supplied on the command line.

This correction keeps x14v ON by default but allows:
    MPCD_X14V_GAS_KINETIC_EXCESS_KICK=0
for a true ablation. The resolved value is also written to the environment log
and printed in the startup CHAIN line.

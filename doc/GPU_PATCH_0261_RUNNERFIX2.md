# GPU patch 0261 runnerfix2

Fixes the remaining `set -u` scope issue in `scripts/run_cuda_classic_src_wall_resident_0261.sh` by defining `summary_every_current` in the main grid loop before it is written to the CSV.

This patch changes only the runner; it does not modify C++/CUDA code.

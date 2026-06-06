# GPU patch 0261 runner fix

Corrects `scripts/run_cuda_classic_src_wall_resident_0261.sh` so that the CSV field `summaryEvery` is computed in the main loop instead of referencing the local `summary_every` variable from `run_validation_logged()`.

This fixes the Bash `set -u` failure:

```text
summary_every: unbound variable
```

No C++/CUDA source is changed.

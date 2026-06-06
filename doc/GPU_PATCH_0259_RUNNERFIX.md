# GPU patch 0259 runner fix

This small differential fixes the 0259 validation runner.

The original runner used the local shell variable `minimal_download_0257` outside
its function scope while `set -u` was enabled. As a result, the script stopped
with:

```text
minimal_download_0257: unbound variable
```

The fixed runner computes a CSV-row flag `row_minimal_download` from the current
mode name in the outer loop instead of reading the function-local variable.

No C++/CUDA source is changed by this runner-only fix.

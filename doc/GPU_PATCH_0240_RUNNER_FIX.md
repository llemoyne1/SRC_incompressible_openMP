# GPU patch 0240 runner fix

This small corrective patch fixes the 0240 smoke launcher after the first
compile correction.

The repository contains the validated 0239 script as:

```text
scripts/run_cuda_resampling_persistent_state_ops_smoke_0239.sh
```

but the original 0240 launcher looked for:

```text
scripts/run_cuda_resampling_persistent_state_ops_0239.sh
```

and required executable bits with `-x`.  In exchanged archives the executable
bit may be lost, so the corrected runner now checks `-f` and invokes scripts
through `bash`.

Apply by copying this archive over the repository root, then run:

```bash
bash scripts/run_cuda_resampling_persistent_active_path_0240.sh
```

This only fixes the launcher.  The current 0240 C++ bridge still falls back to
the CPU active resampling path until it is wired to the 0239 persistent-state
CUDA symbols.

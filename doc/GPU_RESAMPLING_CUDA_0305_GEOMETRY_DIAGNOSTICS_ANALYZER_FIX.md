# 0305 geometry diagnostics analyzer fix

This small follow-up fixes a Python scoping issue in
`scripts/analyze_cuda_resampling_geometry_diagnostics_0305.py`.

The analyzer defined a helper function named `f(row, key)` and later reused
`f` as a file-handle variable inside `main()`. In Python, that later assignment
makes `f` local to `main()`, so the earlier list comprehension
`[f(r, key) for r in rows]` raises:

```text
UnboundLocalError: cannot access local variable 'f' where it is not associated with a value
```

The fix renames file handles to `fh` / `out_fh`. It does not change CUDA code,
runners, diagnostics, or simulation outputs.

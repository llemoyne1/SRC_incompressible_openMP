# GPU rollback 0329c — remove rotation-table cache experiment

This archive removes the experimental 0329 rotation-table cache from the SRC classic CUDA resident benchmark path.

## Rationale

The 0329/0329b experiment compiled and ran, but the disabled-runtime check showed that the 0327b baseline remains faster and more stable. The 0329 cache path increased setup/upload overhead and did not demonstrate a net gain.

## Kept state

This rollback restores the code to the validated 0327b/0328 state:

- 0318b wall+circle resident path kept.
- 0319 skip wall virtual-particle diagnostics kept.
- 0320 wall fast diagnostics defaults kept.
- 0321 fast thermostat diagnostics kept.
- 0322 shared thermostat/rotation setup kept.
- 0324/0328 kernel breakdown append profiling kept.
- 0327b skip host cellId sentinel fill kept.
- 0325 rejected fusion remains absent.
- 0329 rotation-table cache is removed.

## Expected checks

After applying and rebuilding, the runner output should contain no `[0329-demo]` line and no `[0325-demo]` line. Performance should return to the 0327b baseline band, approximately 6.8 s per 10000 steps on the reference VK periodic benchmark after cold-start.

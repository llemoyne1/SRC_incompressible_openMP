# 0163b header fix for StepProfile declarations

This differential archive restores the public StepProfile declarations required by
`src/main_src_mpcd_base.cpp` and `src/src_mpcd_base.cpp` after applying the 0163
resampling guard optimization on a branch whose `include/src_mpcd_base.h` still
comes from the pre-0157 non-profiled state.

It adds to `include/src_mpcd_base.h`:

- `StepProfilePhaseCount`
- `step_profile_phase_name(...)`
- `StepProfile`
- `StepResult::profile`

No physical algorithm is changed.

Apply after 0163 if the build reports:

```text
error: ‘StepProfilePhaseCount’ is not a member of ‘mpcd’
```

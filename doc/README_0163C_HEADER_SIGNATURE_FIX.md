# 0163c header signature fix

This small follow-up patch completes the 0163 header interface.

It updates `include/src_mpcd_base.h` so that the public declaration of
`mpcd::run_src_mpcd_base_step(...)` matches the implementation and the
profiled main program:

```cpp
StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace,
                                  bool collectResamplingDiagnosticsWhenDisabled = true);
```

The default value preserves backward-compatible behavior for existing callers
that do not pass the new boolean argument. The main benchmark/profiling program
passes the explicit value computed from `summaryEvery`, so the optimized path is
unchanged.

No numerical or physical operation is modified.

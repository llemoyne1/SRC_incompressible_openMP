# GPU non-regression Q6/resampling/virial — 0326d

0326d is a script-only strict non-regression harness for the post-0322 clean CUDA branch.

The key correction relative to 0326b/0326c is that hybrid checks do **not** set `srcClassicCudaModeEnable=true`.
In the solver, classic mode is an operator-level short-circuit for Q6 and closed-capacity. Therefore the correct hybrid smoke is selected by environment variables only:

```text
CUDA persistent collision only -> CPU Q6 / resampling / virial -> CPU thermostat
```

The strict parser fails a target if the advertised module is not actually exercised in `validation_summary_0162.csv`.

Expected targets:

- `q6_only_tg`: CPU SRC + Q6, no resampling.
- `resampling_only_tg`: CPU SRC + resampling, no Q6.
- `hybrid_cuda_q6_resampling_tg`: environment-selected CUDA persistent collision plus CPU Q6/resampling/thermostat, with `srcClassicCudaModeEnable=false`.
- `hybrid_cuda_piston_virial`: environment-selected CUDA persistent piston collision plus CPU Q6/resampling/closed-capacity virial/thermostat, with `srcClassicCudaModeEnable=false`.

No solver source is modified.

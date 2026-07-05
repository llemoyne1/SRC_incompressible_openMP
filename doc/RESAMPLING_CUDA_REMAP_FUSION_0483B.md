# 0483b resident remap fusion micro-variant

Scope: test a minimal micro-architectural variant of the non-committed 0483 fused remap kernel.

0483 fused the target thermal energy accumulation and remap mass-apply kernels. The first A/B comparison showed correct CPU/CUDA physics but mixed performance: favorable for `src-q6-resampling`, not robust for `src-resampling` on the large `128x128_g40` case.

0483b keeps the same numerical semantics but changes the instruction order inside the fused kernel:

```cpp
const double targetContribution = 0.5 * massBefore * (dux * dux + duy * duy);
mass[i] = massBefore * scale[c];
atomicAdd(&targetEnergy[c], targetContribution);
```

The intended effect is to let the global mass write issue before the contended per-cell atomic accumulation and to slightly shorten live ranges around the atomic operation. The target contribution still uses `massBefore`, while subsequent current-energy accumulation sees the remapped mass.

Validation strategy: no new broad physical matrix. The 0483 candidate already passed the 18-row CPU/CUDA physical stress matrix. For 0483b, run one long performance A/B only:

- baseline: clean `b4d0a77` / 0482
- candidate: current tree after 0483b patch
- grid: `128x128x40`
- seed: `1628638`
- modes: `src-resampling`, `src-q6-resampling`
- steps: 2000

Expected number of solver executions: 8 = 1 grid × 1 seed × 2 modes × 2 versions × CPU/CUDA.

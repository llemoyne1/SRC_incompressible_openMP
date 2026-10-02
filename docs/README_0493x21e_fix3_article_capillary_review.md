# 0493x21e-fix3 — article capillary analysis review

Analysis-only patch. It does not modify or rebuild the solver and does not launch simulations.

Purpose:
- preserve the signed offline x6c -> p3/Scharr -> alpha=0.5 -> x9r curvature;
- preserve the signed x9e `measuredPressureJump` convention;
- stop interpreting the v1 free-fit slope as `sigma_eff` before the pressure observable is validated;
- reuse the already-existing active plateau pressure histories as an independent diagnostic;
- label `interfaceSpeedRms/U_sigma` as thermal-inclusive rather than a pure spurious-current amplitude.

The original `article_capillary_outputs` directory is not modified. Results are written to:
`runs/0493x21e_article_capillary_radius_s10000/article_capillary_review_fix3/`.

Run from the repository root:

```bash
bash scripts/run_0493x21e_fix3_article_capillary_review.sh
```

Expected scientific status before reviewing the new output: `REVIEW_PRESSURE_OBSERVABLE`; `sigmaEffective=NOT_ASSIGNED`.

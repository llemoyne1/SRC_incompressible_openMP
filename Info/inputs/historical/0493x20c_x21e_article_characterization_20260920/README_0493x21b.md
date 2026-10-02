# 0493x21b — weak Young–Laplace pilot at the x13h fluid point

Purpose: validate the sigma*kappa -> solved-Q6 pressure mechanism in a weak, well-resolved static regime, deliberately separated from the strong-sigma Taylor–Culick benchmark.

Defaults: gamma=8, alphaSRC=120 deg, lambda/h=0.72, R/h=64, sigma=120, Rmin/h=4, x12a Rc/h=25.298, one paired seed, 316 steps, summary every 3.

Run: `LIVE_PROGRESS=1 bash scripts/run_0493x21b_capillary_static_weak.sh --run`.

Do not launch a radius sweep unless `pilot_analysis/capillary_pilot_weak_decision_0493x21b.txt` is PASS.

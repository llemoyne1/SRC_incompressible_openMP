# 0493l — Particle-weight transport diagnostic

This patch is additive and diagnostic only. It does not change the solver,
resampling, collision, thermostat, Q6, empty-refill or any qualification gate.
No rebuild and no rerun are required.

The diagnostic treats the current `particleMass` field as the effective
particle weight actually used by the solver and measures whether resampling
broadens that weight distribution or correlates it with Taylor--Green vortex
radius and species composition.

## Quantities

For all active particles and separately for species 1 and 2:

- min, p01, p05, median, p95, p99 and max particle weight;
- coefficient of variation squared `CV²`;
- Gini coefficient;
- effective sample size `ESS=(sum w)^2/sum(w^2)` and `ESS/N`;
- mass fraction carried by the heaviest 1% and 5% of particles;
- count and mass fractions outside the initial weight interval;
- particle-level correlations between weight, normalized distance to the
  nearest vortex center, binary composition basis, radial velocity and radial-speed magnitude;
- number-weighted and mass-weighted radial velocity, plus the difference
  between the heaviest and lightest 10% of carriers;
- cell-level counts, masses, weight dispersion and effective carrier count;
- radial profiles around vortex centers;
- paired `src-resampling` / `src` comparisons.

The normalized vortex radius is zero at a vortex center and one at the corner
of its periodic Voronoi cell.

## Outputs

- `weight_transport_0493l_summary.csv`
- `weight_transport_0493l_pairs.csv`
- `weight_transport_0493l_radial_profiles.csv`
- `weight_transport_0493l_cells.csv`
- `weight_transport_0493l.md`

## Existing 64x64 TG run

```bash
RUN_ROOT=runs/0493k_tg_binary_64_m2_pilot_1500 \
SEED=493101 \
SCENARIO=binary_species \
RUN_MODES="src src-resampling" \
STEPS_LIST="0 200 400 800 1500" \
NX=64 NY=64 TG_MODE=2 \
bash scripts/run_0493l_particle_weight_transport.sh
```

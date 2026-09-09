# 0493x13d transport follow-up

Campaign tooling only; no `src/` or `include/` modification.

## H-Ny256
Targeted long-wave transverse-shear qualification at the A1 microscopic point:
- gamma: 8, 14, 20
- alpha: 120 deg
- lambda/h: 0.48
- U0: 0.05
- wavelength: 256 collision cells
- seeds: 4931411..4931414 (paired with x13c)
- observation time: 1.4 SRD positioning e-folds, with no T=28 cap.

Outputs:
- `H_longwave_runs_0493x13d.csv`
- `H_longwave_summary_0493x13d.csv`
- `H_longwave_locality_0493x13d.csv`

## C-damping
No new simulation. Reuses completed x13c Cstat state dumps for A1/G08/G10 at eps=0.04/0.08.
Fits the phase-projected density Fourier mode directly:

rho_k(t) = C + exp(-beta t) [A cos(omega t) + B sin(omega t)]

and reports:
- nu_L = 2 beta / k^2
- c_s = sqrt(omega^2 + beta^2) / k

Bootstrap resamples whole realizations with replacement. Default: 500 draws.

Outputs:
- `Cdamp_individual_replicates_0493x13d.csv`
- `Cdamp_group_statistics_0493x13d.csv`
- `Cdamp_fluid_qualification_0493x13d.csv`

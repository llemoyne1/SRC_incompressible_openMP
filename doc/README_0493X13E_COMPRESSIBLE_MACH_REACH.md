# 0493x13e — G08 compressible Mach/reach qualification

Purpose: determine how far the x13d G08 constitutive point remains wavelength-converged as the coherent longitudinal Mach number rises, then translate the qualified Mach range into characteristic-cell requirements for Re=1e3, 3e3, 1e4.

Frozen solver: SRC-only; no `src/` or `include/` changes. Thermostat remains `cell_relative_rescale`, so this is an **isothermal/quasi-isothermal compressible** qualification, not an energy-conserving shock-thermodynamics campaign.

Reference G08 coefficients from x13d:
- gamma = 8
- alpha = 120 deg
- lambda/h = 0.48
- nu_T = 5.328464868639473e-4
- c_s = 0.3554482475790296
- H_h = c_s h / nu_T ~ 2.606

Initial condition: exact uniform density, longitudinal velocity mode `u_x=U0 sin(2 pi x/Lx)`, with `U0=Ma*c_s`. This avoids low-gamma density quantization and directly controls the initial coherent Mach number. Nonlinearity is intentionally allowed to generate density modes and higher harmonics.

Default axes:
- Ma = 0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.70, 0.90, 1.00
- wavelength = 128, 256 cells
- Ny = 16
- 3 paired seeds
- 3 acoustic periods
- 80 state-dump intervals

The runner continues after an individual high-Mach failure by default (`CONTINUE_ON_FAILURE=1`), because a stress-case failure is data rather than a reason to lose the rest of the matrix.

Analysis uses the existing 0493w1 state reader and measures Fourier modes m=1..4 of density and longitudinal velocity. The acoustic modal energy is `|u_m|^2 + c_s^2 |rho_m|^2`. It reports first-quarter-cycle phase speed, harmonic-energy transfer, Eulerian column density extrema, and 128/256 wavelength consistency.

Grades:
- `LINEAR_COEFFICIENTS_VALID`: phase speed remains within 5% of x13d and wavelength-converged, with <=10% peak harmonic fraction over the first acoustic cycle.
- `NONLINEAR_RESOLVED`: nonlinear harmonic generation is significant but the 128/256 responses remain converged.
- `NONLINEAR_REVIEW`: some wavelength sensitivity remains.
- `UNRESOLVED_OR_KINETIC`: strong wavelength dependence.

The reach table uses `Re = Ma * (L/h) * H_h`. It does **not** claim a Re=1e4 simulation is affordable; it reports required characteristic cells and the corresponding gamma=8 particle count for a square 2-D domain so feasibility can be judged before any giant run.

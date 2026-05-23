# Liquid-closure Q6/Q9/virial validation status

This document records the current validation status of the incompressible/liquid
closure branch.  The intent is to keep the C++ implementation as close as
possible to the MATLAB validation line, especially for the `general_bc` / low-k
mass-flux projection logic.

## 1. Architecture currently validated

The branch uses a single generic elliptic projection core rather than separate
Q6, Q9, virial or filtering solvers.  The common form is

```text
F_new = F_base - alpha grad(phi)
div(F_new) = target
```

The same discrete divergence/gradient/operator machinery is used for:

- Q6 velocity projection;
- Q9 mass-flux projection;
- channel and periodic elliptic boundary configurations;
- elliptic low-pass filtering of Q9 targets and low-k mismatch fields;
- future smoothing/filtering needs for interface and surface-tension modules.

This is the intended C++ analogue of the MATLAB path based on `general_bc` and
`relax_to_uniform_lowk`.

## 2. Q6 validation summary

Validated components:

- manufactured periodic elliptic projection;
- manufactured periodic-x / wall-y elliptic projection;
- periodic Taylor-Green high-SNR test;
- periodic-x / wall-y Poiseuille channel;
- moving active-domain piston, with geometric divergence target.

Important interpretation for moving domains: for a compressing active domain,
Q6 should not force zero divergence.  It should match the geometric divergence
of the moving boundary.  For the piston case `yTop: 0.95 -> 0.90`, the expected
terminal divergence scale is approximately `0.001 / 0.90 = 0.001111`.

## 3. Q9 filtered mass-flux validation summary

The stable Q9 formulation is the MATLAB-like low-k formulation:

```text
targetRaw       = beta/dt * (M - M_ref)
densityTarget   = elliptic_lowpass(targetRaw)
rhsFull         = densityTarget - div(J_base)
rhsLowK         = elliptic_lowpass(rhsFull)
projectionTarget = div(J_base) + rhsLowK
```

The essential point is that Q9 must not correct the high-frequency cellwise
mismatch `target - div(J_base)`.  It must correct the low-k mismatch only.

Validated Q9 cases:

- periodic Q9 smoke test;
- Q9 beta sweep showing that raw/unfiltered Q9 is not usable;
- filtered Q9 beta sweep;
- filtered Q9 Taylor-Green;
- filtered Q9 Poiseuille channel;
- filtered Q9 moving active-domain piston;
- filtered Q9 plus virial on piston and density-wave tests.

### Q9 low-k incident retained as a regression lesson

An intermediate implementation filtered the density target but not the full
low-k mismatch.  In a channel Q9 run, this eventually produced huge local kicks,
a ballistic particle and a wall-reflection crash.  The correction was not to add
a limiter, but to restore the MATLAB-like low-k mismatch filtering.  See
`docs/Q9_LOWK_FILTERING_INCIDENT.md`.

## 4. Virial EOS closure validation summary

The virial module is optional and decoupled from Q6/Q9.  The diagnostic EOS is

```text
P_vir = K_virial * (rho - rho_EOS_ref)
P_tot = P_kin + P_vir
```

The dynamic kick is driven by the gradient of the selected pressure-drive field,
followed by exact global momentum correction.  The module remains fully
disabled unless explicitly enabled.

### Piston EOS validation

For active-domain piston compression, the virial contribution scales linearly
with `Kvirial`, while mass, active-area compression, temperature and wall safety
remain stable.  The stress compression case `yTop: 0.95 -> 0.80` makes the EOS
pressure response very visible.  For example, the total-pressure ratio reaches
approximately `5.72` for `K=0.25, beta=0.10` and `10.03` for `K=0.50, beta=0.20`,
while the applied velocity kick remains small compared with the thermal speed.

### Density-wave virial validation

A fixed channel with periodic x, solid thermal y-walls and an imposed low-k
initial density modulation is the clearest test of dynamic virial response.  It
creates a spatial pressure gradient without global piston compression.

The density-wave test shows the expected trend: stronger virial settings relax
the low-k density mode faster.  In the reference run, the final density-mode
absolute ratio decreases from approximately `0.218` for Q9-filtered without
virial to `0.202` for `K=0.5, beta=0.2` and `0.148` for `K=1.0, beta=0.5`.
Particle speeds, thermal control and wall reflections remain stable.

## 5. Liquid-closure dynamic validation suite

The dynamic suite currently compares:

```text
classic
q6
q9_filtered
q9_virial
```

on two canonical flows:

- Taylor-Green periodic high-SNR short run;
- periodic-x / wall-y Poiseuille channel.

The purpose is not to tune final transport coefficients, but to verify that the
liquid-closure stack preserves coherent flow structures while retaining stable
Q6/Q9/virial diagnostics.

### Taylor-Green result pattern

The accepted behavior is:

- Q6/Q9/virial should keep a Taylor-Green amplitude close to the Q6/Q9 filtered
  baseline;
- the pattern correlation should remain much better than the classic baseline;
- Q9 and virial corrections should remain small compared with the thermal speed.

Reference result from the current suite:

```text
amplitudeRatio:
  classic      ~0.309
  q6           ~0.312
  q9_filtered  ~0.306
  q9_virial    ~0.302

correlationEnd:
  classic      ~0.742
  q6           ~0.884
  q9_filtered  ~0.883
  q9_virial    ~0.879
```

### Poiseuille result pattern

The accepted behavior is:

- Q9-filtered should preserve or improve the fitted parabolic profile;
- Q9+virial should remain close to the Q9-filtered channel result;
- effective viscosity may shift moderately and must be treated as a measured
  transport property of the liquid closure, not assumed identical to classic
  SRC/MPCD;
- wall safety and particle-speed diagnostics must remain normal.

Reference result from the current suite:

```text
fitR2:
  classic      ~0.770
  q6           ~0.708
  q9_filtered  ~0.851
  q9_virial    ~0.810

nuEff:
  classic      ~0.117
  q9_filtered  ~0.124
  q9_virial    ~0.114
```

## 6. Current interpretation

At this stage, the first-level liquid-closure stack is validated in C++:

```text
Q6 velocity projection
Q9 filtered low-k mass-flux projection
optional virial EOS pressure/kick
moving active domains
solid thermal channel walls
```

The most important implementation constraint going forward is to keep Q9 close
to the MATLAB method.  In particular, avoid reverting to raw cellwise density or
mass-flux correction.  Low-k filtering is not a cosmetic stabilizer; it is part
of the method.

## 7. Suggested next steps

Recommended next steps are:

1. keep this stack as the reference liquid-closure baseline;
2. avoid adding limiters unless diagnostics show a specific need;
3. use density-wave and piston tests for virial/EOS changes;
4. use Taylor-Green and Poiseuille for dynamic regression;
5. treat von Karman as a later dedicated benchmark with its own resolution and
   runtime requirements;
6. develop surface tension later as a disabled-by-default module using the same
   elliptic/div-grad/filtering core.

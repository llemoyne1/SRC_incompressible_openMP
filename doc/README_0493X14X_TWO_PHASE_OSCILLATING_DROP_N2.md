# 0493x14x — two-phase oscillating drop n=2

Runner/tooling-only qualification. No C++/CUDA change and no new runtime diagnostic.

The test reuses the current x14 liquid/gas chain unchanged:

- liquid: x9 + x10o + CIC + Q2 + x10p/q + x10u + x10v full-vector + x12a;
- gas: type 2, `mG=0.1`, `kBT_G=0.08`, `q6Strength=0`;
- x6g: `eos_accessible_volume`;
- x14l: gas normal specular reflection in the moving-interface frame;
- x14v: gas kinetic normal excess transferred collectively to the liquid;
- common SRC collisions provide tangential liquid/gas coupling.

The box is periodic in x and y, so no physical wall participates in the result.

The initial interface is

`r(theta)=R[sqrt(1-eps^2/2)+eps cos(2 theta)]`

with exact continuous area `pi R^2`.  Default `eps=0.04` improves signal-to-noise while remaining in the small-amplitude range used previously.

For an unbounded 2-D cylindrical interface between two inviscid fluids,

`omega_n^2 = n(n^2-1) sigma / ((rho_L+rho_G) R^3)`.

The n=2 analysis uses the existing x9f signed quadrupole observable.  Damping is fitted freely and reported as a measurement only; no two-viscous-fluid damping formula is imposed.

Default point: 400x400, h=1/256, gamma=20, R/h=40, dt=0.002, sigma=2560, TL=0.02, TG=0.08.  It gives approximately `omega_2=1.6711455`, `T_2=3.7598075`, about 1880 steps/period.  The default 6000-step run therefore covers about 3.19 periods.

`./livevis_control.kv` is read-only.  The runner defaults to LiveVis enabled, film recording every 100 steps, and state dumps every 2000 steps (adapted from the usual 1000-step restart cadence because the state contains 3.2 million particles).

A runner-level `RESTART=1 RESTART_STATE=/path/state_step_N.smpcd` hook is provided. Restart output is placed in a separate segment and never overwrites the original diagnostics.

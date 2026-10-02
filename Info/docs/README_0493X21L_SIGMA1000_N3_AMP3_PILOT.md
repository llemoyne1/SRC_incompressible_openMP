# 0493x21l — sigma=1000, n=3, amplitude=3h pilot

Purpose: discriminate between the noisy-but-nearly-linear a=2h result and the
stable-but-frequency-shifted a=4h result.  The solver, binary, capillary physics,
thermostat, x13h surface-free chain, x12cal analyzer, fit window and qualification
thresholds are unchanged.  Only the initial wave amplitude is set to 3h.

Parameters retained from the article campaign:
- sigma_declared = 1000
- mode n = 3
- seeds = 4932501, 4933501, 4934501
- Nx x Ny = 256 x 128, Lx x Ly = 1 x 0.5
- gamma = 8, kBT = 0.125, dt = 0.0063471328149122585
- mean depth H = 0.25
- amplitude = 3h
- a/lambda = 0.03515625
- k a = 0.220893233456
- same production binary SHA-256 gate as x21i/x21k

The runner produces the standard x12cal mode CSV, a strict gate, and a
non-gating same-seed comparison a=2h / 3h / 4h when the two baselines exist.
No solver source modification and no compilation are performed.

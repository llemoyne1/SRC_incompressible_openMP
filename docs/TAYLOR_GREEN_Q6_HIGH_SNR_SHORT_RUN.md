# High-SNR short Taylor--Green validation for Q6

The first Taylor--Green validation used `gamma=20`, `U0=0.05`, and `tEnd=2`.
That run validates the Q6 projection numerically, but the Taylor--Green mode
quickly becomes too weak compared with thermal and sampling noise.

This short high-SNR variant is designed to keep the coherent periodic mode
measurable over the analysis window.

## Parameters

The example uses:

```text
Nx = Ny = 64
gamma = 80
U0 = 0.08
kBT = 0.01
dt = 0.001
nSteps = 500
tEnd = 0.5
```

The higher `gamma` reduces cell-sampling noise. The moderately larger `U0`
increases the modal signal without making this a high-speed wall or inlet test.
The shorter horizon avoids judging the method after the coherent mode has nearly
fully decayed.

## Generate the initial state

```matlab
% From the matlab/ directory:
state = generate_taylor_green_high_snr_short_state();
```

This writes:

```text
initial_state_tg_64x64_g80_u0p08_kbt0p01.smpcd
```

## Run classic and Q6

```bash
./build/src_mpcd_base examples/params_taylor_green_high_snr_classic_64x64_g80_short.kv
./build/src_mpcd_base examples/params_taylor_green_high_snr_q6_64x64_g80_short.kv
```

## Analyze

```matlab
% From the matlab/ directory:
out = validate_taylor_green_q6_high_snr_short( ...
    'makePlots', true, ...
    'plotFinalFields', true);
```

The important checks are:

```text
q6Converged = 1 on projected steps
q6DivAfterProjectedFluxRms << q6DivBeforeRms
mass conserved
momentum corrected
kBT stable
Taylor--Green modal amplitude remains measurable at tEnd
Q6 dumped-field divergence lower than classic dumped-field divergence
```

The dumped-field divergence is a post-processing diagnostic reconstructed from
particle dumps. It is not the same operator as the face-field divergence used by
the Q6 projection core. The runtime Q6 columns remain the primary projection
operator diagnostics.

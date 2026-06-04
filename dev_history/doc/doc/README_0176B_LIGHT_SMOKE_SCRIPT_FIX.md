# 0176b - OpenMP-light smoke script fix

This patch fixes only `scripts/run_openmp_light_smoke_0176.sh`.

The first 0176 smoke script used legacy short option names for
`generate_validation_state_0162.py`:

- `--out`
- `--nx`
- `--ny`
- `--flow`
- `--kbt`

The current generator expects:

- `--output`
- `--Nx`
- `--Ny`
- `--flow-mode`
- `--kBT`

No C++ source file is modified by this patch.

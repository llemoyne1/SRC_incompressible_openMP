# 0493x7v — Von Kármán symmetry-breaking growth

## Purpose

This MATLAB-only diagnostic measures the growth of the symmetry-breaking wake mode in the already generated Von Kármán dumps. It is designed to discriminate SRC, legacy Q6, and Q6-g-f on both VK configurations without rerunning the solver.

It consumes the complete x7u timeseries and rereads only dumps with `4 <= tauD <= 15` and `tauL < 0.8` by default.

## Correct reflection parity

For reflection about `y=y0`, with `y' = 2*y0-y`, a symmetric cylinder wake obeys

- `Ux(y) = Ux(y')`
- `Uy(y) = -Uy(y')`
- `omega(y) = -omega(y')`

The symmetry-breaking fields are therefore

- `Ux_break = (Ux(y)-Ux(y'))/2`
- `Uy_break = (Uy(y)+Uy(y'))/2`
- `omega_break = (omega(y)+omega(y'))/2`

The primary reflection axis is the cylinder centreline. A channel-centreline analysis is also produced as a sensitivity check because the present cylinder centre is slightly offset from `Ly/2`.

## Why POD is used

Instantaneous MPCD parity fields contain a stochastic noise floor. A direct RMS of `omega_break` is therefore not a clean linear-instability amplitude, especially when the coherent wake is weak.

For each geometry x7v builds the first two POD modes from the **SRC parity-breaking velocity field** in the near+mid wake. Legacy Q6 and Q6-g-f are then projected onto this same SRC basis. The two coefficients form a quadrature pair for an oscillating shedding mode, and the envelope

`A = sqrt(a1^2+a2^2)`

is fitted rather than either signed coefficient separately.

Each mode also gets its own self-POD pair. This distinguishes genuine suppression from development of a different symmetry-breaking structure.

## Growth rate

The primary comparable rate is obtained from

`log(A) = c + sigmaD*tauD`

over `4 <= tauD <= 12`.

`sigmaD` is the effective logarithmic growth per convected cylinder diameter. The script also reports the dimensional `d(log A)/dt`, R², point count, and growth factor. Secondary windows `4-8`, `8-12`, and `12-15` are included to reveal onset and saturation.

A fit is labelled:

- `PASS_LINEAR` when slope > 0 and R² >= 0.70;
- `WEAK_LINEARITY` when slope > 0 but the exponential approximation is weak;
- `DECAY_OR_FLAT` for a non-positive slope;
- `INSUFFICIENT_POINTS` when fewer than six points are available.

## Mode aliases

`q6` and `src-q6` are canonicalized to `src-q6`.

`q6-g-f`, `src-q6-g-f`, and `src+q6-g-f` are canonicalized to `src-q6-g-f`.

If multiple directories exist for the same canonical mode, x7v selects the one with the largest `tauD` extent, then the largest frame count. The decision is written to `vk_symmetry_breaking_selection_0493x7v.csv`.

## Usage

From the repository `matlab/` directory:

```matlab
run_vk_symmetry_breaking_0493x7v
```

The x7u timeseries is expected at:

`../runs/vk_vorticity_transport_0493x7u_analysis/vk_vorticity_timeseries_0493x7u.csv`

## Outputs

Under `../runs/vk_symmetry_breaking_0493x7v_analysis/`:

- `vk_symmetry_breaking_selection_0493x7v.csv`
- `vk_symmetry_breaking_timeseries_0493x7v.csv`
- `vk_symmetry_breaking_summary_0493x7v.csv`
- `vk_symmetry_breaking_pod_0493x7v.mat`
- per-mode amplitude/phase figures
- per-configuration SRC/Q6/Q6-g-f comparison figures
- a suite growth-rate summary figure

The most important columns to return are the cylinder-axis rows of the summary: `sigmaD_common_primary`, `r2D_common_primary`, `sigmaD_self_primary`, `r2D_self_primary`, `commonPodCapture`, `selfPodCapture`, and the three window amplitudes.

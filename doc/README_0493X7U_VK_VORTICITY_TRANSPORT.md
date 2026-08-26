# 0493x7u — Von Kármán vorticity-transport post-processing

This patch adds MATLAB-only post-processing for the existing VK particle dumps. It does not modify or rerun the solver.

Run from the repository `matlab/` directory. The launcher deliberately uses `../runs/*`.

## Files

- `matlab/analyze_vk_vorticity_transport_0493x7u.m`
- `matlab/run_vk_vorticity_transport_0493x7u.m`

The analyzer reuses the existing `read_smpcd_state`, `bin_smpcd_state`, and `parse_smpcd_kv` helpers.

## Analysis contract

The primary analysis grid is defined physically by `D/20`. For the current `Lx=1.5`, `Ly=0.4`, `D=0.08` VK geometry this is exactly `375 x 100`, independently of the native MPCD grid. A `D/16` sensitivity pass is enabled by default.

For every dump it measures:

- mass-weighted upstream and global velocity;
- mode-specific `Re_D` when a compatible viscosity is known;
- convective clocks `tau_D = integral Uinf dt / D` and `tau_L = integral Uinf dt / Lx`;
- RMS vorticity and absolute circulation in the cylinder-generation annulus, near wake, mid wake, and far wake;
- generator-to-near, near-to-mid, and mid-to-far vorticity survival ratios;
- signed and antisymmetric wake circulation;
- transverse-velocity probes at `2D` and `4D` downstream;
- wake momentum-deficit proxies at `2D`, `4D`, and `8D`;
- low-k vorticity fraction and wake population reliability.

The primary summary window is the first-pass wake interval:

- `tau_D >= 4` to discard startup;
- `tau_L < 0.8` to avoid interpreting periodic wrap-around as fresh shedding.

A shedding frequency and Strouhal number are reported only when enough cycles and coherent spectral content are present. Otherwise `StrouhalStatus` explains why the value is not considered qualified.

## x7t viscosity mapping

The x7t transverse-shear viscosities are used automatically only when the run matches the calibrated signature:

- square native cell size `a = 0.002`;
- `gamma = 6`;
- `dt = 0.0005`;
- `kBT = 5`;
- rotation angle `80 deg`.

The values are:

- SRC: `nu = 0.00118720273`;
- legacy Q6: `nu = 0.000759568145`;
- Q6-g-f signed1: `nu = 0.00124451358`.

For any other fluid signature, `Re_D` remains unavailable rather than silently applying the wrong calibration. Use the `ModeViscosities` option to supply a known calibration explicitly.

## Usage

From `matlab/`:

```matlab
run_vk_vorticity_transport_0493x7u
```

or directly:

```matlab
suite = analyze_vk_vorticity_transport_0493x7u( ...
    'RunPatterns', {'../runs/0434_vk_darcy_chi_periodic_*'}, ...
    'OutputDir', '../runs/vk_vorticity_transport_0493x7u_analysis');
```

Main outputs:

- `vk_vorticity_timeseries_0493x7u.csv`
- `vk_vorticity_summary_0493x7u.csv`
- `vk_vorticity_regions_0493x7u.csv`
- `vk_vorticity_sensitivity_0493x7u.csv`
- `vk_vorticity_fields_<case>.csv`
- `vk_vorticity_suite_0493x7u.mat`
- comparison and per-case figures.

# Immersed circle time-averaged and filtered post-processing

This note documents MATLAB-only helpers for the fixed immersed circular solid
validation runs.

## Time-averaged fields

Use:

```matlab
out = analyze_immersed_circle_time_average( ...
    'runs/immersed_circle_forced_long', ...
    'fieldList', {'Ux','Uy','omega'}, ...
    'timeAverageStartFraction', 0.5, ...
    'frameStride', 1, ...
    'filterType', 'box', ...
    'filterWidth', 3, ...
    'showPlots', true);
```

The script reconstructs binned fields from each selected dump, applies an
optional spatial filter, and reports:

- `out.meanFields.<field>`
- `out.rmsFields.<field>`
- the number of averaged frames
- the time window used

The circle outline is overlaid for visual guidance only. The data are not
masked; cell-binning artefacts near the circular boundary therefore remain
visible.

## Filtered animation

Use:

```matlab
play_smpcd_filtered_animation( ...
    'runs/immersed_circle_forced_long', ...
    'field', 'omega', ...
    'timeAverageStartFraction', 0.5, ...
    'filterType', 'box', ...
    'filterWidth', 3, ...
    'temporalHalfWindow', 1, ...
    'pauseTime', 0.05);
```

Recommended first settings:

- `field = 'omega'`
- `filterType = 'box'`
- `filterWidth = 3`
- `temporalHalfWindow = 1` or `2`

Filtering is only intended to reduce visual noise in animations. Validation
metrics should still be interpreted from the raw reconstructed fields and from
runtime summaries.

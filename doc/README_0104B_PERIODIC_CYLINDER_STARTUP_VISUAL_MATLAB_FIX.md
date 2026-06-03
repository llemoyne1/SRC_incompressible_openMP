# 0104b — MATLAB visual report structure-array fix

This micro-fix keeps the periodic-cylinder startup visual case unchanged and only repairs
`make_periodic_cylinder_startup_visual_report_0104.m`.

## Problem

MATLAB could fail with:

```text
Subscripted assignment between dissimilar structures.
Error in make_periodic_cylinder_startup_visual_report_0104 (line 81)
    report.generated(end+1) = runReport;
```

The report container was initialized as `struct([])`, i.e. an empty structure with no
declared fields.  Some MATLAB versions reject appending a non-empty structure with fields
into that array.

## Fix

The report container is now initialized as a homogeneous empty structure array:

```matlab
report.generated = struct('runDir', {}, 'outputDir', {}, 'frames', {}, 'png', {});
```

No simulation parameter, diagnostic, sidecar, or C++ code is changed.

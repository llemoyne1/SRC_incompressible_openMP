# 0186f — Von Karman static circle with inlet/outlet Q6

This update fixes the first Von Karman cylinder launcher failure.

The previous runtime parameter guard inherited from the 0067 inlet/outlet work accepted Q6 + open-boundary + immersed-solid only for a fixed rectangle. The cylinder launcher uses `immersedSolidShape = circle`, so the executable stopped during parameter validation before step 0 and before any dump was written.

The guard now accepts a fixed static circle as well as a fixed static rectangle when all other validated inlet/outlet requirements are satisfied:

- hard-cell-density inlet/reservoir;
- `projectionImmersedSolidMaskEnable = true`;
- `projectionAllowUnmaskedImmersedSolid = false`;
- zero immersed-solid translational velocity;
- zero immersed-solid angular velocity.

The Von Karman launcher also now reports solver stderr/time output even when the solver exits with a non-zero status, so fatal parameter errors are visible directly from the script.

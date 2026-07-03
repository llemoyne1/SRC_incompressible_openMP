# 0439 link fix: standalone periodic support hooks

The initial 0439 standalone validator linked `cell_grid.cpp` and `weighted_resampling.cpp`
without the production translation units that define boundary-periodicity helpers and immersed-solid helpers.

For this validator we intentionally test only periodic, wall-free, no-solid synthetic cases. Therefore the
validator now provides local definitions for:

- `mpcd::is_x_periodic`
- `mpcd::is_y_periodic`
- `mpcd::immersed_solid_enabled`
- `mpcd::immersed_solid_fraction_in_cell`

This avoids pulling the full parameter I/O and immersed-solid production stack into the small validator and
keeps 0439 focused on deposit/classification shadow comparison.

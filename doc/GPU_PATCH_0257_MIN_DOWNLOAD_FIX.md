# GPU patch 0257 minimal-download fix

This corrective differential keeps the 0257 reduced post-collision download path,
but makes it conservative enough for the existing validation summaries.

The first 0257 version cleared `cellCountOut` in minimal-download mode. The run
then reduced `collisionDownloadSeconds`, but failed 4/76 validation metrics on
`tg_periodic_full`, indicating that CPU-side population diagnostics still depend
on post-collision cell counts.

This fix keeps downloading:

- particle velocities,
- particle `cellId`,
- cell population counts,
- scalar counters.

It still skips the heavier post-collision cell arrays:

- `cellMass`,
- `cellUx`,
- `cellUy`.

Expected result: `0257_minimal_collision_download` should return to
`failed_metrics=0` while preserving most of the download reduction.

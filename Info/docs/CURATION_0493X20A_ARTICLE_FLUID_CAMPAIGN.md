# 0493x20a — JCP article fluid characterization campaign

Purpose: one master campaign runner for the systematic bulk characterization of the SRC fluid and the production Q6-G-F quasi-incompressible closure.

The runner reuses `scripts/calibrate_fluid_0493w1_standalone.sh`; it does not modify solver physics.

Matrix: 12 unique physical configurations around the production nominal point gamma=8, alpha_SRC=120 deg, lambdaMean/h=0.72. Main sweeps are lambdaMean/h = 0.36, 0.48, 0.60, 0.72, 0.90; gamma = 4, 6, 8, 12, 16; alpha_SRC = 60, 90, 120, 150 deg. Shared nominal points are de-duplicated. Cross/collapse points are intentionally deferred until trends are inspected.

Per physical configuration the runner performs 3 Taylor-Green and 3 MSD realizations on each of SRC and Q6-G-F, plus 3 pooled acoustic repetitions on SRC: 15 solver invocations/configuration, 180 total.

The article reduced mean-free-path variable is also written in `campaign_matrix.csv` as ell = (dt/h)*sqrt(kBT/m). `lambdaMeanOverH` is retained for compatibility with historical x13 nomenclature.

Restart policy: the constituent standalone calibrator writes `.complete` markers for individual TG/MSD/sound realizations. The master runner uses `SKIP_EXISTING=1`, so re-running the same campaign root retries incomplete work and skips completed realizations. This is campaign-level restart; a single interrupted short 64x64 calibration is rerun from its start.

LiveVis policy: these calibrations are short and use small 64x64/64x16 grids, therefore LiveVis defaults OFF for throughput. It can be enabled explicitly; if `./livevis_control.kv` exists the runner points to it and never edits it.

Outputs include the full per-configuration standalone analysis plus campaign-level matrix, manifest, status log, aggregated transport CSV, SRC/Q6-G-F transport ratios, and realization CSV. No pandas dependency is introduced.

# 0493x23e — article Couette LiveVis metrology

Purpose: instrumented reproduction of the high-signal x14w Couette point for the JCP article.

No C++/CUDA source file is modified by this patch.

Files:
- `scripts/run_0493x23e_article_couette_livevis.sh`
- `matlab/analyze_0493x23e_article_couette_livevis.m`

Frozen primary physical point:
- 128 x 128, Lx = Ly = 0.5, h = 1/256
- gamma = 20
- liquid: m=1, kBT=0.02, src-q6-g-f
- gas: m=0.1, kBT=0.08, src
- dt = 0.002
- Uw = 0.075
- seed = 593170
- 18000 steps

Instrumentation changes only:
- LiveVis enabled, `LIVE_VIS_EVERY=1`
- run-local control file; repository `livevis_control.kv` is untouched
- recorder fields `rho,ux,uy`
- recorder cadence 20 steps
- `filterMode=none`, `smoothPasses=0`
- state dumps every 1000 steps for restart anchors

The runner still executes the historical x14w dump-based analyzer for provenance.
The article metrology is performed separately in MATLAB from the recorder output.

The MATLAB estimator is conservative:
`sum(rho*ux)/sum(rho)` over x and time, followed by antisymmetric folding and
fixed fit windows (4 cells excluded around the nominal interface and wall).

Reference dynamic-viscosity ratio defaults to `muG/muL = 0.11843095`.

Historical anchor:
- x14w archive commit: `5dd346136d2da9d69952b9cade7ed8eb91a2b93f`
- archived x14w runner SHA-256:
  `8cb8d70c6d3080c8b1e579237854eafdde68c206ae67597c192951f879300716`
- current/historical analyzer SHA-256:
  `74f0e641a85cd34fd0306c80c45b942f27d62f6efdcca1eba2e5499d7fdbb7c5`


## v2 preflight correction

The historical `suite_run_binary_0434` helper resets `LIVE_VIS_CONTROL_FILE` to the repository-root user control immediately before launch.  x23e therefore performs the common preflight and binary checks but launches the binary locally, preserving the run-local recorder control.  The global `./livevis_control.kv` is neither read as the x23e recorder contract nor modified.

The preflight must report exactly: native recorder grid `128x128`, fields `rho,ux,uy`, `recordEvery=20`, `filterMode=none`, `filterSampleEvery=20`, `smoothPasses=0`, and `particleTypeFilter=-1`.

# Evidence bundle — 0493x20c to 0493x21e (2026-09-20)

This directory is a documentary snapshot for the article-oriented characterization
campaign after the already-curated x19d/x20a/x20b frontier.

It is deliberately source/data only. It does not change solver physics.

## Transport (x20c-x20d)

- x20c extends the alpha_SRC axis. The final article table retains x20c data where
  qualified and marks status-aware REVIEW/INVALID points explicitly.
- x20d requalifies alpha=165 and 175 deg with TG 256x256, six matched seeds:
  - alpha165: nu_SRC=0.0042083346039622, nu_Q6GF=0.003105024403558631,
    paired ratio=0.7403439825360834, PASS.
  - alpha175: nu_SRC=0.00943178700191517, nu_Q6GF=0.005861715685563784,
    paired ratio=0.6227525580553404, PASS.

## Longitudinal/acoustic (x20e-x20j)

The retained interpretation is:
- SRC supports weakly compressible longitudinal propagation with c close to sqrt(kBT/m).
- production src-q6-g-f suppresses the coherent propagative longitudinal mode under
  this protocol; no robust acoustic phase speed is assigned to the closure.
- projected-face divergence is the residual to the active divergence constraint;
  particle/cell reconstructed divergence is a distinct stochastic diagnostic.

x20f alpha branches are not retained because the original campaign reused/stale
outputs. x20g/x20h demonstrate angle sensitivity; x20i reruns the angles cleanly;
x20j resolves the alpha175 SRC branch with a damped long-wave fit.

## Capillary article campaign (x21a-x21e)

- x21a: strong static pilot; useful for protocol design, not retained as the final
  Young-Laplace calibration.
- x21b: long sigma0 baseline superseded because the free sigma0 drop evolves.
- x21c: same-checkpoint 2-step shadow protocol; 18/18 paired runs collected with
  structural integrity PASS; no sigma_eff is inferred from raw x9e curvatureMean.
- x21d: article pipeline pilot at sigma=10000, R/h=64. Plateau PASS:
  Reff/h=59.6181, radius drift=0.036%, area drift=0.073%, axisRatio=1.02284,
  clipMean=1.998%, clipMax=5.518%.
- x21e: current multi-radius production campaign:
  sigma=10000; R/h=40,48,56,64,72,80; three seeds; active 1500-step relaxation
  followed by same-state sigma/sigma0 shadows. Article curvature is reconstructed
  offline as x6c -> p3/Scharr -> alpha=0.5 face interpolation -> x9r cutoff.

Current x21e frontier at curation time:
- R40 seed4932401 active run completed.
- geometric plateau PASS 600..1500; selected checkpoint 1500.
- runner fix2 corrects CRLF parsing of the selected checkpoint CSV; physics unchanged.
- final fig_07/table_03/table_S3 are not yet claimed complete.

## Binary provenance

Current local binary:
422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc

Reference commit:
74297ce274fc0cd92a9f47a4de92b444ce671b5f

The x21d audit shows:
- src/cuda_q6_resident_0400.cu: identical to reference;
- src/params_io_base.cpp: identical to reference;
- build_src_mpcd_cuda_q6_resident_livevis_0486.sh: identical to reference;
- src/src_mpcd_base.cpp: differs only by x19d diagnostic/performance hot-path cleanup.
The attempted x21c face-kappa diagnostic modification was reverted and is not part
of the canonical solver state.

## Article outputs targeted by x21e

- figures/fig_07_capillary_calibration.pdf/.png
- tables/table_03_capillary_calibration.tex/.csv
- tables/table_S3_capillary_map.tex/.csv
- data/capillary_realizations.csv
- data/capillary_aggregated.csv
- capillary_article_summary.txt

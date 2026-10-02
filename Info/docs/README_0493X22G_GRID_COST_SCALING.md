# 0493x22g — grid-size scaling of production SRC vs Q6-G-F

Diagnostic-only performance campaign. No source or physical-law modification.

## Purpose

Test the observed Q6-G-F overhead as a function of grid size at **constant particle occupation**.
The default is `gamma=20`, because x22f showed that the large overhead persists at that occupation and it is closer to historical qualification campaigns.

## Controlled quantities

Held fixed:

- gamma = 20 (override with `GAMMA=...` only for a separate campaign);
- cell size h = 1/256;
- dt = 0.0063471328149122585;
- kBT = 0.125;
- particle mass = 1;
- periodic x/y boundaries;
- projection tolerance = 1e-5;
- Q6-G-F production path = x7j resident CG, 0407 OFF;
- LiveVis/recording/dumps/internal profiles OFF for measured timings.

Only `N=NX=NY` changes. Because h is fixed, `L=N*h`; cell count and particle count therefore grow with N.

Default grid sequence:

`64 96 128 192 256`

## Timing protocol

For each grid:

1. generate one common thermal initial state;
2. run one unmeasured 100-step warm-up for SRC and Q6-G-F;
3. run three paired 800-step measurements with alternating order;
4. report median SRC and Q6-G-F seconds/step, paired ratio, overhead and MAD;
5. fit empirical log-log scaling exponents versus linear grid size N for SRC, Q6-G-F and the incremental Q6-G-F cost.

This is a computational diagnostic, not an article cost claim until reviewed.

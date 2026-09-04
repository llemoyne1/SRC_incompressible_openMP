# 0493x14ac — projection conservative minimale de la jauge x6g sur x10n

## But

Tester la fermeture

\[
J_{thermo,s}=\left[p_{ref}+\Delta p_s^{x10n}+\delta p_s\right](-dy_s,+dx_s)\,dt
\]

avec la pression locale nominale x10n conservée, mais une correction minimale `delta p_s` qui impose à la **résultante de jauge** la même valeur que celle obtenue sur les faces x6g représentées.

La correction est

\[
\delta p_s = m_s\cdot\lambda,\qquad
M\lambda=F_{Q6}-F_{x10n},\qquad
M=\sum_s L_s m_s m_s^T.
\]

Pour une interface circulaire, cette correction est dipolaire (`n=1`) et ne remplace pas la distribution locale x10n qui avait correctement reproduit le mode `n=2`.

## Contrat de coût

Le mode x14ac est opt-in :

```text
MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=1
```

Implémentation :

- aucun nouveau kernel CUDA ;
- aucune nouvelle passe cellules ;
- aucune nouvelle passe particules ;
- aucun buffer O(N) ;
- aucun transfert host/device ;
- aucun second CG ;
- scratch global : 7 doubles = 56 octets ;
- remise à zéro du scratch fusionnée dans `q6_x10cic_filter_phase_alpha` ;
- `F_Q6`, `F_x10n` et `M` accumulés dans le build x10n déjà existant ;
- solve 2x2 effectué une fois par bloc puis diffusé en mémoire partagée dans le kernel x14v déjà existant ;
- la pression locale x10n est rééchantillonnée une deuxième fois seulement pour les quelques centaines de segments d'interface, afin d'éviter deux nouveaux tableaux O(Ncell).

Les modes x14aa, x14ab et x14ac sont mutuellement exclusifs. x14z est automatiquement neutralisé lorsque x14ac est actif.

## Application

Depuis la racine du dépôt :

```bash
python3 tools/apply_0493x14ac_gauge_resultant_projection.py
git diff --check
git diff --stat
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

Le script d'application attend la préimage x14ab et est idempotent.

## Run n=2 apparié — 2000 steps

```bash
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1 \
MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1 \
MPCD_X14V_X6G_FACE_THERMO_TRACTION=0 \
MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0 \
MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=1 \
MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0 \
CASE_LABEL=0493x14ac_n2_gauge_resultant_projection \
CAMPAIGN_ROOT=runs/0493x14ac_n2_gauge_resultant_projection_seed493180 \
SEED=493180 \
MODE=2 \
EPSILON=0.04 \
RADIUS_CELLS=40 \
SURFACE_TENSION_SIGMA=2560 \
STEPS=2000 \
SUMMARY_EVERY=10 \
DUMP_STATE_EVERY=1000 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY=1 \
LIVE_VIS_HOLD_ON_EXIT=1 \
RECORD_ENABLE=true \
RECORD_FIELDS=mass \
RECORD_EVERY=100 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_ok_0493x14x_two_phase_oscillating_drop_n2.sh
```

Le log source attendu contient :

```text
thermoGeometry=x10n-local+x6g-gauge-resultant-projection
newScratchBytes-x14ac=56
newKernelLaunch=0
newCellPass=0
newParticlePass=0
```

## Critères du test

Le test n'a d'intérêt que si les trois propriétés sont obtenues simultanément :

1. dérive barycentrique proche du niveau x14ab (`~10^-5–10^-4`) ;
2. fréquence `n=2` revenue vers le nominal x14v (`Gomega ~ 1.03`) ;
3. temps par step indiscernable de la dispersion des runs x14aa/x14ab/nominal.

Ne pas poursuivre n=3/n=4 avant ce verdict.

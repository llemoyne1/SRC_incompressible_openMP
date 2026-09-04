# 0493x14ad — pression de jauge x6g locale sur normales x10n + projection résiduelle

## But

Tester la variante qui combine les deux propriétés déjà isolées :

- **distribution locale** portée par les normales x10n/CIC, qui conserve la bonne dynamique de forme ;
- **pression de jauge locale** prise directement sur les faces x6g qui terminent le même segment Marching-Squares ;
- **projection globale x14ac** conservée uniquement pour corriger le résidu de résultante.

Pour un segment x10n terminé par les faces x6g `f1` et `f2` :

\[
\Delta p_s^{loc}=\frac{\Delta p_{f1}^{x6g}+\Delta p_{f2}^{x6g}}{2}.
\]

Si une seule face x6g est représentée, sa valeur est utilisée. Si aucune ne l'est, le lookup nominal x14v est conservé en fallback.

La fermeture finale reste :

\[
\Delta p_s^*=\Delta p_s^{loc}+m_s\cdot\lambda,
\qquad
M\lambda=F_{Q6}-F_{loc}.
\]

La partie uniforme `p_ref` reste strictement sur la géométrie x10n, comme dans x14ac.

## Représentation des faces et coût

Les identités des deux arêtes de chaque segment sont déjà connues pendant le build x10n. x14ad les compacte dans **un octet par cellule déjà alloué** : `kineticMovingWallActive0493x10m`, inutilisé dans la branche x10n/x10o au moment considéré.

Il n'y a donc :

- aucun nouveau kernel ;
- aucune nouvelle passe cellules ;
- aucune nouvelle passe particules ;
- aucun nouveau buffer ;
- aucun transfert host/device ;
- aucun second CG ;
- le scratch global x14ac reste 7 doubles = 56 octets.

Le lookup local « milieu du segment -> recherche de cellule gaz » est remplacé, lorsque les deux faces sont disponibles, par deux accès directs aux faces x6g correspondantes. La variante doit donc rester au minimum coût-neutre à l'échelle du step.

**Important : le scatter/gather CIC x14v est volontairement laissé strictement inchangé dans ce test.** Aucun diagnostic de support n'est ajouté, afin d'isoler le suspect « pression locale ».

## Gate

```text
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
```

Les modes x14aa, x14ab, x14ac et x14ad sont mutuellement exclusifs.

## Application

Depuis la racine du dépôt :

```bash
unzip -o 0493x14ad_local_x6g_face_gauge_projection.zip -d .
python3 tools/apply_0493x14ad_local_x6g_face_gauge_projection.py

git diff --check
git diff --stat

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

Le script attend la préimage x14ac et est idempotent.

## Run discriminant n=2 — 2000 steps

```bash
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1 \
MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1 \
MPCD_X14V_X6G_FACE_THERMO_TRACTION=0 \
MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0 \
MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0 \
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1 \
MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0 \
CASE_LABEL=0493x14ad_n2_local_x6g_face_gauge \
CAMPAIGN_ROOT=runs/0493x14ad_n2_local_x6g_face_gauge_seed493180 \
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

Le log doit notamment contenir :

```text
thermoGeometry=x10n-local-x6g-face-gauge+residual-resultant-projection
newScratchBytes-x14ac=56
x14adEdgeMetadata=reused-x10m-active-byte
newBufferBytes-x14ad=0
newKernelLaunch=0
newCellPass=0
newParticlePass=0
```

## Critères

Le test est concluant seulement si les trois propriétés sont obtenues simultanément :

1. dérive barycentrique nettement inférieure à x14ac (`2.46e-4`), idéalement dans la zone `1e-5–1e-4` ;
2. période `n=2` conservée dans la zone du nominal/x14ac (`Gomega ~ 1.03`, en privilégiant les crossings sur ce run court) ;
3. temps par step indiscernable de la dispersion des runs x14aa/x14ab/x14ac.

Si la fréquence reste bonne mais que la dérive reste proche de x14ac, le prochain suspect à instrumenter est alors la branche terminale de `q6_x14v_scatter_supported_impulse` qui abandonne une impulsion lorsqu'aucune masse liquide supportée n'est trouvée dans le voisinage 5x5.

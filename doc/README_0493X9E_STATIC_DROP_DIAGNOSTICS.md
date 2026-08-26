# 0493x9e — qualification diagnostique de la goutte statique x9d

## Portée

0493x9e est **strictement diagnostique** au-dessus de x9d.

Il ne modifie pas :

- `surfaceTensionSigma` ni la loi `p_l-p_g=sigma*kappa_p3` ;
- la courbure p3 (3 passes binomiales + Scharr) ;
- `alpha_x6c`, le stencil x6f, `phiGamma`, le RHS, CG ou B1 ;
- les trajectoires particulaires.

Le patch ajoute seulement des réductions CUDA à la cadence `summaryEvery` et le champ LiveVis `curvature_interface`.

## Diagnostics ajoutés

### `cuda_static_drop_pressure_0493x9e.csv`

- aire liquide `sum(alpha_x6c)*cellArea` ;
- rayon équivalent `Reff=sqrt(A/pi)` et `1/Reff` ;
- pression de projection Q6 dans le coeur liquide (`alpha>=0.9`) :
  `p'_l = rho_l,ref * phi / dt` ;
- pression EOS gazeuse, dans la **même jauge x6g**, dans le gaz profond (`alpha<=0.1`) ;
- saut mesuré `Delta p = <p'_l> - <p'_g>` ;
- cible courante `sigma/Reff` ;
- courbure p3 interpolée aux traversées `alpha=0.5` ;
- résultante capillaire discrète face-normale
  `sum(kappaGamma*n_axis*faceMeasure)` et résidu normalisé.

La pression reportée est la **pression de projection Q6 cohérente avec x6g/x9d**, pas une reconstruction indépendante d'une pression thermodynamique absolue.

### `cuda_static_drop_velocity_0493x9e.csv`

Vitesses moyennes cellulaires du liquide **après Q6/B1 et avant streaming/collision** :

- domaine liquide `alpha>=0.5` ;
- coeur `alpha>=0.9` ;
- bande interface `0.1<=alpha<=0.9` ;
- moyenne, RMS, RMS après retrait de la moyenne et maximum.

### LiveVis

Nouveau champ :

- `curvature_interface` / `kappa_interface`

Il affiche la courbure p3 uniquement dans la bande physique `0.1<=alpha_x6c<=0.9` et met le bulk à zéro. Le rééchantillonnage LiveVis reste nearest-neighbour ; aucune courbure n'est recalculée pour l'affichage.

Les champs existants restent disponibles :

- `curvature` / `kappa` : p3 cellulaire complet ;
- `curvature_x9b` / `kappa_x9b` : p1 historique.

## Application

Depuis la racine du dépôt, après x9d :

```bash
python3 tools/apply_0493x9e_static_drop_diagnostics.py
git diff --check
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

Le script de modification est idempotent et ne contient pas de garde sur le working tree.

## Premier contrôle

Preflight :

```bash
PREFLIGHT_ONLY=1 \
LIVE_VIS_ENABLE=0 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9e_static_drop.sh
```

Puis cas actif x9d inchangé :

```bash
SIGMA=256 \
R_CELLS=40 \
STEPS=20 \
LIVE_VIS_ENABLE=1 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9e_static_drop.sh
```

Contrôle no-op :

```bash
SIGMA=0 \
R_CELLS=40 \
STEPS=20 \
LIVE_VIS_ENABLE=1 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9e_static_drop.sh
```

`SIGMA=0` produit désormais lui aussi `static_drop_0493x9e.json`.

## Sortie principale

L'analyseur imprime quatre lignes, dont :

```text
[0493x9e-analysis] ... Reff=... kMean=... dPmeas=... dPLaplace=... dPErr=...
[0493x9e-analysis] uRms(liq/core/int)=(...) uMax(...) forceResidual=... COM=...
[0493x9e-analysis] tail... dPmean=... targetMean=... uRmsMean=... uIntRmsMean=...
```

Aucun seuil physique PASS/FAIL n'est imposé dans x9e : `PASS-structural` signifie seulement que les diagnostics ont été produits et sont lisibles.

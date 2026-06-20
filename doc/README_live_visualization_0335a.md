# 0335a — Optional live visualization for SRC/MPCD CUDA runs

This patch adds an optional in-situ live visualization path for qualitative physical inspection of SRC/MPCD simulations.  It is designed for the `SRC_GPU-VIZ` workflow and is disabled by default.

## Build

The normal CUDA build still works without OpenGL/GLFW and compiles a no-op visualization module.  To enable the actual windowed renderer:

```bash
MPCD_ENABLE_LIVE_VIS=1 \
OUT=build/src_mpcd_base_cuda_livevis_0335a \
bash scripts/build_src_mpcd_cuda_0315b.sh
```

The live renderer uses GLFW/OpenGL.  On Ubuntu/WSL this may require:

```bash
sudo apt install libglfw3-dev libgl1-mesa-dev
```

## Runtime controls

The renderer is enabled by environment variables, not by `.kv` parameters, so it does not change existing simulation configurations.

```bash
SRC_LIVE_VIS_ENABLE=1
SRC_LIVE_VIS_FIELD=ux              # ux, uy, speed, vorticity, mass, density, N/count
SRC_LIVE_VIS_EVERY=10
SRC_LIVE_VIS_NX=600
SRC_LIVE_VIS_NY=160
SRC_LIVE_VIS_ALPHA=1.0
SRC_LIVE_VIS_CLIP=-1               # auto scale if <= 0
SRC_LIVE_VIS_SMOOTH_PASSES=0
SRC_LIVE_VIS_WINDOW_SCALE=1
SRC_LIVE_VIS_VSYNC=0
```

The visualization downloads only a role-filtered active-fluid host mirror when the CUDA shared particle state is fresh.  This keeps the inactive reservoir out of the visualization path.

## Example

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-VIZ

MPCD_ENABLE_LIVE_VIS=1 \
OUT=build/src_mpcd_base_cuda_livevis_0335a \
bash scripts/build_src_mpcd_cuda_0315b.sh

SRC_BIN=build/src_mpcd_base_cuda_livevis_0335a \
MODE=classic \
STEPS=20000 \
SRC_LIVE_VIS_FIELD=ux \
SRC_LIVE_VIS_EVERY=10 \
bash scripts/run_vk_full_periodic_livevis_0335a.sh
```

For resampling inspection:

```bash
SRC_BIN=build/src_mpcd_base_cuda_livevis_0335a \
MODE=resampling \
INACTIVE_SLOTS=750000 \
SRC_LIVE_VIS_FIELD=vorticity \
SRC_LIVE_VIS_EVERY=20 \
bash scripts/run_vk_full_periodic_livevis_0335a.sh
```

## Scope

This is deliberately a first robust CPU-fallback live visualization layer.  It avoids CUDA/OpenGL interop and therefore works across the existing resident CUDA families by synchronizing a compact active-fluid host mirror only at visualization frames.  A later 0335b patch can move the accumulation/rendering to CUDA/OpenGL interop if needed.


## 0335c notes: field readability

For particle-noise dominated MPCD fields, use a coarse visualization grid and temporal smoothing.  Good starting points are:

```bash
SRC_LIVE_VIS_NX=300
SRC_LIVE_VIS_NY=80
SRC_LIVE_VIS_ALPHA=0.08
SRC_LIVE_VIS_SMOOTH_PASSES=1
SRC_LIVE_VIS_QUANTILE=0.995
```

For stronger color contrast, set `SRC_LIVE_VIS_GAIN=2` or use an explicit clip, for example `SRC_LIVE_VIS_CLIP=0.2` for `ux`.

For resampling runs, the script defaults to `SRC_LIVE_VIS_FORCE_HOST_MIRROR=1`, which is slower but helps keep the host mirror moving when resampling invalidates the shared CUDA resident state.


## 0335d notes: resampling host-mirror visualization

If a resampling run logs `source=host_state_fallback` and the image is frozen, the CUDA resampling path has invalidated the shared 0251 compact-fluid mirror used by the live renderer.  The script therefore enables a slower visual-inspection mode by default for `MODE=resampling`:

```bash
SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=1
```

This disables the fully-resident shared particle path for that visual run and forces host-visible updates.  It is intended only for qualitative visual inspection, not for performance measurement.  Set `SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0` to return to the fastest resident configuration.


### Champ `N` / `count`

Le champ live `N` affiche le nombre de particules fluides contenues dans chaque cellule de la grille de visualisation live. Il est différent de `mass`/`density` lorsque les masses particulaires ne valent pas toutes 1, par exemple après les corrections de masse ou certains modes de resampling.

Alias acceptés : `N`, `n`, `count`, `population`, `particle_count`, `cell_count`.

La valeur est comptée sur la grille live `SRC_LIVE_VIS_NX` × `SRC_LIVE_VIS_NY`. Pour obtenir une carte par cellule collision SRC/MPCD, choisir la grille live égale à la grille solveur :

```bash
SRC_LIVE_VIS_NX=$NX SRC_LIVE_VIS_NY=$NY SRC_LIVE_VIS_FIELD=N
```

Pour repérer les cellules vides ou surpeuplées, utiliser de préférence un affichage non lissé :

```bash
SRC_LIVE_VIS_FIELD=N SRC_LIVE_VIS_CLIP=-1 SRC_LIVE_VIS_SMOOTH_PASSES=0
```

Côté CUDA compact, lorsque `SRC_LIVE_VIS_CLIP<=0`, l'échelle par défaut de `N` est `2 * activeFluid / (liveNx * liveNy)`, afin d'éviter la saturation immédiate lorsque la grille live est plus grossière que la grille solveur.


### Min/max du champ affiché

La fenêtre live indique désormais le minimum et le maximum du champ scalaire affiché dans son titre.

- Chemin CPU/host : les valeurs sont calculées sur `displayScalar`, donc après lissage et relaxation temporelle `SRC_LIVE_VIS_ALPHA`.
- Chemin CUDA compact : les valeurs sont calculées sur le champ scalaire GPU après lissage spatial et avant conversion RGBA. Seuls les min/max par bloc sont transférés vers l'hôte, afin d'éviter de recopier toute la grille scalaire.

Le log source CUDA peut afficher :

```text
source=cuda_field_0337 min=... max=... scale=... minmax_s=...
```


### Couleur noire des segments quiver 0366

Les segments de l’overlay quiver sont désormais tracés en **noir** (`glColor3f(0,0,0)`), ce qui améliore nettement la lisibilité sur les cartes de couleurs claires ou thermiques. Ce changement est purement visuel et n’ajoute aucun coût de calcul significatif.

### Overlay quiver / vecteurs vitesse 0364

Le renderer live peut afficher un overlay vectoriel vitesse sous forme de simples segments `GL_LINES`, par-dessus le champ scalaire courant. Cet overlay est désactivé par défaut.

Contrôles par variables d'environnement ou par `livevis_control.kv` :

```bash
SRC_LIVE_VIS_QUIVER_NX=60
SRC_LIVE_VIS_QUIVER_NY=32
SRC_LIVE_VIS_QUIVER_SCALE=-1      # <0 désactive l'overlay ; >=0 active l'affichage
SRC_LIVE_VIS_QUIVER_MIN_SPEED=0
SRC_LIVE_VIS_QUIVER_SMOOTH_PASSES=-1  # <0 réutilise SRC_LIVE_VIS_SMOOTH_PASSES
```

Clés équivalentes dans `livevis_control.kv` :

```text
quiverNx = 60
quiverNy = 32
quiverScale = 12
quiverMinSpeed = 0
quiverSmoothPasses = 2
```

`quiverScale` est un gain manuel en pixels par unité de vitesse. Une valeur négative désactive immédiatement l'overlay, ce qui permet de l'allumer/éteindre pendant un run en éditant `livevis_control.kv`.

Le coût reste limité : le chemin CUDA échantillonne seulement une grille vectorielle décimée `quiverNx × quiverNy`, puis transfère deux tableaux `float` vers l'hôte. Par exemple, `60 × 32` représente environ 15 kB par frame, très inférieur au buffer RGBA déjà transféré.

Le lissage des vecteurs est effectué sur cette grille décimée. Par défaut, `quiverSmoothPasses < 0` réutilise `smoothPasses`; on peut définir `quiverSmoothPasses = 2` pour lisser les vecteurs même lorsque `smoothPasses = 0` est conservé pour inspecter un champ `N` non lissé.

# 0364 — Overlay quiver pour la visualisation live

## Objectif

Ce correctif ajoute un overlay optionnel de vecteurs vitesse à la visualisation live SRC/MPCD. La première version dessine des segments simples, sans têtes de flèches, afin de conserver un coût faible et une implémentation robuste.

L'overlay est utile pour inspecter simultanément :

- un champ scalaire (`N`, `vorticity`, `speed`, `chi`, `alpha`, etc.) ;
- la direction et l'intensité locale du champ de vitesse moyen.

## Contrôles

Le comportement peut être piloté par variables d'environnement au lancement ou à chaud via `livevis_control.kv`.

Variables d'environnement :

```bash
SRC_LIVE_VIS_QUIVER_NX=60
SRC_LIVE_VIS_QUIVER_NY=32
SRC_LIVE_VIS_QUIVER_SCALE=-1
SRC_LIVE_VIS_QUIVER_MIN_SPEED=0
```

Clés `livevis_control.kv` :

```text
quiverNx = 60
quiverNy = 32
quiverScale = 12
quiverMinSpeed = 0
```

Sémantique :

- `quiverScale < 0` : overlay désactivé ;
- `quiverScale >= 0` : overlay activé ;
- `quiverScale` : longueur en pixels par unité de vitesse ;
- `quiverNx`, `quiverNy` : résolution de la grille vectorielle décimée ;
- `quiverMinSpeed` : seuil sous lequel les segments ne sont pas dessinés.

## Implémentation

### Chemin CUDA compact

Le chemin `SRC_LIVE_VIS_CUDA_FIELD=1` utilise les sommes déjà déposées sur la grille live :

```text
mass, ux, uy
```

Un petit noyau CUDA échantillonne la vitesse moyenne `ux/mass`, `uy/mass` sur une grille décimée `quiverNx × quiverNy`. Seuls deux tableaux `float` sont transférés vers l'hôte.

Coût de transfert typique pour `60 × 32` :

```text
60 × 32 × 2 × sizeof(float) ≈ 15 kB par frame
```

### Chemin CPU/host fallback

Le fallback CPU utilise les accumulateurs `sumMass`, `sumUx`, `sumUy` déjà remplis pour le champ scalaire. Il échantillonne la même grille décimée puis dessine les segments par-dessus l'image RGBA.

### Rendu OpenGL

Les segments sont dessinés après `glDrawPixels(...)`, avec `GL_LINES`, dans les coordonnées framebuffer. Aucune tête de flèche n'est ajoutée dans cette première version.

## Exemple

```bash
cat > livevis_control.kv <<'CONTROL'
field = N
clip = -1
gain = 1
smoothPasses = 0
colormap = thermal
quiverNx = 60
quiverNy = 32
quiverScale = 12
quiverMinSpeed = 0
CONTROL
```

Pour désactiver l'overlay pendant le run :

```text
quiverScale = -1
```

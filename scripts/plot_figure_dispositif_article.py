# -*- coding: utf-8 -*-
"""
Figure complexe multiphasique pour le cas Fr'=3.0, step 5701

Affiche simultanément :
- densité liquide rho1
- densité gaz rho2 (amplifiée visuellement)
- champ de vitesse ux, uy en quiver, séparé visuellement en "liquide" et "gaz"
- parois solides + lance

Hypothèses :
- maillage 400 x 256
- pas spatial h = 1/256
- fichiers .f32 en float32, rangés en (Ny, Nx)
- les champs ux, uy sont des champs eulériens lissés uniques,
  masqués ensuite selon les zones liquide/gaz
"""

from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import Normalize
from matplotlib.patches import Rectangle
from mpl_toolkits.axes_grid1 import make_axes_locatable
from scipy.ndimage import binary_erosion, binary_dilation


# ============================================================================
# PARAMÈTRES UTILISATEUR
# ============================================================================


record_dir = Path(
    "/mnt/e/SRC_MPCD_dev/SRC_GPU-SURF/"
    "runs/0493x24ah_Fr3_atomization_KM2_S_dt2p2e4_seed493205/"
    "Fr3p0/restart_common_relaxed_start/"
    "output/recordings/record_smooth"
)

step = 5701

# Taille du champ
NX = 400
NY = 256
h = 1.0 / 256.0

# Paramètres de rendu
gas_density_gain = 100.0    # facteur visuel pour rho2
gas_velocity_gain = 1    # facteur visuel pour les flèches gaz
subsample = 8               # sous-échantillonnage des quivers
figure_dpi = 300

# Seuils/masques
liquid_mask_frac = 0.08     # seuil relatif sur rho1 pour "présence liquide"
gas_mask_frac = 0.03        # seuil relatif sur rho2 pour "présence gaz"

# Géométrie (à ajuster si besoin)
Lx = NX * h                 # ~1.5625
Ly = NY * h                 # 1.0
D = 20 * h                  # largeur inlet/nozzle = 20 cellules
nozzle_length = 31 * h      # ~1.55 D
y_nozzle_exit = 0.81640625  # hauteur de sortie
x_center = 0.5 * Lx
x_nozzle_left = x_center - 0.5 * D
x_nozzle_right = x_center + 0.5 * D

# Sauvegarde
out_pdf = record_dir / f"multiphase_snapshot_step_{step:010d}.pdf"
out_png = record_dir / f"multiphase_snapshot_step_{step:010d}.png"


# ============================================================================
# LECTURE DES CHAMPS
# ============================================================================

def load_field(field_name: str) -> np.ndarray:
    path = record_dir / f"step_{step:010d}_field_{field_name}.f32"
    if not path.exists():
        raise FileNotFoundError(f"Champ introuvable : {path}")

    arr = np.fromfile(path, dtype=np.float32)
    expected = NX * NY
    if arr.size != expected:
        raise ValueError(
            f"Taille inattendue pour {field_name}: {arr.size} "
            f"(attendu {expected} = {NX}x{NY})"
        )

    # Réorganisation en (Ny, Nx)
    return arr.reshape((NY, NX))


rho1 = load_field("rho1")
rho2 = load_field("rho2")
ux = load_field("ux")
uy = load_field("uy")


# ============================================================================
# COORDONNÉES
# ============================================================================

x = (np.arange(NX) + 0.5) * h
y = (np.arange(NY) + 0.5) * h
X, Y = np.meshgrid(x, y)

# ============================================================================
# MASQUES / NORMALISATIONS
# ============================================================================

rho1_max = float(np.nanmax(rho1))
rho2_max = float(np.nanmax(rho2))

# Liquide : masque relativement strict
liquid_mask = rho1 > (liquid_mask_frac * rho1_max)

# Gaz : on conserve pratiquement toutes les cellules contenant du gaz.
# Un seuil absolu très faible évite seulement les zéros/bruit numérique.
gas_abs_threshold = max(1.0e-6, 1.0e-4 * rho2_max)
gas_mask = rho2 > gas_abs_threshold

rho1_vals = rho1[liquid_mask]

rho2_scaled = gas_density_gain * rho2
rho2_vals = rho2_scaled[gas_mask]

if rho1_vals.size == 0 or rho2_vals.size == 0:
    raise RuntimeError("Masque liquide ou gaz vide ; revoir les seuils.")

# Normalisation robuste
rho1_vmin, rho1_vmax = np.percentile(rho1_vals, [2, 98])

# Pour le gaz, on veut que les faibles densités restent réellement visibles.
rho2_vmin = 0.0
rho2_vmax = np.percentile(rho2_vals, 99.5)

norm_rho1 = Normalize(vmin=rho1_vmin, vmax=rho1_vmax)
norm_rho2 = Normalize(vmin=rho2_vmin, vmax=rho2_vmax)

# Liquide : même rendu qu'avant
alpha_liq = np.zeros_like(rho1, dtype=float)
alpha_liq[liquid_mask] = 0.25 + 0.75 * (
    (rho1[liquid_mask] - rho1_vmin)
    / max(rho1_vmax - rho1_vmin, 1e-12)
)
alpha_liq = np.clip(alpha_liq, 0.0, 1.0)

# Gaz : alpha presque constant.
# Ainsi une faible densité apparaît avec la couleur "faible densité"
# de la colormap au lieu d'apparaître blanche par transparence.
alpha_gas = np.zeros_like(rho2, dtype=float)
alpha_gas[gas_mask] = 0.80


# ============================================================================
# QUIVERS
# ============================================================================


# Références de phase
rho1_ref = np.percentile(rho1[liquid_mask], 95)
rho2_ref = np.percentile(rho2[gas_mask], 95)

# Présence "physique" des phases
liq_presence = rho1 > (0.35 * rho1_ref)
gas_presence = rho2 > max(0.02 * rho2_ref, gas_abs_threshold)

# Structures morphologiques
st_liq = np.ones((5, 5), dtype=bool)
st_gas = np.ones((5, 5), dtype=bool)
st_buf = np.ones((7, 7), dtype=bool)

# Coeurs internes : on retire l'interface
liq_core = binary_erosion(liq_presence, structure=st_liq, iterations=2)
gas_core = binary_erosion(gas_presence, structure=st_gas, iterations=1)

# Exclusion mutuelle avec une petite zone tampon
liq_core &= ~binary_dilation(gas_presence, structure=st_buf, iterations=1)
gas_core &= ~binary_dilation(liq_presence, structure=st_liq, iterations=1)


# Sous-échantillonnage
sl_y = slice(None, None, subsample)
sl_x = slice(None, None, subsample)

Xs = X[sl_y, sl_x]
Ys = Y[sl_y, sl_x]
uxs = ux[sl_y, sl_x]
uys = uy[sl_y, sl_x]
rho1s = rho1[sl_y, sl_x]
rho2s = rho2[sl_y, sl_x]

Xs = X[::qstep, ::qstep]
Ys = Y[::qstep, ::qstep]
uxs = ux[::qstep, ::qstep]
uys = uy[::qstep, ::qstep]

liq_qmask = liq_core[::qstep, ::qstep]
gas_qmask = gas_core[::qstep, ::qstep]


liquid_qmask = rho1s > (liquid_mask_frac * rho1_max)
gas_qmask = rho2s > (gas_mask_frac * rho2_max)

# Si tu veux éviter les zones mixtes trop chargées :
# liquid_qmask &= (rho2s < 0.2 * rho2_max)
# gas_qmask &= (Ys > y_nozzle_exit - 0.15)

# Échelles quiver
# Avec matplotlib, plus "scale" est grand, plus les flèches sont petites.
liquid_quiver_scale = 3.0
gas_quiver_scale = 30.0


# ============================================================================
# FIGURE
# ============================================================================

fig, ax = plt.subplots(figsize=(11.5, 7.2))

# rho1 liquide en fond
im1 = ax.imshow(
    rho1,
    origin="lower",
    extent=[0, Lx, 0, Ly],
    cmap="Blues",
    norm=norm_rho1,
    alpha=alpha_liq,
    interpolation="bilinear",
)

# rho2 gaz par-dessus
im2 = ax.imshow(
    rho2_scaled,
    origin="lower",
    extent=[0, Lx, 0, Ly],
    cmap="inferno",
    norm=norm_rho2,
    alpha=alpha_gas,
    interpolation="bilinear",
)

# Quiver liquide
q1 = ax.quiver(
    Xs[liquid_qmask],
    Ys[liquid_qmask],
    uxs[liquid_qmask],
    uys[liquid_qmask],
    color="deepskyblue",
    angles="xy",
    scale_units="xy",
    scale=liquid_quiver_scale,
    width=0.0022,
    headwidth=3.8,
    headlength=4.8,
    headaxislength=4.2,
    pivot="mid",
)

# Quiver gaz (même champ, mais amplifié visuellement)
q2 = ax.quiver(
    Xs[gas_qmask],
    Ys[gas_qmask],
    gas_velocity_gain * uxs[gas_qmask],
    gas_velocity_gain * uys[gas_qmask],
    color="red",
    angles="xy",
    scale_units="xy",
    scale=gas_quiver_scale,
    width=0.0020,
    headwidth=3.6,
    headlength=4.6,
    headaxislength=4.0,
    pivot="mid",
)

# Parois externes
ax.plot([0, 0], [0, Ly], color="k", lw=2.2)
ax.plot([Lx, Lx], [0, Ly], color="k", lw=2.2)
ax.plot([0, Lx], [0, 0], color="k", lw=2.2)

# Lance (parois solides internes)
lance = Rectangle(
    (x_nozzle_left, y_nozzle_exit),
    D,
    Ly - y_nozzle_exit,
    fill=False,
    ec="k",
    lw=2.2,
)
ax.add_patch(lance)

# Arête de sortie de la lance
ax.plot([x_nozzle_left, x_nozzle_right], [y_nozzle_exit, y_nozzle_exit], color="k", lw=2.2)

# Axes
ax.set_xlim(0, Lx)
ax.set_ylim(0, Ly)
ax.set_aspect("equal", adjustable="box")
ax.set_xlabel("x")
ax.set_ylabel("y")
ax.set_title(f"Fr'=3.0 — multiphase snapshot — step {step}")

# Légende textuelle discrète
ax.text(
    0.01, 0.015,
    rf"Liquid: $\rho_1$ + velocity quiver | Gas: {gas_density_gain:g}$\times\rho_2$ + velocity quiver $\times {gas_velocity_gain:g}$",
    transform=ax.transAxes,
    fontsize=10,
    color="black",
    bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.75, edgecolor="0.7")
)

# Quiver keys
ax.quiverkey(
    q1, X=0.02, Y=1.03, U=1.0,
    label=r"liquid velocity: $|u|=1$",
    labelpos="E", coordinates="axes", color="deepskyblue"
)
ax.quiverkey(
    q2, X=0.38, Y=1.03, U=gas_velocity_gain * 1.0,
    label=rf"gas velocity shown $\times {gas_velocity_gain:g}$",
    labelpos="E", coordinates="axes", color="yellow"
)

# Liquide
ax.quiver(
    Xs[liq_qmask], Ys[liq_qmask],
    (liquid_velocity_gain * uxs)[liq_qmask],
    (liquid_velocity_gain * uys)[liq_qmask],
    color='deepskyblue',   # ou la couleur liquide choisie
    angles='xy',
    scale_units='xy',
    scale=liquid_quiver_scale,
    width=0.0022,
    zorder=6
)

# Gaz
ax.quiver(
    Xs[gas_qmask], Ys[gas_qmask],
    (gas_velocity_gain * uxs)[gas_qmask],
    (gas_velocity_gain * uys)[gas_qmask],
    color='red',
    angles='xy',
    scale_units='xy',
    scale=gas_quiver_scale,
    width=0.0020,
    zorder=7
)


# Deux colorbars à droite
divider = make_axes_locatable(ax)
cax1 = divider.append_axes("right", size="3.0%", pad=0.06)
cax2 = divider.append_axes("right", size="3.0%", pad=0.34)

cb1 = fig.colorbar(im1, cax=cax1)
cb1.set_label(r"liquid density $\rho_1$")

cb2 = fig.colorbar(im2, cax=cax2)
cb2.set_label(rf"gas density {gas_density_gain:g}$\times \rho_2$")

fig.tight_layout()
fig.savefig(out_pdf, bbox_inches="tight")
fig.savefig(out_png, dpi=figure_dpi, bbox_inches="tight")
plt.show()

print(f"Saved: {out_pdf}")
print(f"Saved: {out_png}")
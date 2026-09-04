# 0493x14af + 0493x14ag — bilan global Q6/x14v et goutte entraînée par Poiseuille gazeux

## x14af : diagnostic de résultante x14v

Gate opt-in :

```text
MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=1
```

Le diagnostic est volontairement limité à la branche x14ad (`MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1`, x14z off). Il accumule **cumulativement** dans 11 doubles : nombre de segments, `Jraw`, `Jthermo`, `Jpref`, `Jgauge`, `Jkick` (x/y). Les identités attendues sont

```text
Jthermo = Jpref + Jgauge
Jkick   = Jraw - Jthermo
```

Le fichier est `output/cuda_x14v_global_balance_0493x14af.csv`. La sortie est faite seulement aux pas d'audit (`summaryEvery`).

Contrat de coût : 88 octets de scratch, aucun nouveau kernel, aucune nouvelle passe cellule/particule, aucun second CG. Les atomiques supplémentaires ne sont présents que quand le gate diagnostic est actif. Le test recommandé fait 200 steps avec `SUMMARY_EVERY=1`; il ne s'agit pas d'une option de production.

Le runner `scripts/run_ok_0493x14af_q6_x14v_global_balance.sh` relance exactement le cas n=2 x14ad pendant 200 steps et compare pas à pas

```text
dPtot  vs  Jq6_applied - Jthermo_x14ad
```

avec `cuda_species_q6_independent_masked_0493w5.csv`, dont `momentumX/Y` est l'impulsion Q6/RT0 réellement appliquée aux particules liquides.

## x14ag : goutte entraînée par un vrai écoulement gazeux

Le runner `scripts/run_ok_0493x14ag_drop_gas_poiseuille_drag.sh` utilise une conduite 2D à parois solides en y, une entrée gazeuse Poiseuille pleine hauteur à gauche et une sortie Neumann à droite. Aucun body force n'est appliqué : la goutte liquide, initialement au repos au centre de la conduite, ne peut acquérir sa vitesse x que par interaction avec le gaz.

Défaut :

```text
Lx x Ly = 2 x 1
Nx x Ny = 512 x 256       (h=1/256)
gamma = 20
dt = 0.002
R/h = 40
centre = (1.0, 0.5)
liquid: m=1, kBT=0.02, q6=1
gas:    m=0.1, kBT=0.08, q6=0
sigma = 2560
Ugas,mean = 0.05
Ugas,max  = 0.075
Udrop(0)  = 0
steps = 6000
```

Pour ces valeurs, `We` basé sur la vitesse centrale vaut ~0.09 : le premier test vise surtout la translation/traînée, sans déformation violente. Le générateur initialise déjà le gaz avec le même profil de Poiseuille que l'inlet pour réduire le transitoire d'établissement.

L'analyseur produit `analysis/drop_drag_trace_0493x14ag.csv` et `analysis/drop_drag_summary_0493x14ag.json`, avec xCM/yCM, vitesse moyenne liquide, vitesse moyenne gaz, glissement et déformation. Il n'impose pas une loi de traînée analytique lors de ce premier test : le contrat est `dx>0`, yCM stable autour de la ligne médiane, accélération/translation cohérente avec le gaz, sans déformation pathologique.

LiveVis et l'enregistrement WYSIWYR sont activés par défaut pour x14ag :

```text
LIVE_VIS_ENABLE=1
LIVE_VIS_EVERY=1
FILTERED_RECORDING_ENABLE=1
RECORD_ENABLE=true
RECORD_EVERY=100
RECORD_FIELDS=mass,ux,uy
```

Le fichier `./livevis_control.kv` n'est pas modifié.

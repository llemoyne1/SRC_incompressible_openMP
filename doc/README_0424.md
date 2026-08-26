# README_0424 — Traitement Darcy/chi du cylindre von Kármán

## Objet

Ce point d’étape documente les développements récents liés au traitement Darcy/Brinkman par champ `chi` dans le chemin SRC classic CUDA résident, ainsi que la campagne de comparaison avec le mode `immersedSolid=circle`.

L’objectif est de disposer d’une alternative plus générale au solide analytique, pilotée par un champ externe `chi`, tout en reproduisant autant que possible les effets physiques importants du mode solid :

- blocage global et traînée effective ;
- production de vorticité pariétale ;
- limitation de la pénétration de particules dans la zone solide ;
- structures tourbillonnaires de sillage proches du cas solid ;
- coût inférieur ou comparable au chemin solid/circle.

Le cas de référence utilisé pour la validation est un von Kármán périodique `1200x640`, avec cylindre centré en `(0.2, 0.205)`, rayon `0.04`, `Lx=1.5`, `Ly=0.4`, `gamma=6`, `kBT=5`, `U0=0.9`, `dt=0.0005`, `bodyAccelerationX=5e-6`, `3000` pas.

---

## État antérieur et limite du Darcy moyen

Le traitement Darcy/Brinkman initial agissait comme un frein volumique sur les particules réelles, contrôlé par le champ `chi` et une perméabilité équivalente via `alpha`.

Le mode historique :

```kv
darcyBrinkmanForcingMode = mean
```

applique un kick de relaxation de la vitesse moyenne cellulaire vers la vitesse solide `u_solid`.

Ce mode est stable et peu intrusif, mais il ne reproduit pas correctement le mode `immersedSolid=circle` :

- vorticité pariétale trop faible ;
- déficit de sillage insuffisant ;
- longueur de recirculation trop grande ;
- présence de particules dans le solide ;
- comportement plus proche d’un obstacle poreux que d’un mur.

Il est donc utile comme baseline, mais ne doit pas être considéré comme une condition de paroi équivalente au solid analytique.

---

## 0418 — Nettoyage initial et bain thermique Darcy

Le patch 0418 a introduit deux extensions.

### Nettoyage initial par `chi`

```kv
darcyInitialDeactivateBelowChi = <seuil>
```

Ce paramètre désactive, au chargement de l’état initial ou d’un restart, les particules fluides actives situées dans des cellules dont `chi` est inférieur au seuil.

Ce nettoyage est effectué une seule fois au chargement, puis l’état est compacté. Il n’y a pas de désactivation continue pendant le run.

Valeurs testées :

- `0.5` : trop agressif pour certains champs `chi`, car il peut supprimer trop de particules dans la couche d’interface ;
- `0.05` : meilleure valeur pratique pour conserver une interface active tout en supprimant le cœur solide profond.

La valeur de référence actuelle est :

```kv
darcyInitialDeactivateBelowChi = 0.05
```

### Mode thermique isotrope

```kv
darcyBrinkmanForcingMode = thermal_bath
```

Ce mode remplace le kick moyen par une relaxation stochastique de type bain thermique vers `u_solid`, avec température issue de `wallKBT` si défini, sinon `kBT`.

Ce mode reste stable, mais il n’a pas apporté d’amélioration suffisante sur le sillage von Kármán. Il est conservé comme variante de diagnostic, pas comme candidat final.

---

## 0419 — Réémission orientée vers le fluide

Le patch 0419 a ajouté un champ normal dérivé de `chi` :

```text
n = grad(chi) / |grad(chi)|
```

Comme `chi=0` dans le solide et `chi=1` dans le fluide, cette normale pointe du solide vers le fluide.

Nouveau mode :

```kv
darcyBrinkmanForcingMode = outward_bath
```

Ce mode décompose la vitesse relative en composantes normale et tangentielle et réémet la composante normale vers le fluide. Il ne crée pas de vraies réflexions géométriques, mais impose une tendance locale à ressortir du solide.

Résultat qualitatif et quantitatif :

- amélioration forte de la vorticité pariétale ;
- structures de sillage visuellement proches du mode solid ;
- vitesse moyenne et déficit de sillage proches du solid ;
- mais pénétration de particules dans la zone solide encore non négligeable.

Ce mode est le meilleur candidat simple.

---

## 0420 — Mode combiné `mean_outward_bath`

Le patch 0420 a ajouté un mode combiné :

```kv
darcyBrinkmanForcingMode = mean_outward_bath
```

Logique appliquée :

```text
1. kick Brinkman moyen classique ;
2. réémission outward_bath orientée par grad(chi).
```

L’objectif est de conserver la réduction de fuite moyenne du mode `mean` tout en imposant une orientation sortante aux particules proches de l’interface.

Résultats :

- très bonne réduction de la fraction de particules dans le solide ;
- vorticité pariétale forte ;
- mais, sans VP collisionnelles, blocage global et déficit de sillage insuffisants par rapport au solid.

Ce mode est donc pertinent comme brique locale de paroi, mais pas suffisant seul.

---

## 0421 — Livevis hold-on-exit

Le patch 0421 a ajouté la possibilité de garder la fenêtre livevis ouverte à la fin du run :

```bash
SRC_LIVE_VIS_HOLD_ON_EXIT=1
```

ou :

```bash
MPCD_LIVE_VIS_HOLD_ON_EXIT=1
```

Le solveur termine, affiche `done`, puis la fenêtre reste ouverte jusqu’à fermeture manuelle, ou pression sur `Q` / `Esc`.

Pour les campagnes automatisées, il faut désactiver ce comportement :

```bash
LIVE_VIS_HOLD_ON_EXIT=0
```

sinon chaque run attendra la fermeture de la fenêtre avant de passer au suivant.

---

## 0422 — Particules virtuelles collisionnelles effectives dérivées de `chi`

Le patch 0422 a ajouté un modèle léger de particules virtuelles de collision, sans créer de particules persistantes.

Paramètres :

```kv
darcyChiCollisionVpEnable = true
darcyChiCollisionVpMode = interface_band
darcyChiCollisionVpGamma = -1
darcyChiCollisionVpMass = 1.0
darcyChiCollisionVpLayers = 1
darcyChiCollisionVpThreshold = 0.5
darcyChiCollisionVpStrength = 1.0
```

Principe :

```text
M_eff = M_real + M_vp
P_eff = P_real + M_vp * u_wall
u_cm_eff = P_eff / M_eff
```

Les particules réelles sont collisionnées autour du centre de masse effectif. Les particules virtuelles n’existent que comme contribution masse/moment dans la collision :

- pas de slots particules ;
- pas de streaming VP ;
- pas de dumps modifiés ;
- pas de compaction additionnelle ;
- coût faible à modéré.

Résultats :

- `mean + chiVP` reproduit très bien le blocage global, la vitesse moyenne, le déficit de sillage et la longueur de recirculation ;
- mais sans outward, les particules peuvent rester piégées dans le solide et la vorticité pariétale reste trop faible ;
- la combinaison `mean_outward_bath + chiVP` donne le meilleur compromis physique.

---

## 0423 — Campagne finale iso-paramètres

Un lanceur de comparaison finale a été ajouté :

```bash
scripts/run_vk_final_comparison_0423.sh
```

Il relance à iso-paramètres :

```text
solid
darcy_mean
darcy_thermal_bath
darcy_outward_bath
darcy_mean_outward
darcy_mean_chiVP
darcy_mean_outward_chiVP
```

Les paramètres communs sont :

```text
STEPS=3000
DT=0.0005
KBT=5.0
U0=0.9
AX=0.000005
NX=1200
NY=640
GAMMA=6
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.05
DUMP_STATE_EVERY=1000
SUMMARY_EVERY=300
```

Le lanceur écrit un manifeste :

```text
runs/vk_final_compare_0423/vk_final_compare_manifest_0423.csv
```

Ce manifeste sert d’entrée aux scripts d’analyse.

---

## 0424 — Analyse filtrée et balayage VP strength

Les dumps instantanés restent très bruités, surtout pour la vorticité. L’analyse brute du champ signé `omega` est trop sévère et trop sensible au déphasage du shedding.

Le script d’analyse filtrée :

```matlab
analyze_vk_wake_similarity_filtered_0424
```

applique donc :

```text
dépôt particules -> ux, uy
filtrage binomial de ux, uy
calcul de omega filtré
enveloppe de vorticité sqrt(filtre(omega^2))
comparaison sur steps 1000, 2000, 3000
```

Sorties principales :

```text
analysis/vk_similarity_filtered_0424/vk_filtered_similarity_by_step_0424.csv
analysis/vk_similarity_filtered_0424/vk_filtered_similarity_summary_0424.csv
```

Un balayage léger du paramètre `DARCY_CHI_COLLISION_VP_STRENGTH` a ensuite été effectué avec :

```bash
scripts/run_vk_vp_strength_sweep_0424.sh
```

Valeurs testées :

```text
0.25
0.50
0.75
```

La valeur `1.00` provenait déjà de la campagne finale 0423.

Analyse dédiée :

```matlab
analyze_vk_vp_strength_sweep_filtered_0424
```

Sorties :

```text
analysis/vk_vp_strength_sweep_0424/vk_vp_strength_filtered_by_step_0424.csv
analysis/vk_vp_strength_sweep_0424/vk_vp_strength_filtered_summary_0424.csv
```

Résultat du balayage :

```text
DARCY_CHI_COLLISION_VP_STRENGTH = 0.25
```

est le meilleur compromis global pour la similarité filtrée du sillage.

Valeur `1.0` :
- meilleure près de la paroi ;
- mais trop contraignante pour le développement aval du sillage.

Valeur `0.25` :
- meilleur score global `wake` ;
- meilleur compromis `near_wake` / `far_wake` ;
- conserve l’effet VP tout en réduisant la surcontrainte collisionnelle.

---

## Configuration de référence actuelle

La configuration recommandée pour le Darcy/chi enrichi est :

```bash
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.05
DARCY_BRINKMAN_FORCING_MODE=mean_outward_bath
DARCY_CHI_COLLISION_VP_ENABLE=true
DARCY_CHI_COLLISION_VP_GAMMA=-1
DARCY_CHI_COLLISION_VP_LAYERS=1
DARCY_CHI_COLLISION_VP_THRESHOLD=0.5
DARCY_CHI_COLLISION_VP_STRENGTH=0.25
WALL_KBT=-1.0
```

Pour un run VK de référence :

```bash
LIVE_VIS_HOLD_ON_EXIT=0 \
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.05 \
DARCY_BRINKMAN_FORCING_MODE=mean_outward_bath \
DARCY_CHI_COLLISION_VP_ENABLE=true \
DARCY_CHI_COLLISION_VP_GAMMA=-1 \
DARCY_CHI_COLLISION_VP_LAYERS=1 \
DARCY_CHI_COLLISION_VP_THRESHOLD=0.5 \
DARCY_CHI_COLLISION_VP_STRENGTH=0.25 \
STEPS=3000 DT=0.0005 KBT=5.0 U0=0.9 AX=0.000005 \
SUMMARY_EVERY=300 DUMP_STATE_EVERY=1000 DUMP_ROLE_FILTER=fluid \
TAG=vk_ref_darcy_mean_outward_chiVP_s025_3000 \
bash scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh
```

---

## Interprétation physique

Les développements montrent que trois mécanismes doivent être distingués.

### 1. Brinkman moyen

Le frein moyen stabilise et réduit certaines fuites, mais ne suffit pas à créer un vrai mur.

### 2. Réémission outward

La réémission orientée par `grad(chi)` améliore fortement la dynamique locale de paroi et la production de vorticité.

### 3. VP collisionnelles

Les VP collisionnelles effectives restaurent le blocage global et la structure tourbillonnaire du sillage, car elles modifient le centre de masse SRC local comme le fait une population solide virtuelle.

La combinaison la plus prometteuse est donc :

```text
Brinkman mean + outward bath + chi collision VP
```

avec une masse VP modérée (`strength=0.25`).

---

## Limitations connues

Le traitement Darcy/chi n’est pas encore strictement équivalent au mode `immersedSolid=circle`.

Limitations restantes :

- pas de vraie réflexion géométrique au niveau de l’interface `chi` ;
- présence possible de particules dans les cellules solides ou mixtes ;
- dépendance au seuil `darcyInitialDeactivateBelowChi` ;
- dépendance à la régularité et à la résolution du champ `chi` ;
- diagnostics Darcy historiques encore partiellement orientés force/puissance Brinkman, pas impulsion réelle VP ;
- comparaison encore basée sur des dumps instantanés filtrés, pas sur une statistique longue de shedding.

---

## Recommandations pour la suite

Avant de modifier à nouveau le code, il est recommandé de figer cet état et de valider la configuration de référence sur un run plus long :

```text
mean_outward_bath + chiVP strength=0.25
```

Points à surveiller :

- stabilité thermique ;
- fraction de particules dans le solide ;
- maintien du score filtré de sillage ;
- évolution du far wake ;
- coût relatif par rapport au mode solid ;
- sensibilité à la résolution du champ `chi`.

Un futur chantier pourrait ajouter :

- projection positionnelle légère hors solide ;
- diagnostics explicites de contribution VP ;
- moyenne temporelle de vorticité/enstrophie ;
- extraction de fréquence de shedding et nombre de Strouhal ;
- généralisation à des formes `chi` non circulaires : NACA, bend-pipe, topologie optimisée.

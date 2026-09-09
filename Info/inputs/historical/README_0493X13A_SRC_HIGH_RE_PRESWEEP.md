# 0493x13a — presweep SRC-only gros Reynolds A0–A6

## Objet

Cartographier, sans modifier le code source, la capacité de transport du SRC homogène lorsque l'angle de collision et le libre parcours thermique sont poussés vers un régime de viscosité plus faible.

La campagne est volontairement indépendante d'une application. Aucun diamètre de goutte, vitesse d'impact, obstacle ou Reynolds cible n'est utilisé dans le runner.

La métrique intrinsèque principale est

\[
H_h=\frac{c_s h}{\nu},
\]

car pour une longueur caractéristique de `N=L/h` cellules,

\[
Re=Ma\,N\,H_h.
\]

## Physique figée pour A0–A6

- SRC-only, périodique ; Q6=false ; resampling=false.
- `h=1/256`, grille de calibration `64x64`, donc boîte `0.25x0.25`.
- `gamma=20`, `kBT=0.125`, masse particulaire `1`.
- rotation aléatoire de signe et grid shift actifs.
- thermostat `cell_relative_rescale`, chaque pas, cible `kBT=0.125`, minimum 3 particules.
- même seed de base dans tous les cas afin de rendre la comparaison aussi appariée que le permet la modification de la dynamique collisionnelle.

## Matrice

|cas|angle|lambda_mean/h|fonction|
|---|---:|---:|---|
|A0|90°|0.2268740929|témoin historique `dt=0.002`|
|A1|120°|0.48|première hausse de back-scattering|
|A2|150°|0.95|bord du régime local `lambda/h~1`|
|A3|165°|1.32|transition mésoscopique|
|A4|175°|1.50|près de pi, libre parcours modéré|
|A5|175°|2.10|près de pi, libre parcours étendu|
|A6|175°|3.00|sonde frontière volontairement agressive|

`dt` est calculé à partir de la cible `lambda_mean/h` avec la vitesse thermique moyenne 2D du fluide canonique. Le manifeste écrit aussi l'estimateur analytique SRD `nu_kin + nu_col`; celui-ci sert au positionnement et non à remplacer TG.

## Durées de mesure

Les cas sont comparés à durée physique égale :

- TG : `T=4.0`, 80 dumps ;
- acoustique : `T=2.4`, 120 dumps, 2 réalisations indépendantes ;
- MSD : `T=5.0`, 60 dumps.

Le mode acoustique est `modeX=1` afin de conserver une longueur d'onde de 64 cellules et une résolution temporelle correcte jusque A6.

## Installation dans le dépôt

Copier les deux scripts et le check dans `scripts/`. Aucun fichier de `src/` ou `include/` n'est modifié.

## Vérification

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
bash scripts/check_0493x13a_src_high_re_presweep.sh
```

Le check fait seulement de la syntaxe/compilation Python et un `PREFLIGHT_ONLY` A0+A6 ; il ne lance pas de simulation.

## Preflight complet A0–A6

```bash
PREFLIGHT_ONLY=1 \
bash scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh
```

Vérifier notamment qu'A0 retrouve `dt=0.002`, qu'A6 est proche de `dt=0.0264464`, et qu'aucun warning acoustique rédhibitoire n'apparaît.

## Run complet

```bash
LIVE_PROGRESS=1 \
bash scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh
```

## Relancer seulement certains cas

Par exemple :

```bash
CASES=A3,A4,A5 \
CLEAN_SWEEP_ROOT=0 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh
```

Chaque case relancée nettoie seulement son propre `RUN_ROOT`. Les autres résultats restent en place.

## Réanalyse seule

```bash
ANALYZE_ONLY=1 CLEAN_SWEEP_ROOT=0 \
bash scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh
```

## Sorties à examiner / renvoyer

Le fichier principal est :

```text
runs/0493x13a_src_high_re_presweep_A0_A6/analysis/high_re_presweep_0493x13a.csv
```

avec son rapport lisible :

```text
runs/0493x13a_src_high_re_presweep_A0_A6/analysis/README_0493X13A_HIGH_RE_PRESWEEP.md
```

Le collecteur conserve également les statuts et métriques TG/MSD/acoustiques de 0493w1, plus :

- réduction de viscosité par rapport à A0 ;
- `H_h=c_s h/nu` ;
- Reynolds par cellule à Ma=0.1, 0.2 et 0.3 ;
- bandes descriptives de `lambda/h` et de Schmidt ;
- rapport viscosité mesurée / estimateur SRD ;
- temps mur total et speedup par rapport à A0 ;
- coût normalisé par milliard de particle-steps.

Aucune classe `TARGET` spécifique à une application n'est produite. `PASS/REVIEW/INVALID` correspond seulement à la qualité des trois mesures du calibrateur existant.

## Décision après A0–A6

Ne pas encore changer le modèle. On décidera ensuite :

- si le gain utile se poursuit jusqu'à A4/A5 sans invalidation des fits ;
- où se situe la transition de `Sc` et de `lambda/h` ;
- si la hausse de `dt` procure réellement le gain de temps attendu ;
- et seulement ensuite s'il est justifié d'ouvrir la seconde dimension `gamma=40/80` ou une étude de taille de boîte/grille.

## Charge nominale de la première passe

Avec `SOUND_REPLICATES=2`, la matrice canonique représente environ `1.255e9` particle-steps au total. Le preflight estime environ 8.5 GB de dumps pour A0–A6 avec les cadences par défaut. Cette charge décroît fortement avec `dt`: A0 représente à lui seul ~565 millions de particle-steps, contre ~43 millions pour A6.

Ce profil de coût est intentionnel : on mesure à durée physique comparable. Un fluide à grand `dt` doit donc démontrer non seulement une baisse de viscosité mais aussi son avantage réel en temps de calcul par unité de temps physique.

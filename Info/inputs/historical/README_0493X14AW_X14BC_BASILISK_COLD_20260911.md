# 0493x14aw -> x14bc — Basilisk atomisation analogue, interface diagnostics, pulse and cold-liquid selection

Date documentaire: **2026-09-11**.

Cette source historique consolide uniquement les éléments explicitement attestés dans la campagne
courante. Elle ne complète aucune lacune de nomenclature: en particulier **x14bb/x14bb2 ne sont pas
promus comme jalons canoniques**. `0493x14bb2` n'a été qu'un label de campagne/répertoire pour la
calibration du liquide froid.

## x14aw — benchmark Basilisk 2-D Re_L=500 / We_G=200

Le runner `run_0493x14aw_basilisk_atomisation_re500.sh` introduit l'analogue 2-D du cas
`src/examples/atomisation.c` de Basilisk: jet liquide rectiligne dans gaz initialement stagnant,
rapport de densité 27.84, D/h=96, domaine 18D x 18D et cible St=5/3. Le chemin physique liquide/gaz
reste la chaîne x14 existante: liquide Q6-g-f, x6g/x9/x10/x12 et x14l/x14v, sans resampling ni kick
viriel.

Le point de départ retenait le liquide `gamma=8`, `alpha=90 deg`, `dt=0.00635`, `m_L=1`,
`kBT_L=0.03125`, avec la calibration TG128 déjà obtenue `nu_L=0.0003303602194` (PASS, CV=11.28%).
Le gaz conservait `m_G=0.03591954022988506`, `kBT_G=0.00575`, `nu_G=0.0003536191886`
(TG64, ensemble REVIEW, CV=13.22%).

## x14ax / x14az — fraction liquide x6c enregistrable puis visualisable

`x14ax` rend la fraction liquide physique résidente `phaseAlphaFiltered0493x6c` accessible au
filtered recorder sous le nom canonique `alpha_x6c`, avec alias `phase_alpha`,
`phase_alpha_x6c` et `liquid_fraction_x6c`. Le remapping vers la grille Live/recorder est conservatif
par aire; aucun transfert hôte du champ solveur complet n'est ajouté et aucun lissage recorder
supplémentaire n'est appliqué à ce champ.

`x14az` complète x14ax en rendant `alpha_x6c` directement affichable par LiveVis. Il conserve
l'ancien champ `alpha` comme alpha Darcy. Pour `alpha_x6c`, `smoothPasses` est neutralisé afin que
la vue corresponde au champ x6c effectivement utilisé par la chaîne interfaciale.

Le root `livevis_control.kv` reste user-owned et n'est modifié par aucun de ces patches.

## x14ay — test de raffinement particulaire gamma 12/16

Le runner x14ay teste la transformation de similitude particulaire

    gamma' = s gamma
    m'     = m/s
    kBT'   = kBT/s

qui préserve `gamma*m`, `gamma*kBT`, `kBT/m`, les densités et `lambda/h` dans les grandes lignes.
Le smoke gamma=12 a montré une amélioration limitée de l'interface pour un coût particulaire accru
d'environ 50%. La campagne a donc **abandonné gamma=12/16 comme levier principal** et est revenue
à gamma=8.

Cette décision est expérimentale et ne constitue pas une invalidation du runner x14ay; elle signifie
seulement qu'il n'est pas retenu comme fluide de production du benchmark courant.

## Sélection du liquide froid à gamma=8

À gamma=8 et masse liquide 1, la réduction directe de `kBT_L/m_L` s'est montrée beaucoup plus
efficace sur la rugosité interfaciale que l'augmentation de gamma:

- `kBT_L=0.015625`: amélioration nette, interface encore accidentée;
- `kBT_L=0.0078125`: interface jugée convaincante sur les vues `rho` et `alpha_x6c` à 300 pas.

Ces observations sont **qualitatives** et les captures correspondantes sont conservées dans l'archive
de provenance. Elles ne sont pas transformées en métrique quantitative de rugosité.

Le point `kBT_L=0.0078125` a ensuite été recalibré par Taylor-Green sur le chemin de production
`src-q6-g-f`, grille 128x128, 8 graines, `gamma=8`, `alpha=90 deg`, `m=1`, `h=1/256`,
`dt=0.00635`, mode TG (2,2), amplitude 0.05, T=4.0. Le log exact donne:

    status=PASS
    viscosity=PASS
    nu=0.0002122268985
    std=4.705e-06
    CV=0.022

Cette valeur devient la référence liquide froide de la campagne.

Le gaz n'est pas rematché exactement à cette viscosité. La décision de campagne est de conserver
l'ordre de grandeur du transport gazeux avec la calibration existante `nu_G=0.0003536191886`;
l'égalité stricte `nu_G=nu_L` n'est pas exigée pour le régime exploratoire visé.

## x14ba — oscillation globale de vitesse d'entrée

x14ba ajoute six paramètres solveur canoniques, tous neutres par défaut:

    inletVelocityOscillationEnable
    inletVelocityOscillationAmplitude
    inletVelocityOscillationPeriod
    inletVelocityOscillationPhase
    inletVelocityOscillationStartTime
    inletVelocityOscillationTimeOffset

Les alias courts `inletOscillation*` sont acceptés. Lorsque le mécanisme est actif,

    F(t) = 1 + A sin(2*pi*(t_eff - t_start)/T + phase)
    t_eff = t + timeOffset

et le multiplicateur d'entrée est le produit du facteur de ramp existant et de ce facteur oscillant.
`A` est borné à [0,1], `T>0`, la phase est en radians. Le même facteur est propagé au chemin
particulaire et aux flux Q6 host/CUDA afin de garder injection et projection synchronisées.
`timeOffset` permet la continuité de phase après restart.

Lorsque `inletVelocityOscillationEnable=false`, le facteur ajouté vaut exactement 1.0.

## x14bc — runner froid Re_L=500 pulsé

x14bc remplace le fluide liquide x14aw par le point froid calibré et active par défaut la loi x14ba.
Les valeurs par défaut documentées sont:

    gamma = 8
    alpha = 90 deg
    h = 1/256
    dt = 0.00635
    m_L = 1
    kBT_L = 0.0078125
    nu_L = 0.0002122268985
    m_G = 0.03591954022988506
    kBT_G = 0.00575
    nu_G = 0.0003536191886
    rho_L/rho_G = 27.84
    D/h = 96
    domain = 18D x 18D
    Re_L = 500
    We_G = 200
    St = 5/3
    A/U = 0.05

Le runner en déduit environ:

    U = 0.282969198
    sigma = 2.827354642
    Re_G ~= 300
    nu_G/nu_L ~= 1.67
    pulse period ~= 0.79514
    pulse period ~= 125.2 steps

Le smoke pulsé 300 pas sur seed 493215 a fonctionné avec `alpha_x6c` LiveVis/recorder actif.
Ce smoke valide l'intégration de la chaîne mais **pas** encore une statistique de breakup ni une
qualification multi-seed.

Le run long prévu est 4758 pas, dumps/restarts tous les 1000 pas, `ALLOW_LARGE_DUMPS=1`,
recording tous les 25 pas pour résoudre la phase du pulse. Son coût local estimé/observé est de
l'ordre de deux heures; la stratégie retenue est donc **un cas long de référence unique** et une
analyse temporelle/phase-folded sur environ 38 périodes, plutôt qu'un ensemble de plusieurs graines.
Cette stratégie de coût n'est pas une revendication d'indépendance statistique inter-seed.

## Provenance binaire

Archive primaire associée:

`Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip`

SHA-256 de l'archive:

`7e06184d9ba1130147579d92d2bf6bf6d5bca2f6718c361e378632734759376b`

L'archive contient les packages exacts x14ax/x14ay/x14az/x14ba/x14bc, le runner x14aw, le log
TG128 froid, les captures qualitatives sélectionnées et un manifest SHA-256 interne.

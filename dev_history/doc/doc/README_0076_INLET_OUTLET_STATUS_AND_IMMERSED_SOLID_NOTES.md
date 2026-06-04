# 0076 — État inlet/outlet et bilan des essais immersed-solid Q9

## Objet

Ce document fige l'état méthodologique du chantier `feature/inlet-outlet` après les essais 0067–0075. La conclusion principale est que les conditions inlet/outlet doivent être validées et clôturées d'abord **sans solide immergé**. Les difficultés observées avec la marche/obstacle relèvent d'un second chantier : le couplage Q6/Q9/viriel avec des géométries solides immergées et des cellules fluides adjacentes au solide.

Contraintes de branche rappelées :

- rester sur `feature/inlet-outlet` pour le chantier inlet/outlet ;
- garder le mode `classic` compressible disponible ;
- ne pas casser les validations périodique/canal ;
- privilégier l'opérateur elliptique générique ;
- ne pas ajouter de chemin FFT spécifique ;
- ne pas produire de fichier `.patch` ;
- ranger les nouvelles documentations dans `doc/`, sauf `README.md` racine.

## État fonctionnel à conserver sur `feature/inlet-outlet`

Les éléments suivants sont considérés comme les acquis centraux de la branche :

1. `classic` inlet/outlet particulaire fonctionnel.
2. Q6 inlet/outlet via l'opérateur elliptique générique fonctionnel.
3. Q9 inlet/outlet en canal ouvert fonctionnel.
4. Q9 + viriel bulk-only en canal ouvert fonctionnel.
5. Hard inlet reservoir `hard_cell_density` fonctionnel : chaque cellule de la bande inlet est reconstruite avec `N=gamma`, `Uin`, `kBT`.
6. Le mode Q9 `ramp_floor` est désormais effectivement branché dans le cœur Q9 et diagnostiqué par :
   - `q9LowMassSuppressedCells`,
   - `q9LowMassRampedCells`,
   - `q9MassFloorAppliedCells`,
   - `q9VelocityLimitedCells`.
7. Les diagnostics de budget masse/flux en canal ouvert et en marche permettent d'identifier les défauts de bilan particulaire et les zones d'accumulation.

## Validation sans solide : canal ouvert hard-inlet/outlet 48x24

Le test 0071 sans solide, en `48x24`, a été conçu pour isoler le couple :

```text
hard_cell_density inlet + outlet passif
```

sans géométrie immergée. Le cas `openchan_q9_virial_hard_inlet_s003_48x24_long` couvrait :

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
Uin = 0.05
dt = 0.001
CASE_STEPS = 60000
tfinal = 60 ≈ 1.5 Tadv
```

Résultat synthétique :

```text
Np initial = 23040
Np final   = 23546
ΔNp        = +506 ≈ +2.2 %
```

La masse totale augmente pendant le transitoire, puis tend vers un plateau. Les proxies d'état indiquent un rapport outlet/inlet proche de l'unité en fin de run :

```text
stateOutletOverInletFluxProxyMeanLate ≈ 1.001
```

Interprétation : le couple hard-inlet/outlet passif peut relaxer naturellement vers un débit traversant en canal droit sans solide. Cela dédouane largement le chantier inlet/outlet lui-même : le défaut majeur observé avec la marche n'est pas un défaut structurel du canal ouvert, mais une difficulté de couplage avec obstacle immergé.

## Bilan des essais avec marche/obstacle immergé

Les essais 0072–0075 ont été utiles comme stress tests exploratoires, mais ils ne doivent pas servir de critère de clôture de `feature/inlet-outlet`.

### 0072 — Marche proche, Q9 faible/limité

Configuration : marche proche de l'inlet, `48x24`, `q9_virial`, `q9MassFluxProjectionStrength=0.03`, limiteur Q9 `0.003`, halo solide Q9 réduit à `1`.

Résultat : le débit outlet finit par rattraper l'inlet, mais au prix d'une compression amont massive.

```text
Np initial = 20640
Np final   = 32314
ΔNp        ≈ +56.6 %
maxFluidN final ≈ 756
stdFluidN final ≈ 68.6
```

Conclusion : Q9 faible/limité protège thermiquement le calcul, mais ne maintient pas la densité quasi-incompressible devant la marche. L'obstacle proche crée une poche de rétention majeure.

### 0073 — Marche proche, paramètres Q9 validés Poiseuille, sans limiteur

Configuration : même marche proche, mais réinjection des paramètres Q9 validés avant inlet/outlet :

```text
q6ProjectionStrength = 1.0
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
q9CorrectionVelocityLimiter = 0.0
```

Sur un probe à `10000 steps`, le calcul ne diverge pas immédiatement, mais la réponse devient très violente :

```text
q9CorrectionVelocityRms max      ≈ 6.78
q9CorrectionVelocityMaxAbs max   ≈ 68.6
kBT max                          ≈ 35.1
kBT final t=10                   ≈ 0.434
maxN final t=10                  ≈ 1032
```

Conclusion : retirer le limiteur permet à Q9 de réagir fortement et limite l'accumulation globale, mais produit des régimes balistiques et une hétérogénéité de densité encore excessive.

### 0074 — Obstacle reculé et bas, Uin=0.05, paramètres Q9 validés sans limiteur

Configuration : obstacle reculé et plus fin :

```text
xMin = 0.625
xMax = 0.750
yMin = 0.0
yMax = 0.25
Uin  = 0.05
```

Cette géométrie donne environ onze colonnes Q9 actives entre l'inlet et la marche, au lieu d'environ deux dans la configuration initiale.

Résultat : la rétention amont massive disparaît, mais le domaine se vide globalement et la dynamique reste très violente.

```text
totalFluidMass initial ≈ 22680
totalFluidMass final   ≈ 14052
ΔNp                    ≈ -38 %
kBT max                ≈ 226
kBT final              ≈ 1.37
maxParticleSpeed max   ≈ 299
maxFluidN final        ≈ 994
```

Conclusion : la géométrie reculé/bas confirme que la marche initiale était trop proche de l'inlet, mais les paramètres Q9 validés sans limiteur restent trop agressifs pour ce cas ouvert avec solide à `Uin=0.05`.

### 0075 — Obstacle reculé et bas, Uin=0.025, paramètres Q9 validés sans limiteur

Configuration : même géométrie que 0074, mais avec `Uin=0.025` pour réduire l'agressivité du forçage. Run `80000 steps`, soit environ un temps advectif :

```text
Lx = 2.0
Uin = 0.025
Tadv = 80
CASE_STEPS = 80000
tfinal = 80
```

Fichiers analysés :

```text
mass_budget_summary_0072(4).csv
mass_budget_timeseries_all_cases(6).csv
summary_runtime(19).csv
```

Résultats de budget masse :

```text
totalFluidMass initial = 22680
totalFluidMass final   = 14187
ΔNp                    = -8493 ≈ -37.4 %
meanFluidN final       ≈ 12.51
stdFluidN final        ≈ 42.16
maxFluidN final        ≈ 664
upstreamLowerMass      : 1800 → 1205
frontBandMass          : 480 → 368
downstreamLowerMass    : 3600 → 1202
```

Résultats runtime :

```text
Np max                      = 25916 à t≈11.075
Np min                      = 12403 à t≈55.85
kBTEstimate max             ≈ 426.1 à t≈18.375
kBTEstimate final           ≈ 1.716
maxParticleSpeed max        ≈ 363.6 à t≈12.15
maxParticleSpeed final      ≈ 17.77
q9CorrectionVelocityRms max ≈ 39.83 à t≈18.375
q9CorrectionVelocityMaxAbs max ≈ 382.7 à t≈13.9
q9CorrectionVelocityRms final  ≈ 1.52
q9CorrectionVelocityMaxAbs final ≈ 10.69
q9LowMassSuppressedCells final = 442
q9EmptyCells final             = 535
q9VelocityLimitedCells         = 0
virialRhoDefectRelRms max      ≈ 6.29
virialRhoDefectRelRms final    ≈ 3.50
```

Conclusion : baisser `Uin` à `0.025` ne suffit pas à stabiliser le cas avec solide. Le run reste très chaud, fortement hétérogène et globalement raréfié. Le problème n'est donc pas seulement l'intensité de l'inlet ; il relève du couplage Q9/viriel/solide, notamment de l'activité effective de Q9 près des parois, des cellules low-mass, des faces fluide-solide et des réflexions solides.

## Décision méthodologique

La branche `feature/inlet-outlet` doit être clôturée sur les validations sans solide. Les scripts avec obstacle peuvent être conservés comme cas exploratoires, mais les problèmes observés doivent être transférés vers une branche dédiée, par exemple :

```bash
git checkout feature/inlet-outlet
git pull
git checkout -b feature/q9-immersed-solid-boundary
```

Sur cette future branche, les sujets à traiter seront :

1. Q9 actif dans les cellules fluides adjacentes au solide.
2. Fermeture correcte des faces fluide-solide : flux normal correctif nul.
3. Remplacement du halo solide Q9 par un opérateur masqué cellule/face plus propre.
4. Gestion des cellules low-mass près paroi sans neutraliser la projection là où la compression se forme.
5. Couplage viriel près du solide.
6. Diagnostics zone par zone de `q9Active`, `q9LowMassSuppressed`, `q9MassFloorApplied`, `q9EmptyCells`, `maxN`, `stdN`, `kBT` autour du solide.
7. Validation progressive : canal droit → contraction douce → obstacle bas reculé → marche plus forte.

## Recommandation pour clôturer `feature/inlet-outlet`

Avant de quitter la branche, conserver au minimum :

```text
scripts/run_open_channel_hard_inlet_budget_0071.sh
matlab/analyze_open_channel_hard_inlet_budget_0071.m
matlab/make_open_channel_hard_inlet_visual_report_0071.m
```

comme validation structurée du hard inlet/outlet sans solide.

Les scripts obstacle 0072–0075 peuvent rester dans le dépôt s'ils sont utiles comme historique, mais leur statut doit être clairement indiqué : exploratoire, non bloquant pour la validation inlet/outlet.

## Commandes de commit suggérées

```bash
git status
git add doc/README_0076_INLET_OUTLET_STATUS_AND_IMMERSED_SOLID_NOTES.md
git commit -m "0076 document inlet-outlet validation and immersed-solid split"
git status
```

Message long suggéré :

```text
0076 document inlet-outlet validation and immersed-solid split

- summarize hard-inlet/open-outlet validation without immersed solids
- record exploratory backward-step runs 0072-0075
- document that open-channel inlet/outlet relaxes toward balanced flux
- document that immersed-solid cases expose a separate Q9/virial/solid-boundary issue
- recommend closing feature/inlet-outlet on no-solid validation and moving solid work to a dedicated branch
```

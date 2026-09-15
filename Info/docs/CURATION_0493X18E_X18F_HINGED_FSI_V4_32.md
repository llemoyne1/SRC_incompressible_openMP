# V4.32 — 0493x18e / 0493x18f : sous-cyclage FSI et frontières ouvertes du volet

## Périmètre

V4.32 clôt le chantier immédiat du volet articulé après V4.31-fix1. La curation ajoute deux jalons :

- **x18e** : sous-cyclage FSI local du volet, sans modifier le pas global SRC/Q6 ;
- **x18f** : frontières ouvertes des runners x18a/x18b et intégration durable de l'initialisation x18a-fix2.

Aucun correctif global de conservation de population n'est promu.

## 0493x18e — sous-cyclage FSI local

Avant x18e, le couplage partitionné du volet pouvait devenir extrêmement coûteux sous forte excitation : la géométrie mobile était mise à jour avec un retard de pas parent et le broad-phase x17a pouvait devoir parcourir un nombre très élevé de cellules pour des trajectoires devenues trop longues.

x18e conserve **le pas global `dt` du solveur** mais sous-cycle localement le couplage particule-paroi et l'ODE du volet. Les paramètres introduits sont :

- `chiSolidHingedFsiSubcyclingEnable=true` ;
- `chiSolidHingedFsiMinSubsteps=4` ;
- `chiSolidHingedFsiMaxSubsteps=64` ;
- `chiSolidHingedMaxAngularIncrement=0.02` ;
- `chiSolidHingedMaxTipDisplacementCells=0.20` ;
- `chiSolidHingedMaxParticleSpanCells=64`.

La validation opérateur rapporte une compilation CUDA locale réussie et des runs fonctionnels. Un pas global testé jusqu'à **20 fois la limite pratique précédente** n'a pas reproduit le hang. Ce résultat autorise le statut `VALIDATED/FUNCTIONAL`; il ne constitue ni une preuve de stabilité inconditionnelle ni un speedup wall-time de 20x.

## 0493x18f — frontières ouvertes et initialisation finale des runners

### x18a : `inlet_neumann`

Le runner x18a utilise par défaut :

- topologie segmentée ;
- inlet uniforme pleine hauteur à gauche, vitesse `FLOW_UX` ;
- outlet Neumann pleine hauteur à droite ;
- parois solides en haut et en bas.

La validation locale x18f a compilé et exécuté **200 pas à `dt=0.006`, `FLOW_UX=0.352`**, jusqu'à `t=1.2`, avec terminaison `COMPLETE`. Ce chemin est retenu comme configuration de référence pour le futur sweep stationnaire `U -> theta`.

### Initialisation x18a-fix2 intégrée

`HINGED_INITIAL_FLUID_GEOMETRY=auto` est désormais câblé directement dans le runner. Pour un angle initial non nul, le runner neutralise la vieille exclusion verticale et appelle `prepare_0493x18a_initial_fluid.py` afin d'exclure le fluide uniquement dans le volet réellement tourné. Il n'est plus nécessaire de réappliquer le script x18a-fix2 après chaque build.

### x18b : `double_neumann`

Le runner de chute x18b utilise par défaut deux faces x ouvertes Neumann, avec haut/bas solides. Cette configuration **outlet-only** était auparavant refusée par les gates du chemin segmenté qui demandaient au moins un inlet et un outlet. x18f l'autorise uniquement pour le chemin Q6 résident avec `openBoundaryOutletMode=neumann`; le contrat legacy SRC-classic n'est pas élargi.

La configuration est fonctionnelle mais **non qualifiée quantitativement en bilan de masse** :

- à `FLUID_DENSITY_FACTOR=0.01`, l'essai s'arrête vers le pas 110 par épuisement des slots inactifs ; le bilan cumulé est `inserted-deleted=+71338`, avec environ +2400 particules nettes au pas 110 ;
- à `FLUID_DENSITY_FACTOR=0.10`, `solidMass=4000`, `gravityY=-10`, `hingeDamping=0`, le run 2000 pas termine correctement et constitue un bon démonstrateur qualitatif de chute/amortissement hydrodynamique ; la population passe toutefois de `1087414` à `1053894`, soit `-3.0825%`, avec minimum `1037481` et maximum `1087891` ; après environ 800 pas, une dérive tardive d'environ `-25` à `-29` particules/pas persiste.

Le signe du biais dépend donc du régime. Le double-Neumann est retenu comme **démonstrateur qualitatif FSI**, pas comme CL stationnaire quantitative de longue durée.

## Décision sur x18f-fix1

Le correctif proposé `x18f-fix1`, qui aurait imposé un verrou global `N_insert <= N_deleted`, **n'a pas été appliqué** et n'est pas retenu comme sémantique de production.

Une architecture générale de frontières ouvertes doit autoriser un bilan de masse non nul lorsque la physique le demande : remplissage par inlet dominant, vidange par outlet dominant, gonflement ou dégonflement d'un volume mobile/déformable. Le bilan global doit être la conséquence des lois locales de CL. Un contrôleur global de masse/densité pourra exister ultérieurement, mais seulement comme option explicite.

## Pool de slots inactifs

x18f utilise `INACTIVE_SLOTS_CELL_FRACTION` en topologie segmentée (défaut `1.0`). Cette variable est distincte de `INACTIVE_SLOTS_FRACTION`. Augmenter le pool peut repousser un épuisement de capacité, mais ne corrige pas un biais physique du bain Neumann.

## Statut final du chantier

- x18d : `VALIDATED/FUNCTIONAL`, diagnostics lourds opt-in ;
- x18e : `VALIDATED/FUNCTIONAL`, sous-cyclage local et gardes anti-hang ;
- x18a/x18f `inlet_neumann` : `VALIDATED/FUNCTIONAL` ;
- x18b/x18f `double_neumann` : fonctionnel qualitativement, **non qualifié quantitativement en masse** ;
- x18f-fix1 : **NOT_APPLIED / NOT_CANONICAL**.

Le sweep `U -> theta` doit utiliser x18a `inlet_neumann`; il n'est pas bloqué par le chantier ultérieur des frontières outlet-only.

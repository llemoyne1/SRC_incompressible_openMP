# Jalons par nature

> Les jalons sont regroupés par **nature canonique** puis triés, dans chaque groupe, en ordre **naturel numérique et alphabétique** (`x9z < x10a`, `fix2 < fix10`).

## ABLATION

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x10e` | Miroir tangent du endpoint final | FREE_SURFACE_KINETICS | Expérience de forme/isotropie historique, retirée avec la barrière universelle par x10h |
| `x10f` | Ablation réaction exacte sur réservoir liquide global | FREE_SURFACE_KINETICS | Ablation causale; non production multi-gouttes, code conservé sans call-site actif |
| `x10j` | Ablation spéculaire dans le repère laboratoire | FREE_SURFACE_KINETICS | Ablation rejetée : conservation de norme labo mais dripping fortement bloqué; OFF production |
| `x10k` | Ablation spéculaire dans le repère liquide local | FREE_SURFACE_KINETICS | Ablation rejetée; améliore la covariance locale mais ne fournit pas la fermeture de production |
| `x10m` | Paroi locale mobile alpha=0.5 | FREE_SURFACE_KINETICS | Étape architecturale/ablation OFF production; scratch et primitives seront réutilisés par les étapes continues |
| `x10r` | Ablation vitesses endpoints full-vector | FREE_SURFACE_KINETICS | Ablation rejetée : dripping dégradé; OFF production |
| `x10s` | Ablation cinématique normale au segment | FREE_SURFACE_KINETICS | Ablation rejetée/OFF; incompatible avec le vrai Q2 de production |
| `x10t` | Ablation cinématique tangentielle rigide | FREE_SURFACE_KINETICS | Ablation rejetée : impulse parasite aggravée; OFF production |
| `x13o` | Ablation swap normal-only | TRANSPORT_SURFACE | Ablation OFF production; le tag qualifié utilise le swap full-vector x10v |
| `x13p` | Zone de crossing libre autour de l’interface | TRANSPORT_SURFACE | Expérience post-x13n; amélioration TC partielle mais non retenue |
| `x13q` | Turnover des orphelins de fermeture cinétique | TRANSPORT_SURFACE | Expérience de confinement post-x13n; absente du commit qualifié 7655b81 |
| `x13r` | Refroidissement direct des cellules interfaciales | TRANSPORT_SURFACE | Rejetée: fermeture discontinue et dépendante du masque; supersédée par x13t |
| `x13s` | Refroidissement interfacial anisotrope | TRANSPORT_SURFACE | Rejetée comme fermeture générale; supersédée par x13t |
| `x13t` | Refroidissement progressif unifié | TRANSPORT_SURFACE | Expérience causale rejetée comme chemin général après x13zd |
| `x13u` | Combinaison x13t + relocalisation one-for-one | TRANSPORT_SURFACE | Expérimental/rejeté; x13u fixe la combinaison mais pas la fermeture générale |
| `x13v` | Séparation position one-for-one / swap vitesse | TRANSPORT_SURFACE | Expérimental/rejeté; outil causal de séparation de x10u et x10v |
| `x13w` | Escape → inactive → reseed local | TRANSPORT_SURFACE | Rejeté: contraction artificielle du support de phase |
| `x13x` | Sweep de rétention probabiliste | TRANSPORT_SURFACE | Aucun compromis robuste vitesse/confinement; non production |
| `x14n` | Ablation fermeture gaz OFF | LIQUID_GAS | Ablation |
| `x14o` | Ablation pression gaz constante | LIQUID_GAS | Ablation |
| `x14y` | Ablation sans soustraction p_g | LIQUID_GAS | Rejeté: double comptage pression équilibre |
| `x14z` | Fermeture géométrique p_ref | LIQUID_GAS | Rejeté comme cause du défaut n=1 |

## ANALYZER

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x8b` | Attribution temporelle Darcy / résidu non-Darcy | Q6_GF | Analyseur hors ligne; aucune modification du solveur |
| `x8i` | Analyse du sillage VK établi par POD et sondes | OPEN_BOUNDARY | Analyseur du sillage établi; aucune modification du solveur |
| `x8j` | Nondimensionnalisation VK et comparaison bibliographique | OPEN_BOUNDARY | Analyse bibliographique/nondimensionnelle; enrichie plus tard par les diagnostics de flux x8n |
| `x8n` | Diagnostic de conservation amont du débit et du flux massique | OPEN_BOUNDARY | Diagnostic hors ligne du conditionnement et de la conservation amont; aucune modification du solveur |
| `x14r` | Analyse volume accessible | LIQUID_GAS | Diagnostic conduisant à x14s |

## BENCHMARK

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0493O0` | Références SRC seules avant réparation locale du support | MULTISPECIES_RESAMPLING | Référence historique pré-réparation |
| `0493W0` | Audit du régime cinétique du cas segmented-Darcy | SRC_CALIBRATION | Diagnostic historique du régime cinétique |
| `0493W2` | Référence segmented-Darcy sur fluide SRC calibré | SRC_CALIBRATION | Référence physique calibrée |
| `x7i` | Benchmark physique multi-cas SRC / Q6 / Q6-g-f | Q6_GF | Benchmark diagnostique de référence; sans seuil PASS/FAIL arbitraire |
| `x8f` | Premier candidat von Karman Q6-g-f à inlet/outlet ouverts | OPEN_BOUNDARY | Premier candidat VK ouvert; runner-only, ensuite prolongé/raffiné |
| `x8m` | Benchmark de production Zovatto-Pedrizzetti Re_H=280 | OPEN_BOUNDARY | Benchmark de production/restart Zovatto; première lignée sous x8l, ensuite réalignée sur la fermeture x8t |
| `x9q` | Test de potentialité jet gravitaire / pincement / impact | SURFACE_TENSION | Benchmark exploratoire sans seuil physique dur; démontre des changements de topologie et expose la faiblesse de courbure sous-résolue traitée par x9r |
| `x9s` | Benchmark paramétrable d'impact et splash | SURFACE_TENSION | Démonstration/qualification morphologique qualitative; pas une mesure convergée de Weber critique |
| `x12b` | Prototype JFM D=320h sur obstacle Darcy/chi | FREE_SURFACE_KINETICS | Benchmark exploratoire de construction; pas encore une reproduction quantitative JFM 524 |
| `x12c` | Benchmark JFM compact-Y à physique inchangée | FREE_SURFACE_KINETICS | Étape de production/compaction du benchmark; physique identique à x12b |
| `x12d` | Cas de mesure JFM 524 à géométrie/We/Fr ciblés | FREE_SURFACE_KINETICS | Benchmark applicatif de mesure; géométrie/We/Fr ciblés mais Re numérique ~649 au lieu de Re expérimental 12200 |
| `x13n` | Benchmark Taylor–Culick 2-D | TRANSPORT_SURFACE | Limite dynamique connue; référence de rollback G_TC≈0.795 à sigma=10000 |
| `x13z` | Exploration de changements de grille | TRANSPORT_SURFACE | Gains séduisants mais non suffisants pour validation |
| `x14ag` | Traînée avec inlet/outlet | LIQUID_GAS | Abandonné |
| `x14ah` | Traînée périodique-x | LIQUID_GAS | Benchmark intégré |
| `x14aj` | Goutte oscillante n=3 avec gaz | LIQUID_GAS | REVIEW: fréquence ~12% lente dans campagne actuelle |
| `x14ak` | Taylor-Culick diphasique - fluide x14 | LIQUID_GAS | REVIEW; ne pas utiliser pour isoler effet gaz |
| `x14al` | Taylor-Culick apparié au point x13h | LIQUID_GAS | Contrôle liquide reproduit; branche gaz à relire car EOS global kBT avait été mal aligné dans le premier runner |
| `x14aw` | Analogue 2-D Basilisk atomisation ReL=500 / WeG=200 | LIQUID_GAS | Benchmark exploratoire 2-D; géométrie et nombres sans revendication d’équivalence 3-D exacte avec Basilisk. |
| `x14j` | Goutte deux températures | LIQUID_GAS | Benchmark d'intégration |
| `x14t` | Piston pression thermodynamique | LIQUID_GAS | Qualification composante thermodynamique |
| `x14u` | Gaz incident normal | LIQUID_GAS | Diagnostic conduisant à x14v |
| `x14w` | Couette biphasique | LIQUID_GAS | PASS-like sur contrainte tangentielle |
| `x14x` | Goutte oscillante diphasique n=2 | LIQUID_GAS | Qualification intégrée/tooling |

## CALIBRATOR

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0493W1` | Calibrateur constitutif du fluide SRC | SRC_CALIBRATION | Calibrateur historique |
| `x8e` | Recalibration viscosité Q6-g-f et raideur Darcy | Q6_GF | Calibration Q6-g-f et carte de raideur Darcy; aucun changement du solveur |
| `x12cal` | Calibrateur dynamique de tension superficielle | SURFACE_TENSION | Calibrateur dynamique courant; aucune nouvelle physique C++ |
| `x12yl` | Calibrateur mécanique/statique de tension superficielle | SURFACE_TENSION | Calibrateur mécanique/statique courant; remplace x11a comme extraction scalaire de sigma_eff |
| `x13a` | Pré-balayage intrinsèque SRC haut-Re | TRANSPORT_SURFACE | Pré-balayage constitutif scripts-only; aucune physique solveur nouvelle |
| `x13d` | Follow-up longue longueur d’onde et amortissement | TRANSPORT_SURFACE | Calibration constitutive du point G08 de référence |
| `x13f` | Optimisation locale du transport G08 | TRANSPORT_SURFACE | Optimisation/calibration du fluide, pas optimisation de code |
| `x13i` | Loi d’échelle en kBT du fluide x13h | TRANSPORT_SURFACE | Calibration de similitude thermique du fluide x13h; scripts-only |
| `x13j` | Calibrateur transport autonome + qualification Young–Laplace x13h | TRANSPORT_SURFACE | Double rôle historique documenté; aucune nouvelle physique C++ |
| `x14au` | Qualification viscosité associée au cas Sato | LIQUID_GAS | Liquide primaire INVALID; gaz REVIEW; cohérence d’échelle 2σ diagnostique seulement |

## CAMPAIGN

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x14an` | Jet gazeux plan sur bain liquide | LIQUID_GAS | Campagne de construction/qualification; aucun PASS physique autonome inféré du runner |
| `x14ao` | Buse planaire Darcy/chi paramétrable | LIQUID_GAS | Étape géométrique de campagne; pas de qualification autonome revendiquée |
| `x14ap` | Buse Darcy/chi aux défauts de similitude expérimentale | LIQUID_GAS | Point de similitude de campagne; pas de PASS autonome |
| `x14aq` | Réservoirs gazeux ambiants latéraux | LIQUID_GAS | Expérience de condition limite; non retenue comme validation autonome |
| `x14ar` | Atmosphère hard-density sur le dessus hors buse | LIQUID_GAS | Expérience de condition limite; pas de PASS physique autonome |
| `x14as` | Buse à sorties larges, pression gaz comme covariable | LIQUID_GAS | Topologie retenue pour x14at; pression gaz traitée comme covariable mesurée |

## CODE

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0414` | Extension quadriface des open boundaries segmentées | OPEN_BOUNDARY | QUALIFIED |
| `0490B` | Dépôt cellule–espèce | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490C` | Resampling conservatif par espèce | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490D` | Fermeture de masse sensible à la phase | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490E` | Garde de population par espèce | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490F` | Refill d'espèces mixtes | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490G` | Transferts donneur–receveur par espèce | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490H` | Dépôt cellule–espèce CUDA | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490I` | Fermeture de masse multi-espèces CUDA | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490J` | Garde de population multi-espèces CUDA | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490K` | Plan de transferts multi-espèces CUDA | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0490N` | Maintenance résidente multi-espèces | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0491B` | Dépôt partagé et shadow CUDA species-Q6 | SPECIES_Q6 | Jalon historique attesté par documentation technique |
| `0491C` | Application CUDA opt-in du Q6 par espèce | SPECIES_Q6 | Jalon historique attesté par documentation technique |
| `0493B` | Resampling CUDA résident activable par espèce | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0493G` | Restauration locale des moments par espèce | MULTISPECIES_RESAMPLING | Correction physique historique |
| `0493J` | Fermeture conservative de l'énergie cinétique par espèce | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0493O1` | Population effective cible : split local piloté par Neff | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0493W5` | Q6 multi-espèces independent_masked — étape périodique | SPECIES_Q6 | Jalon historique documenté |
| `0493W7` | Q6 independent_masked sur toutes les familles de frontières résidentes | SPECIES_Q6 | Jalon historique documenté et qualifié |
| `Q6` | Projection quasi-incompressible | CORE | Socle actif selon RUN_MODE |
| `Q6-g` | Q6 force-aware | CORE | Introduit par x3, base de Q6-g-f |
| `Q6-g-f` | Q6 force-aware + interface + face-particule + densité | CORE | Chaîne de projection de référence |
| `Q9` | Relaxation basse fréquence du flux de masse | CORE | Historique / séparée du chemin Q6-g-f actuel |
| `SRC/MPCD` | Collision particulaire SRC/MPCD | CORE | Socle actif |
| `x1` | Chemin de frontières closed-box CUDA résident | BOUNDARY | Étape historique qualifiée pour la démonstration dam-break |
| `x3` | Q6-g force-aware — preuve de concept prestream à deux solves | Q6_GF | Preuve de concept validant la cause; supplantée par x4a |
| `x4a` | Q6-g prestream_single — un solve Q6 par pas forcé | Q6_GF | Référence mono-solve; supplantée par la fusion x4b |
| `x5a` | Q6-g free_surface_masked — premier liquide partiellement rempli | Q6_GF | Première fermeture liquide-vide; support numérique encore assimilé à l'interface |
| `x6d` | Expérience cut-face 1/theta sur le bord du carrier | Q6_GF | Expérience active historique; architecture abandonnée au profit de x6f |
| `x6f` | Stencil résident de pression sur l'interface physique alpha=0.5 | Q6_GF | Architecture d'interface retenue; géométrie bornée par x6f2 avant x6g |
| `x6g` | Condition de pression gazeuse sur l'interface physique | Q6_GF | Couplage pression gaz actif sur interface résidente; base du futur terme capillaire |
| `x6h-B1` | Reconstruction affine RT0/MAC des corrections face-vers-particule | Q6_GF | Reconstruction face-particule active dans le profil Q6-g-f qualifié |
| `x7a` | Kick viriel de densité CUDA résident | Q6_GF | Expérience de restauration explicite; abandonnée au profit de la cible de divergence x7c/x7d |
| `x7c` | Restauration de densité intégrée au RHS Q6 | Q6_GF | Mécanisme RHS retenu conceptuellement; paramétrage physique raffiné par x7d |
| `x7d` | Constante de temps physique de restauration de densité | Q6_GF | Paramétrage physique retenu; tau_rho=0.25 dans la chaîne qualifiée |
| `x7d-v2` | Gate cohérent de compression pour la restauration de densité | Q6_GF | Actif dans le profil Q6-g-f qualifié; gate désactivé = comportement x7d historique |
| `x7d-v2-signed1` | Restauration de densité signée à gates cohérents | Q6_GF | Actif dans le profil final signé; qualifié avec la chaîne x7q |
| `x7f` | Extension Q6-g-f aux familles statiques multi-BC | Q6_GF | Actif sur les familles statiques qualifiées; Darcy encore exclu à cette étape |
| `x7g` | Darcy-Brinkman placé avant la projection Q6-g-f | Q6_GF | Actif sur le sous-ensemble Darcy/chi qualifié |
| `x7m` | Garde topologique monophase par registre de phases | Q6_GF | Étape initiale; complétée par x7m-fix1 |
| `x7o` | Symétrisation par réflexion du Q6 independent_masked | Q6_GF | Actif; corrige le biais est/nord du fullDomain independent_masked |
| `x7p` | Symétrisation par réflexion du Q6 commun | Q6_GF | Actif; enlève l'orientation backward-difference historique du Q6 commun |
| `x7q` | Fermeture exacte du moment périodique au niveau particulaire B1/RT0 | Q6_GF | Actif automatiquement pour B1 + fullDomain + direction périodique; chemin partiel/dam-break historique inchangé |
| `x8k` | Inlet segmenté à profil de Poiseuille local | OPEN_BOUNDARY | Actif; sémantique de profil local retenue dans le benchmark Zovatto |
| `x8l` | Première extrapolation Neumann passive de la vitesse de sortie | OPEN_BOUNDARY | Étape intermédiaire conservée : extrapolation de vitesse retenue comme base par x8r, mais sémantique de projection x8l seule supersédée |
| `x8q` | Continuation cinétique locale de l'outlet Neumann | OPEN_BOUNDARY | Actif pour outlet Neumann; forme finale local-bath après les sous-révisions x8q-fix1..fix4 |
| `x8r` | Outlet de pression Neumann Q6-g-f | OPEN_BOUNDARY | Actif; sémantique pression passive du mode openBoundaryOutletMode=neumann |
| `x8t` | Cible de relaxation de densité sans mode moyen à outlet pression | OPEN_BOUNDARY | Actif dans le couplage fullDomain + x8r + relaxation densité; autres topologies inchangées |
| `x9d` | Premier saut de Laplace actif dans Q6-g-f | SURFACE_TENSION | Coeur actif de la capillarité bulk; sigma=0 est un no-op exact |
| `x9g` | Généralisation de l'interface aux paires de phases A/B | SURFACE_TENSION | Actif; abstraction de paire sans prétendre fournir un solveur immiscible symétrique général |
| `x9h` | Provider géométrique résident de paroi | SURFACE_TENSION | Géométrie-only qualifiée; capillarité/mouillage avec B=wall encore interdits à cette étape |
| `x9i` | Première fermeture d'angle de contact par normale imposée | SURFACE_TENSION | Prototype historique : angle local exact mais biais de div(n)/courbure; conservé comme baseline derrière un gate de test |
| `x9j` | Fermeture d'angle par ghost-alpha de courbure | SURFACE_TENSION | Prototype historique supplanté : améliore certains angles mais ne préserve pas suffisamment la géométrie multi-couche |
| `x9k` | Ghost-alpha par miroir cisaillé | SURFACE_TENSION | Prototype historique supplanté : angle robuste mais une transformation affine ne préserve pas un cercle, donc biais de courbure angle-dépendant |
| `x9l` | Reconstruction de normale au mur-face | SURFACE_TENSION | Expérience négative hors voisinage de 90 degrés; gardée comme comparaison et supplantée par x9m |
| `x9m` | Fermeture statique de mouillage par ancre hors support | SURFACE_TENSION | Fermeture statique préférée du cycle x9; robuste géométriquement, mais dynamique de ligne triple non universellement fermée |
| `x9t` | Première rétention cinétique liquide-vide conservative | FREE_SURFACE_KINETICS | Prototype actif de rétention cinétique; première étape du pont x9 vers la fermeture de surface libre x10 |
| `x9u` | Extension de la réflexion aux sorties de support | FREE_SURFACE_KINETICS | Étape active intermédiaire; couverture support-edge améliorée mais le choix de bain sera corrigé par x9w |
| `x9x` | Réflexion au crossing physique prédit | FREE_SURFACE_KINETICS | Étape active intermédiaire : déclenchement géométrique au crossing physique, sans nouvelle passe globale |
| `x9z` | Réflexion individuelle des donneurs et compensation affine du bain | FREE_SURFACE_KINETICS | Dernière étape x9 du mécanisme de rétention; loi individuelle explicitement réutilisée ensuite par x10a |
| `x10a` | Géométrie de crossing et seal du endpoint réfléchi | FREE_SURFACE_KINETICS | Étape géométrique historique; fondation des essais de confinement x10b-x10e, ensuite supplantée par la paroi mobile continue |
| `x10b` | Rétention hard-r1 des particules de shell | FREE_SURFACE_KINETICS | Étape historique hard-r1; sur-confinement ensuite corrigé par x10h |
| `x10biq` | Reconstruction Q2 biquadratique tensorielle | FREE_SURFACE_KINETICS | Vrai Q2 actif dans la chaîne x12; x10r/s/t doivent être OFF |
| `x10c` | Barrière universelle du endpoint final r=1 | FREE_SURFACE_KINETICS | Étape historique de confinement universel; retirée par x10h car incompatible avec une interface réellement mobile |
| `x10cic` | Alpha cinétique CIC dédié | FREE_SURFACE_KINETICS | Composant actif de la chaîne x12; orchestration encore appelée depuis le chemin Q6 |
| `x10d` | Réaction analytique locale exactement conservative P/K | FREE_SURFACE_KINETICS | Branche analytique historique; définition conservée mais orchestration hard-r1 courante la bypass au profit de x10i/x10o |
| `x10i` | Réaction exacte par réservoirs mésoscopiques décalés | FREE_SURFACE_KINETICS | Fallback hard-r1 legacy encore actif hors ablations continues; bypassé par x10o dans la chaîne x12 |
| `x10o` | Paroi cinétique Q6 hydrodynamique à enveloppe thermique | FREE_SURFACE_KINETICS | Socle actif de la chaîne liquide qualifiée x12; priorité sur x10j/k/m/n |
| `x10u` | Relocalisation conservative one-for-one | FREE_SURFACE_KINETICS | Actif dans la chaîne liquide qualifiée; requiert Q2 et x10p |
| `x10v` | Swap local full-vector one-for-one | FREE_SURFACE_KINETICS | Actif dans la chaîne liquide qualifiée; utilise un byte/particule et deux kernels conditionnels |
| `x10w` | Limiter thermique local pairwise | FREE_SURFACE_KINETICS | Implémenté mais OFF production; exclusif avec x12a dans le snapshot audité |
| `x12a` | Refroidissement thermique local des petites structures | FREE_SURFACE_KINETICS | Actif dans la chaîne liquide qualifiée; exclusif avec le limiter x10w |
| `x14aa` | Traction thermodynamique absolue sur faces x6g | LIQUID_GAS | Non retenu: dégrade la géométrie locale de forme |
| `x14ab` | p_ref sur x10n + jauge sur faces x6g | LIQUID_GAS | Non retenu |
| `x14ac` | Projection globale minimum-L2 | LIQUID_GAS | Principe conservé, local supplanté par x14ad |
| `x14ad` | Traction locale cohérente avec faces x6g | LIQUID_GAS | Retenu pour interfaces courbes x14 |
| `x14ai` | Fermeture de résultante Q6 appliquée | LIQUID_GAS | Concept retenu mais version initiale supplantée |
| `x14ai-fix1` | Fermeture B1 exacte post-correction périodique | LIQUID_GAS | Seulement composante liquide fermée et isolée des frontières Q6 externes |
| `x14ba` | Oscillation globale sinusoïdale de vitesse d’entrée | OPEN_BOUNDARY_MULTIPHASE | Chemin désactivé strictement neutre; checker statique/maths PASS et chemin pulsé exercé ensuite par le smoke x14bc. Qualification longue du breakup non encore revendiquée. |
| `x14d` | Collision commune + thermostats séparés | LIQUID_GAS | Actif dans x14 |
| `x14k` | Géométrie cinétique bilatérale | LIQUID_GAS | Opt-in; change le modèle d'interface |
| `x14l` | Réflexion spéculaire du gaz | LIQUID_GAS | Qualifié pour imperméabilité normale dans cas tests |
| `x14m` | Assemblage bilatéral + compatibilité x12a | LIQUID_GAS | Architecture intégrée |
| `x14s` | EOS gaz volume accessible | LIQUID_GAS | Actif dans x14 récent |
| `x14v` | Kick cinétique excédentaire | LIQUID_GAS | Actif dans chaîne x14 candidate |

## DEMONSTRATION

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x13ze` | Démonstrations run_ok impact/puddle stabilisées | FREE_SURFACE_KINETICS | Démonstration historique stabilisée; pas une nouvelle qualification physique |
| `x13zf` | Démonstration run_ok dripping qualitative | FREE_SURFACE_KINETICS | Démonstration qualitative historique stabilisée; non benchmark quantitatif |
| `x14av` | Démonstration atomiseur air-assisté | LIQUID_GAS | DEMONSTRATION_DIAGNOSTIC_ONLY; aucune qualification physique d’atomisation |

## DIAGNOSTIC

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0490N-fix1` | Télémétrie résidente par espèce | MULTISPECIES_RESAMPLING | Diagnostic historique |
| `0493W6` | Diagnostic de divergence après application du Q6 masqué | SPECIES_Q6 | Diagnostic historique documenté |
| `x2` | Diagnostic liquide plein : force appliquée avant une projection Q6 trop tardive | Q6_GF | Diagnostic causal; mène directement à x3 |
| `x6a` | Diagnostic EOS de pression gazeuse interfaciale | Q6_GF | Diagnostic EOS préparatoire; aucune rétroaction sur le solveur |
| `x6b` | Diagnostic géométrique support Q6 / interface alpha=0.5 | Q6_GF | Diagnostic géométrique; prépare la matérialisation résidente x6c |
| `x6e` | Audit topologique de l'interface physique alpha=0.5 | Q6_GF | Diagnostic architectural décisif; motive pressureMask séparé de x6f |
| `x6h-B0` | Diagnostic régional de divergence après application aux particules | Q6_GF | Diagnostic sparse OFF en production; motive la reconstruction B1 |
| `x7b` | Sémantique continue et diagnostic de grille du viriel | Q6_GF | Consolidation sémantique de l'ablation virielle; stratégie ensuite remplacée par x7c |
| `x7n` | Calibrateur de fluide sélectionnable par chemin et diagnostic compression/bruit | Q6_GF | Diagnostic/calibrateur de chemin; précède les corrections x7d-v2 et la qualification x7q |
| `x8a` | Diagnostic exact du moment Darcy | Q6_GF | Diagnostic opt-in; OFF en production |
| `x8c` | Localisation temporaire du moment par étapes | Q6_GF | Instrumentation temporaire retirée après campagne; preuve historique conservée |
| `x9a` | Premier scaffold passif de courbure résident | SURFACE_TENSION | Scaffold passif historique; géométrie seulement, sans tension superficielle active |
| `x9b` | Courbure passive binomiale + Scharr et LiveVis résident | SURFACE_TENSION | Estimateur passif p1 conservé comme baseline; aucune physique capillaire active |
| `x9e` | Qualification diagnostique de goutte statique | SURFACE_TENSION | Diagnostic/qualification au-dessus de x9d; physique inchangée |
| `x9f` | Diagnostic de bande interfaciale vraie et relaxation elliptique | SURFACE_TENSION | Diagnostic de forme/relaxation au-dessus de x9e; aucune modification de la capillarité |
| `x9v` | Diagnostic des voies de fuite de la fermeture x9u | FREE_SURFACE_KINETICS | Diagnostic passif; aucune nouvelle passe particulaire ni modification de physique |
| `x10l` | Diagnostic passif pré-paroi cinétique | FREE_SURFACE_KINETICS | Diagnostic observation-only encore activable; ON dans certains runners JFM, aucune modification vitesse/position |
| `x11c` | Correction de protocole capillaire et baseline sigma=0 | SURFACE_TENSION | Correction analyse/protocole et support observation-only; aucune nouvelle physique capillaire |
| `x13b` | Carte constitutive SRC H/C | TRANSPORT_SURFACE | Métrologie constitutive scripts-only; aucune modification src/include |
| `x13za` | Comparaison gouttes oscillantes entre grilles | TRANSPORT_SURFACE | Diagnostic de dépendance de grille de la dynamique capillaire |
| `x13zb` | Comparaison Young–Laplace entre grilles | TRANSPORT_SURFACE | Diagnostic; la régression brute forte-sigma n’est pas une mesure physique robuste de sigma_eff |
| `x13zb2` | Baseline sigma=0 courte pour comparaison de grille | TRANSPORT_SURFACE | Essai de protocole; ne ferme pas le biais de baseline |
| `x13zb3` | Audit de stabilité et rebaseline Young–Laplace | TRANSPORT_SURFACE | Diagnostic de baseline; motive l’abandon de la référence libre longue sigma=0 |
| `x13zc` | Mécanique statique de goutte versus grille | TRANSPORT_SURFACE | Diagnostic de représentation; R_eff plus petit sur grille fine explique une part majeure du shift fréquentiel |
| `x14ae` | Diagnostic pertes scatter | LIQUID_GAS | Diagnostic; pertes nulles sur cas discriminant |
| `x14af` | Diagnostic bilan global | LIQUID_GAS | Diagnostic causal |
| `x14am` | Young-Laplace diphasique multi-rayons | LIQUID_GAS | REVIEW/non décisif à sigma=10000: kappa_active et pression sont déjà connus comme métrologie bruyante/non monotone dans ce régime |
| `x14ax` | Recorder alpha_x6c du champ liquide physique résident | LIQUID_GAS | Diagnostic intégré et utilisé dans les campagnes d’interface; ne modifie pas la fermeture physique lorsque le champ n’est pas demandé. |
| `x14p` | Audit offline alpha/volume gazeux accessible | LIQUID_GAS | Diagnostic offline; aucune loi CUDA proposée à ce stade |
| `x14q` | Fit offline de fraction de volume accessible | LIQUID_GAS | Diagnostic offline; explicitement pas une proposition CUDA |

## EXPERIMENT

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x8r-neumann-species` | Variante x8r Neumann cinétique séparée par espèce | OPEN_BOUNDARY_MULTIPHASE | Tentative expérimentale post-x14av; construction et checks statiques PASS, mais la famille de reconstruction par bain reste non retenue après échec à l'arrivée de l'interface; supersédée par x8v. |
| `x8v` | Réplique microscopique miroir pour Neumann cinétique | OPEN_BOUNDARY_MULTIPHASE | Prototype physics-first; checks de packaging PASS mais échec runtime précoce rapporté par x8w; non retenu, supersédé par x8w. |
| `x8w` | Cellules virtuelles statistiques Neumann | OPEN_BOUNDARY_MULTIPHASE | Échec expérimental documenté: la copie de l'occupation instantanée de la cellule de bord crée une couche de densité précoce; supersédé par x8x. |
| `x8x` | Réservoir virtuel Neumann coarse-grained | OPEN_BOUNDARY_MULTIPHASE | Améliore le défaut x8w et passe les checks analytiques de demi-flux, mais la densité de réservoir suit encore le déficit de densité intérieur; supersédé par x8y. |
| `x8y` | Réservoir de pression Neumann à densité de référence | OPEN_BOUNDARY_MULTIPHASE | Échec post-contact documenté: un ux liquide intérieur négatif est recopié dans le Maxwellien extérieur et transforme le réservoir en injecteur macroscopique; supersédé par x8z. |
| `x14ay` | Raffinement particulaire gamma 12/16 à similitude thermique | LIQUID_GAS | Smoke gamma=12 exploitable mais amélioration interfaciale jugée trop faible face au surcoût; gamma=12/16 non retenu pour le benchmark courant. |

## FIX

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0490M-fix2` | Fermeture conservative multi-espèces | MULTISPECIES_RESAMPLING | Correctif historique |
| `0490N-fix2` | Matérialisation des transferts multiples | MULTISPECIES_RESAMPLING | Correctif historique |
| `0491H-fix1` | Correctif final et qualification approfondie species-Q6 | SPECIES_Q6 | Correctif historique qualifié |
| `0493C-fix3` | Alignement du population guard medium sur gamma | MULTISPECIES_RESAMPLING | Correctif historique attesté par Git |
| `0493D-fix1` | Rejeu déterministe du state-update après sélection parallèle | MULTISPECIES_RESAMPLING | Correctif historique attesté par Git |
| `0493F-fix2` | Cas deux-espèces physiquement neutre | MULTISPECIES_RESAMPLING | Correctif de qualification historique |
| `0493I` | Fermeture conservative mono-espèce sur le chemin résident | MULTISPECIES_RESAMPLING | Correctif physique attesté par le code |
| `0493O1-fix2` | Autorité CUDA du split-only local | MULTISPECIES_RESAMPLING | Correctif de sûreté résident attesté par le code |
| `0493O2-fix1` | Runner TG mono/dual-espèces pour la réparation de support | MULTISPECIES_RESAMPLING | Sous-jalon historique explicitement attesté |
| `0493W3` | Correction de l'injection sur cellule partielle d'une entrée segmentée | BOUNDARY | Correctif historique attesté par Git |
| `x6f2` | Correction : géométrie de phase bornée avant filtrage | Q6_GF | Correctif géométrique actif de la chaîne x6f/x6g |
| `x6h-A` | Correctif des corrections de faces physiques basses | Q6_GF | Correctif de reconstruction des faces basses actif dans Q6-g-f |
| `x7d-v2-fix2` | Première fermeture du moment périodique B1 au niveau cellule | Q6_GF | Correctif intermédiaire actif historiquement; fermeture k=0 centrée cellule ensuite rendue exacte au niveau particulaire par x7q |
| `x7f-fix2` | Correctif de garde wall-simple pour canal mixte | Q6_GF | Correctif actif du périmètre x7f |
| `x7m-fix1` | Domaine de pression monophase persistant | Q6_GF | Correctif structurel actif du chemin monophase |
| `x8z` | Clamp du backflow normal du réservoir Neumann | OPEN_BOUNDARY_MULTIPHASE | Correction partielle: le mode catastrophique normal est ciblé, mais le run 200x400 montre encore une propagation tangentielle du liquide à l'outlet; supersédé par x9a-neumann. |
| `x9a-neumann` | Annulation du drift complet du réservoir en backflow | OPEN_BOUNDARY_MULTIPHASE | Correction partielle: supprime le mode backflow/sliding dominant, mais le test 200x400 laisse un obstacle cinétique résiduel à la sortie du liquide; supersédée par x9b-neumann. |
| `x9b-neumann` | Réservoir gaz avec outflow liquide strict | OPEN_BOUNDARY_MULTIPHASE | Amélioration forte du déchargement liquide sur 200x400 et 400x400, mais révèle un artefact topologique de type 'hachoir': perte de support alpha au dernier maillon et création d'un end-cap artificiel; supersédée par x9c-outlet. |
| `x9c-outlet` | Prolongation du support de phase à l'outlet Neumann | OPEN_BOUNDARY_MULTIPHASE | Candidat physics-first retenu après runs applicatifs 200x400 et 400x400: comportement de frontière jugé convaincant et réduction nette du hachage visuel; petites détachements résiduels possibles au 200x400, non évidents au 400x400. Qualification qualitative ciblée seulement; l'analyseur x14av reste DEMONSTRATION_DIAGNOSTIC_ONLY. |
| `x9e-fix1` | Correction de compilation du banner x9e-neumann | OPEN_BOUNDARY_MULTIPHASE | Correctif de compilation historique; aucune loi physique ni logique de performance modifiée. |
| `x9e-fix2b` | Invariant ciblé sur la liste des slots supprimés | OPEN_BOUNDARY_MULTIPHASE | Correctif intermédiaire de x9e-fix2; le diagnostic de premier fallback montre qu’un pas hard-reservoir légitime peut avoir un bilan net négatif et motive x9e-fix3. |
| `x9r` | Cutoff de résolution du saut capillaire | SURFACE_TENSION | Correctif actif de courbure sous-résolue; seuil à choisir selon résolution/campagne, non constante physique universelle |
| `x9w` | Bain de recul strictement bulk | FREE_SURFACE_KINETICS | Correctif actif de sélection du bain; recherche bornée à deux cellules et conservation P/K maintenue |
| `x9y` | Côté alpha pointwise et crossing par bissection bornée | FREE_SURFACE_KINETICS | Correctif géométrique actif de x9x; supprime l'aliasing centre-cellule sans buffer ou passe globale supplémentaire |
| `x10h` | Rétention relative compatible avec interface mobile | FREE_SURFACE_KINETICS | Sémantique legacy intégrée; barrière universelle supprimée, chemin ensuite bypassé par x10o en production x12 |
| `x10p` | Résolution des recouvrements initiaux | FREE_SURFACE_KINETICS | Actif en production x12; aucune passe particulaire supplémentaire |
| `x10q` | Récupération large des recouvrements initiaux rares | FREE_SURFACE_KINETICS | Actif en production x12; complète x10p sans élargir le hot path normal |
| `x13w-fix3` | Reseed sur moyenne pré-échappement | TRANSPORT_SURFACE | Correctif utilisé dans x13zd; mécanisme x13w reste invalidé physiquement |
| `x13zn` | Nettoyage runner injection | RUN_OK | Correctif runner-only attesté; aucune modification solveur |
| `x14g` | Cellules exactes post-stream/grid-shift | LIQUID_GAS | Correctif d'intégration actif |

## INFRA

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0490A` | Registre des espèces | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `0491A` | Contrat Q6 sensible à l'espèce | SPECIES_Q6 | Jalon historique documenté |
| `0492` | Refresh et contrat des run_ok | RUN_OK_INFRA | Infrastructure runner historique qualifiée |
| `0493A` | Routage universel du resampling multi-espèces résident | MULTISPECIES_RESAMPLING | Jalon historique documenté |
| `Q6 multi-espèces` | Projection sélective par espèce | CORE | Socle multi-espèces |
| `x6c` | Infrastructure résidente du champ de phase alpha | Q6_GF | Infrastructure géométrique résidente; base des stencils d'interface ultérieurs |
| `x7h` | Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f | Q6_GF | Infrastructure de démonstration et régression |
| `x8h` | Restart hydrodynamique pour les longs runs VK | OPEN_BOUNDARY | Infrastructure de continuation hydrodynamique; RNG non bitwise continu |
| `x8u` | Réalignement du runner Zovatto sur la fermeture x8t | OPEN_BOUNDARY | Réintégration production de la fermeture x8t dans la lignée x8m; clôture documentaire du cycle x8 |
| `x10n` | Interface continue marching-squares mobile | FREE_SURFACE_KINETICS | Architecture continue OFF comme mode autonome; primitives réutilisées par x10o, Q2, x12a et suites |

## PERF

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0490M` | Chemin rapide résident multi-espèces | MULTISPECIES_RESAMPLING | Optimisation historique |
| `0490P` | Politique cellule sur device / zéro CPU | MULTISPECIES_RESAMPLING | Architecture historique |
| `0493D` | Sélection parallèle déterministe des transferts résidents | MULTISPECIES_RESAMPLING | Jalon d'optimisation attesté par le code |
| `0493O3` | Early-exit résident lorsqu'aucune paire cellule/espèce n'est pauvre | MULTISPECIES_RESAMPLING | Optimisation résidente historique |
| `x4b` | Q6-g prestream_single_fused — fusion CUDA force + projection | Q6_GF | Séquençage temporel Q6-g de référence pour la suite de 0493x |
| `x7j` | CG Q6-g-f entièrement CUDA résident | Q6_GF | Optimisation majeure du solve Q6-g-f; fallback hôte conservé |
| `x7k` | Stripping des diagnostics Q6-g-f en production | Q6_GF | Optimisation de télémétrie active en production |
| `x7l` | Stripping de la télémétrie thermostat/espèces | Q6_GF | Optimisation de télémétrie active; thermostat physique inchangé |
| `x8s` | Déflation exacte des modes longitudinaux lents du CG | OPEN_BOUNDARY | Actif uniquement dans la géométrie x8r pleine hauteur applicable; physique inchangée |
| `x9d-fix1-neumann` | Workspace résident et comptages exacts pour la continuation Neumann | OPEN_BOUNDARY_MULTIPHASE | Optimisation structurelle attestée et smoke physique court cohérent avec x9c-outlet; gain de performance NON QUALIFIE car le triplet baseline/optimisé/baseline présente une dispersion murale supérieure à l'effet mesuré. |
| `x9e-fix2` | Fast path par invariant comptable de compacité | OPEN_BOUNDARY_MULTIPHASE | Optimisation intermédiaire; l’hypothèse de pas équilibré s’avère trop restrictive pour le hard-reservoir réel et est remplacée par x9e-fix2b puis x9e-fix3. |
| `x9e-fix3` | Réparation ciblée exacte du préfixe actif | OPEN_BOUNDARY_MULTIPHASE | Chemin de production intégré à surf et qualifié au niveau implémentation/non-régression: algorithme pré-cleanup passé sur 3000 pas; cleanup final passé sur smoke surf 400x400 250/250 avec fast path ciblé actif et sans fallback observé. Physique x9c-outlet inchangée; aucune qualification universelle de toutes les sorties Neumann n’est revendiquée. |
| `x9e-neumann` | Pool résident de recyclage des slots supprimés | OPEN_BOUNDARY_MULTIPHASE | Optimisation de base intégrée à surf; physique x9c-outlet inchangée. La réparation de préfixe initiale est ensuite raffinée par x9e-fix2, x9e-fix2b puis x9e-fix3. |
| `x10g` | Réduction GPU hiérarchique de la réaction globale | FREE_SURFACE_KINETICS | Optimisation performance-only de x10f; physique identique, code conservé sans call-site actif |

## QUALIFICATION

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0490L` | Validation du resampling résident multi-espèces | MULTISPECIES_RESAMPLING | Qualification historique |
| `0491D` | Matrice des chemins species-Q6 | SPECIES_Q6 | Qualification historique |
| `0491E` | Audit strict du Q6 résident par espèce | SPECIES_Q6 | Qualification historique |
| `0491F` | Validation énergie et thermostat du species-Q6 | SPECIES_Q6 | Qualification historique |
| `0491G` | Qualification frontières ouvertes et Darcy du species-Q6 | SPECIES_Q6 | Qualification historique |
| `0491H` | Campagne consolidée de validation species-Q6 | SPECIES_Q6 | Qualification historique consolidée |
| `0493C` | Qualification du resampling multi-espèces résident | MULTISPECIES_RESAMPLING | Qualification historique |
| `0493E` | Qualification physique mono-espèce du resampling | MULTISPECIES_RESAMPLING | Qualification physique historique |
| `0493F` | Qualification physique à deux espèces du resampling | MULTISPECIES_RESAMPLING | Qualification physique historique |
| `0493H` | Diagnostic physique par onde de cisaillement périodique | MULTISPECIES_RESAMPLING | Diagnostic physique historique |
| `0493O4` | Qualification de la réparation de support en segmented-Darcy | MULTISPECIES_RESAMPLING | Qualification historique |
| `0493W8` | Équivalence Taylor--Green mono / dual-identique du Q6 independent_masked | SPECIES_Q6 | Qualification historique consolidée |
| `Resampling` | Contrôle du support particulaire | CORE | Module séparé, OFF dans les qualifications surface libre récentes |
| `x5a2` | Qualification dam-break liquide-vide du free_surface_masked | Q6_GF | Qualification discriminante; motive la séparation support/interface de x6 |
| `x5b` | Qualification liquide-gaz : Q6-g liquide et gaz compressible explicite | Q6_GF | Première qualification bi-espèces; couplage gaz-liquide encore collisionnel côté pression |
| `x7e` | Qualification combinée pression gaz x6g + restauration de densité x7d | Q6_GF | Qualification de composition Q6-g-f; kick viriel explicite désactivé |
| `x8d` | Qualification indépendante Q6-g-f par Poiseuille et Brinkman | Q6_GF | Qualification analytique du chemin Q6-g-f; aucun changement C++/CUDA |
| `x8g` | Qualification full-face et bilan de masse du VK | OPEN_BOUNDARY | Qualification full-face/mass-balance du candidat VK; runner-only |
| `x9c` | Qualification du support de lissage de courbure | SURFACE_TENSION | Qualification passive; sélectionne p3 pour la courbure de production, sans déplacer l'interface x6c |
| `x9n` | Qualification géométrique étendue de x9m | SURFACE_TENSION | Qualification scripts-only de la robustesse géométrique statique x9m |
| `x9o` | Qualification de phase sous-maille tangentielle de x9m | SURFACE_TENSION | Qualification scripts-only; quantifie la sensibilité résiduelle de x9m à la phase sous-maille |
| `x9p` | Qualification dynamique de goutte sessile x9m | SURFACE_TENSION | Résultat dynamique partiel : sens mouillage/démouillage correct, mais équilibre comprimé vers 90 degrés et courbure de ligne triple encore bruitée |
| `x10x` | Qualification de l’enveloppe thermique en C et sigma | FREE_SURFACE_KINETICS | Outil de qualification/campagne; aucun nouveau mode C++ |
| `x10y` | Analyse loi taille-température de l’enveloppe | FREE_SURFACE_KINETICS | Analyse scripts-only; aucun nouveau mode C++ |
| `x11a` | Qualification Young–Laplace quantitative | SURFACE_TENSION | Qualification historique quantitative; base de la calibration mécanique x12yl |
| `x11b` | Qualification de dispersion des ondes capillaires | SURFACE_TENSION | Qualification dynamique historique; base méthodologique du calibrateur x12cal |
| `x13c` | Qualification statistique du transport et choix gamma | TRANSPORT_SURFACE | Qualification constitutive multi-graines; gamma=8 retenu comme compromis coût/transport |
| `x13e` | Qualification de portée Mach du point G08 | TRANSPORT_SURFACE | Qualification compressible scripts-only; aucune modification src/include |
| `x13g` | Qualification de reproductibilité statistique GPU | TRANSPORT_SURFACE | Règle méthodologique de reproductibilité; aucune modification solveur |
| `x13h` | Point liquide de référence G08-120-L072 | TRANSPORT_SURFACE | Référence liquide qualifiée; rollback final vers le tag surf-tension-qualified-x13h-20260831 |
| `x13h-A` | Acoustique du point final lambda/h=0.72 | TRANSPORT_SURFACE | Sous-qualification constitutive A du fluide final |
| `x13h-B` | Viscosité et dépendance en densité du point final | TRANSPORT_SURFACE | Sous-qualification constitutive B du fluide final |
| `x13h-C` | Enveloppe Mach du point final | TRANSPORT_SURFACE | Sous-qualification constitutive C du fluide final |
| `x13k` | Qualification goutte oscillante n=2 | TRANSPORT_SURFACE | Qualification dynamique historique du point surface libre |
| `x13l` | Qualification goutte oscillante n=3 | TRANSPORT_SURFACE | Qualification dynamique historique |
| `x13m` | Qualification goutte oscillante n=4 | TRANSPORT_SURFACE | Qualification dynamique historique |
| `x13zd` | Validation croisée décisive et rollback | TRANSPORT_SURFACE | Invalide x13t+x13w comme chemin général; point de production ramené à surf-tension-qualified-x13h-20260831 |
| `x14a` | Smoke thermostat deux types | LIQUID_GAS | PASS des smokes thermostat deux types |
| `x14at` | Validation externe Sato Stage-A | LIQUID_GAS | Validation externe ciblée: H/D=0.8 et Fr_m≈0.49–0.59 à 4.8–9.9% de Sato; H/D=1.7 REVIEW; pas de similitude dynamique complète |
| `x14b` | Qualification thermostat avec collision SRC active | LIQUID_GAS | PASS active-collision exact-grid |
| `x14c` | Probe thermostat en grille décalée | LIQUID_GAS | PASS production-like shifted-grid probe |
| `x14e` | Qualification thermostat sur chemin SRC de production | LIQUID_GAS | PASS chemin SRC production résident |
| `x14f` | Qualification exacte thermostat sur src-q6-g-f | LIQUID_GAS | PASS x14f-fix1 exact src-q6-g-f |
| `x14i` | Qualification finale thermostat src-q6-g-f avec grid shift | LIQUID_GAS | PASS production shifted-grid resident species thermostat |

## RUNNER

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `0493W4` | Runner d'injection multi-espèces normalisé par famille de phase | MULTISPECIES_RUNNER | Jalon de runner attesté par le code et les inventaires |
| `x14bc` | Benchmark Basilisk froid pulsé ReL=500 | LIQUID_GAS | Calibration liquide TG128 8 graines PASS, CV=2.2%; smoke pulsé 300 pas PASS intégration/visualisation. Production longue 4758 pas planifiée, non encore qualifiée statistiquement. |

## TOOLING

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x13zg` | Profil run_ok surface libre qualifié | FREE_SURFACE_KINETICS | Profil run_ok de référence; chaîne x13h explicitement figée |
| `x13zj` | Harmonisation fluide de référence et LiveVis run_ok | RUN_OK | Harmonisation documentaire/outillage historique attestée par README Git |
| `x13zk` | Checker run_ok à sémantique physique | RUN_OK | Contrôle sémantique run_ok; aucune nouvelle physique |
| `x13zl` | Collection run_ok canonique homogène | RUN_OK | Collection run_ok homogénéisée |

## VISUALIZATION

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x0` | Démonstration dam-break bi-espèces du Q6 independent_masked | SPECIES_Q6 | Démonstration historique d'intégration |
| `x14az` | Affichage LiveVis direct de alpha_x6c | LIQUID_GAS | Diagnostic LiveVis opérationnel; smoothPasses neutralisé pour alpha_x6c afin de montrer le champ physique x6c sans lissage LiveVis additionnel. |

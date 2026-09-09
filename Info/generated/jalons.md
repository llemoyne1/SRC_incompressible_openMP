# Jalons canoniques SRC_GPU-SURF

> Cette liste contient uniquement les jalons **validés/canoniques** de la base. Les candidats Git non curés sont exclus.

## Socle fonctionnel (avant les jalons 0493x)

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `SRC/MPCD` | CODE | CORE | Collision particulaire SRC/MPCD | Socle actif |
| `Q6` | CODE | CORE | Projection quasi-incompressible | Socle actif selon RUN_MODE |
| `Q9` | CODE | CORE | Relaxation basse fréquence du flux de masse | Historique / séparée du chemin Q6-g-f actuel |
| `Resampling` | QUALIFICATION | CORE | Contrôle du support particulaire | Module séparé, OFF dans les qualifications surface libre récentes |
| `Q6 multi-espèces` | INFRA | CORE | Projection sélective par espèce | Socle multi-espèces |
| `Q6-g` | CODE | CORE | Q6 force-aware | Introduit par x3, base de Q6-g-f |
| `Q6-g-f` | CODE | CORE | Q6 force-aware + interface + face-particule + densité | Chaîne de projection de référence |

## x14 couplage liquide-gaz explicite

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x14d` | CODE | LIQUID_GAS | Collision commune + thermostats séparés | Actif dans x14 |
| `x14g` | FIX | LIQUID_GAS | Cellules exactes post-stream/grid-shift | Correctif d'intégration actif |
| `x14j` | BENCHMARK | LIQUID_GAS | Goutte deux températures | Benchmark d'intégration |
| `x14k` | CODE | LIQUID_GAS | Géométrie cinétique bilatérale | Opt-in; change le modèle d'interface |
| `x14l` | CODE | LIQUID_GAS | Réflexion spéculaire du gaz | Qualifié pour imperméabilité normale dans cas tests |
| `x14m` | CODE | LIQUID_GAS | Assemblage bilatéral + compatibilité x12a | Architecture intégrée |
| `x14n` | ABLATION | LIQUID_GAS | Ablation fermeture gaz OFF | Ablation |
| `x14o` | ABLATION | LIQUID_GAS | Ablation pression gaz constante | Ablation |
| `x14r` | ANALYZER | LIQUID_GAS | Analyse volume accessible | Diagnostic conduisant à x14s |
| `x14s` | CODE | LIQUID_GAS | EOS gaz volume accessible | Actif dans x14 récent |
| `x14t` | BENCHMARK | LIQUID_GAS | Piston pression thermodynamique | Qualification composante thermodynamique |
| `x14u` | BENCHMARK | LIQUID_GAS | Gaz incident normal | Diagnostic conduisant à x14v |
| `x14v` | CODE | LIQUID_GAS | Kick cinétique excédentaire | Actif dans chaîne x14 candidate |
| `x14w` | BENCHMARK | LIQUID_GAS | Couette biphasique | PASS-like sur contrainte tangentielle |
| `x14x` | BENCHMARK | LIQUID_GAS | Goutte oscillante diphasique n=2 | Qualification intégrée/tooling |
| `x14y` | ABLATION | LIQUID_GAS | Ablation sans soustraction p_g | Rejeté: double comptage pression équilibre |
| `x14z` | ABLATION | LIQUID_GAS | Fermeture géométrique p_ref | Rejeté comme cause du défaut n=1 |
| `x14aa` | CODE | LIQUID_GAS | Traction thermodynamique absolue sur faces x6g | Non retenu: dégrade la géométrie locale de forme |
| `x14ab` | CODE | LIQUID_GAS | p_ref sur x10n + jauge sur faces x6g | Non retenu |
| `x14ac` | CODE | LIQUID_GAS | Projection globale minimum-L2 | Principe conservé, local supplanté par x14ad |
| `x14ad` | CODE | LIQUID_GAS | Traction locale cohérente avec faces x6g | Retenu pour interfaces courbes x14 |
| `x14ae` | DIAGNOSTIC | LIQUID_GAS | Diagnostic pertes scatter | Diagnostic; pertes nulles sur cas discriminant |
| `x14af` | DIAGNOSTIC | LIQUID_GAS | Diagnostic bilan global | Diagnostic causal |
| `x14ag` | BENCHMARK | LIQUID_GAS | Traînée avec inlet/outlet | Abandonné |
| `x14ah` | BENCHMARK | LIQUID_GAS | Traînée périodique-x | Benchmark intégré |
| `x14ai` | CODE | LIQUID_GAS | Fermeture de résultante Q6 appliquée | Concept retenu mais version initiale supplantée |
| `x14ai-fix1` | CODE | LIQUID_GAS | Fermeture B1 exacte post-correction périodique | Seulement composante liquide fermée et isolée des frontières Q6 externes |
| `x14aj` | BENCHMARK | LIQUID_GAS | Goutte oscillante n=3 avec gaz | REVIEW: fréquence ~12% lente dans campagne actuelle |
| `x14ak` | BENCHMARK | LIQUID_GAS | Taylor-Culick diphasique - fluide x14 | REVIEW; ne pas utiliser pour isoler effet gaz |
| `x14al` | BENCHMARK | LIQUID_GAS | Taylor-Culick apparié au point x13h | Contrôle liquide reproduit; branche gaz à relire car EOS global kBT avait été mal aligné dans le premier runner |
| `x14am` | DIAGNOSTIC | LIQUID_GAS | Young-Laplace diphasique multi-rayons | REVIEW/non décisif à sigma=10000: kappa_active et pression sont déjà connus comme métrologie bruyante/non monotone dans ce régime |
| `x14p` | DIAGNOSTIC | LIQUID_GAS | Audit offline alpha/volume gazeux accessible | Diagnostic offline; aucune loi CUDA proposée à ce stade |
| `x14q` | DIAGNOSTIC | LIQUID_GAS | Fit offline de fraction de volume accessible | Diagnostic offline; explicitement pas une proposition CUDA |

## x0-x1 : dam-break bi-espèces et boîte fermée CUDA résidente

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x0` | VISUALIZATION | SPECIES_Q6 | Démonstration dam-break bi-espèces du Q6 independent_masked | Démonstration historique d'intégration |
| `x1` | CODE | BOUNDARY | Chemin de frontières closed-box CUDA résident | Étape historique qualifiée pour la démonstration dam-break |

## x10 : fermeture cinétique de surface libre

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x10a` | CODE | FREE_SURFACE_KINETICS | Géométrie de crossing et seal du endpoint réfléchi | Étape géométrique historique; fondation des essais de confinement x10b-x10e, ensuite supplantée par la paroi mobile continue |
| `x10b` | CODE | FREE_SURFACE_KINETICS | Rétention hard-r1 des particules de shell | Étape historique hard-r1; sur-confinement ensuite corrigé par x10h |
| `x10biq` | CODE | FREE_SURFACE_KINETICS | Reconstruction Q2 biquadratique tensorielle | Vrai Q2 actif dans la chaîne x12; x10r/s/t doivent être OFF |
| `x10c` | CODE | FREE_SURFACE_KINETICS | Barrière universelle du endpoint final r=1 | Étape historique de confinement universel; retirée par x10h car incompatible avec une interface réellement mobile |
| `x10cic` | CODE | FREE_SURFACE_KINETICS | Alpha cinétique CIC dédié | Composant actif de la chaîne x12; orchestration encore appelée depuis le chemin Q6 |
| `x10d` | CODE | FREE_SURFACE_KINETICS | Réaction analytique locale exactement conservative P/K | Branche analytique historique; définition conservée mais orchestration hard-r1 courante la bypass au profit de x10i/x10o |
| `x10e` | ABLATION | FREE_SURFACE_KINETICS | Miroir tangent du endpoint final | Expérience de forme/isotropie historique, retirée avec la barrière universelle par x10h |
| `x10f` | ABLATION | FREE_SURFACE_KINETICS | Ablation réaction exacte sur réservoir liquide global | Ablation causale; non production multi-gouttes, code conservé sans call-site actif |
| `x10g` | PERF | FREE_SURFACE_KINETICS | Réduction GPU hiérarchique de la réaction globale | Optimisation performance-only de x10f; physique identique, code conservé sans call-site actif |
| `x10h` | FIX | FREE_SURFACE_KINETICS | Rétention relative compatible avec interface mobile | Sémantique legacy intégrée; barrière universelle supprimée, chemin ensuite bypassé par x10o en production x12 |
| `x10i` | CODE | FREE_SURFACE_KINETICS | Réaction exacte par réservoirs mésoscopiques décalés | Fallback hard-r1 legacy encore actif hors ablations continues; bypassé par x10o dans la chaîne x12 |
| `x10j` | ABLATION | FREE_SURFACE_KINETICS | Ablation spéculaire dans le repère laboratoire | Ablation rejetée : conservation de norme labo mais dripping fortement bloqué; OFF production |
| `x10k` | ABLATION | FREE_SURFACE_KINETICS | Ablation spéculaire dans le repère liquide local | Ablation rejetée; améliore la covariance locale mais ne fournit pas la fermeture de production |
| `x10l` | DIAGNOSTIC | FREE_SURFACE_KINETICS | Diagnostic passif pré-paroi cinétique | Diagnostic observation-only encore activable; ON dans certains runners JFM, aucune modification vitesse/position |
| `x10m` | ABLATION | FREE_SURFACE_KINETICS | Paroi locale mobile alpha=0.5 | Étape architecturale/ablation OFF production; scratch et primitives seront réutilisés par les étapes continues |
| `x10n` | INFRA | FREE_SURFACE_KINETICS | Interface continue marching-squares mobile | Architecture continue OFF comme mode autonome; primitives réutilisées par x10o, Q2, x12a et suites |
| `x10o` | CODE | FREE_SURFACE_KINETICS | Paroi cinétique Q6 hydrodynamique à enveloppe thermique | Socle actif de la chaîne liquide qualifiée x12; priorité sur x10j/k/m/n |
| `x10p` | FIX | FREE_SURFACE_KINETICS | Résolution des recouvrements initiaux | Actif en production x12; aucune passe particulaire supplémentaire |
| `x10q` | FIX | FREE_SURFACE_KINETICS | Récupération large des recouvrements initiaux rares | Actif en production x12; complète x10p sans élargir le hot path normal |
| `x10r` | ABLATION | FREE_SURFACE_KINETICS | Ablation vitesses endpoints full-vector | Ablation rejetée : dripping dégradé; OFF production |
| `x10s` | ABLATION | FREE_SURFACE_KINETICS | Ablation cinématique normale au segment | Ablation rejetée/OFF; incompatible avec le vrai Q2 de production |
| `x10t` | ABLATION | FREE_SURFACE_KINETICS | Ablation cinématique tangentielle rigide | Ablation rejetée : impulse parasite aggravée; OFF production |
| `x10u` | CODE | FREE_SURFACE_KINETICS | Relocalisation conservative one-for-one | Actif dans la chaîne liquide qualifiée; requiert Q2 et x10p |
| `x10v` | CODE | FREE_SURFACE_KINETICS | Swap local full-vector one-for-one | Actif dans la chaîne liquide qualifiée; utilise un byte/particule et deux kernels conditionnels |
| `x10w` | CODE | FREE_SURFACE_KINETICS | Limiter thermique local pairwise | Implémenté mais OFF production; exclusif avec x12a dans le snapshot audité |
| `x10x` | QUALIFICATION | FREE_SURFACE_KINETICS | Qualification de l’enveloppe thermique en C et sigma | Outil de qualification/campagne; aucun nouveau mode C++ |
| `x10y` | QUALIFICATION | FREE_SURFACE_KINETICS | Analyse loi taille-température de l’enveloppe | Analyse scripts-only; aucun nouveau mode C++ |

## x11 : validation quantitative capillaire

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x11a` | QUALIFICATION | SURFACE_TENSION | Qualification Young–Laplace quantitative | Qualification historique quantitative; base de la calibration mécanique x12yl |
| `x11b` | QUALIFICATION | SURFACE_TENSION | Qualification de dispersion des ondes capillaires | Qualification dynamique historique; base méthodologique du calibrateur x12cal |
| `x11c` | DIAGNOSTIC | SURFACE_TENSION | Correction de protocole capillaire et baseline sigma=0 | Correction analyse/protocole et support observation-only; aucune nouvelle physique capillaire |

## x12 : refroidissement local, benchmarks et calibrateurs

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x12a` | CODE | FREE_SURFACE_KINETICS | Refroidissement thermique local des petites structures | Actif dans la chaîne liquide qualifiée; exclusif avec le limiter x10w |
| `x12b` | BENCHMARK | FREE_SURFACE_KINETICS | Prototype JFM D=320h sur obstacle Darcy/chi | Benchmark exploratoire de construction; pas encore une reproduction quantitative JFM 524 |
| `x12c` | BENCHMARK | FREE_SURFACE_KINETICS | Benchmark JFM compact-Y à physique inchangée | Étape de production/compaction du benchmark; physique identique à x12b |
| `x12cal` | CALIBRATOR | SURFACE_TENSION | Calibrateur dynamique de tension superficielle | Calibrateur dynamique courant; aucune nouvelle physique C++ |
| `x12d` | BENCHMARK | FREE_SURFACE_KINETICS | Cas de mesure JFM 524 à géométrie/We/Fr ciblés | Benchmark applicatif de mesure; géométrie/We/Fr ciblés mais Re numérique ~649 au lieu de Re expérimental 12200 |
| `x12yl` | CALIBRATOR | SURFACE_TENSION | Calibrateur mécanique/statique de tension superficielle | Calibrateur mécanique/statique courant; remplace x11a comme extraction scalaire de sigma_eff |

## x13 : propriétés de transport, fluide de référence et campagne Taylor-Culick

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x13a` | CALIBRATOR | TRANSPORT_SURFACE | Pré-balayage intrinsèque SRC haut-Re | Pré-balayage constitutif scripts-only; aucune physique solveur nouvelle |
| `x13b` | DIAGNOSTIC | TRANSPORT_SURFACE | Carte constitutive SRC H/C | Métrologie constitutive scripts-only; aucune modification src/include |
| `x13c` | QUALIFICATION | TRANSPORT_SURFACE | Qualification statistique du transport et choix gamma | Qualification constitutive multi-graines; gamma=8 retenu comme compromis coût/transport |
| `x13d` | CALIBRATOR | TRANSPORT_SURFACE | Follow-up longue longueur d’onde et amortissement | Calibration constitutive du point G08 de référence |
| `x13e` | QUALIFICATION | TRANSPORT_SURFACE | Qualification de portée Mach du point G08 | Qualification compressible scripts-only; aucune modification src/include |
| `x13f` | CALIBRATOR | TRANSPORT_SURFACE | Optimisation locale du transport G08 | Optimisation/calibration du fluide, pas optimisation de code |
| `x13g` | QUALIFICATION | TRANSPORT_SURFACE | Qualification de reproductibilité statistique GPU | Règle méthodologique de reproductibilité; aucune modification solveur |
| `x13h` | QUALIFICATION | TRANSPORT_SURFACE | Point liquide de référence G08-120-L072 | Référence liquide qualifiée; rollback final vers le tag surf-tension-qualified-x13h-20260831 |
| `x13h-A` | QUALIFICATION | TRANSPORT_SURFACE | Acoustique du point final lambda/h=0.72 | Sous-qualification constitutive A du fluide final |
| `x13h-B` | QUALIFICATION | TRANSPORT_SURFACE | Viscosité et dépendance en densité du point final | Sous-qualification constitutive B du fluide final |
| `x13h-C` | QUALIFICATION | TRANSPORT_SURFACE | Enveloppe Mach du point final | Sous-qualification constitutive C du fluide final |
| `x13i` | CALIBRATOR | TRANSPORT_SURFACE | Loi d’échelle en kBT du fluide x13h | Calibration de similitude thermique du fluide x13h; scripts-only |
| `x13j` | CALIBRATOR | TRANSPORT_SURFACE | Calibrateur transport autonome + qualification Young–Laplace x13h | Double rôle historique documenté; aucune nouvelle physique C++ |
| `x13k` | QUALIFICATION | TRANSPORT_SURFACE | Qualification goutte oscillante n=2 | Qualification dynamique historique du point surface libre |
| `x13l` | QUALIFICATION | TRANSPORT_SURFACE | Qualification goutte oscillante n=3 | Qualification dynamique historique |
| `x13m` | QUALIFICATION | TRANSPORT_SURFACE | Qualification goutte oscillante n=4 | Qualification dynamique historique |
| `x13n` | BENCHMARK | TRANSPORT_SURFACE | Benchmark Taylor–Culick 2-D | Limite dynamique connue; référence de rollback G_TC≈0.795 à sigma=10000 |
| `x13o` | ABLATION | TRANSPORT_SURFACE | Ablation swap normal-only | Ablation OFF production; le tag qualifié utilise le swap full-vector x10v |
| `x13p` | ABLATION | TRANSPORT_SURFACE | Zone de crossing libre autour de l’interface | Expérience post-x13n; amélioration TC partielle mais non retenue |
| `x13q` | ABLATION | TRANSPORT_SURFACE | Turnover des orphelins de fermeture cinétique | Expérience de confinement post-x13n; absente du commit qualifié 7655b81 |
| `x13r` | ABLATION | TRANSPORT_SURFACE | Refroidissement direct des cellules interfaciales | Rejetée: fermeture discontinue et dépendante du masque; supersédée par x13t |
| `x13s` | ABLATION | TRANSPORT_SURFACE | Refroidissement interfacial anisotrope | Rejetée comme fermeture générale; supersédée par x13t |
| `x13t` | ABLATION | TRANSPORT_SURFACE | Refroidissement progressif unifié | Expérience causale rejetée comme chemin général après x13zd |
| `x13u` | ABLATION | TRANSPORT_SURFACE | Combinaison x13t + relocalisation one-for-one | Expérimental/rejeté; x13u fixe la combinaison mais pas la fermeture générale |
| `x13v` | ABLATION | TRANSPORT_SURFACE | Séparation position one-for-one / swap vitesse | Expérimental/rejeté; outil causal de séparation de x10u et x10v |
| `x13w` | ABLATION | TRANSPORT_SURFACE | Escape → inactive → reseed local | Rejeté: contraction artificielle du support de phase |
| `x13w-fix3` | FIX | TRANSPORT_SURFACE | Reseed sur moyenne pré-échappement | Correctif utilisé dans x13zd; mécanisme x13w reste invalidé physiquement |
| `x13x` | ABLATION | TRANSPORT_SURFACE | Sweep de rétention probabiliste | Aucun compromis robuste vitesse/confinement; non production |
| `x13z` | BENCHMARK | TRANSPORT_SURFACE | Exploration de changements de grille | Gains séduisants mais non suffisants pour validation |
| `x13za` | DIAGNOSTIC | TRANSPORT_SURFACE | Comparaison gouttes oscillantes entre grilles | Diagnostic de dépendance de grille de la dynamique capillaire |
| `x13zb` | DIAGNOSTIC | TRANSPORT_SURFACE | Comparaison Young–Laplace entre grilles | Diagnostic; la régression brute forte-sigma n’est pas une mesure physique robuste de sigma_eff |
| `x13zb2` | DIAGNOSTIC | TRANSPORT_SURFACE | Baseline sigma=0 courte pour comparaison de grille | Essai de protocole; ne ferme pas le biais de baseline |
| `x13zb3` | DIAGNOSTIC | TRANSPORT_SURFACE | Audit de stabilité et rebaseline Young–Laplace | Diagnostic de baseline; motive l’abandon de la référence libre longue sigma=0 |
| `x13zc` | DIAGNOSTIC | TRANSPORT_SURFACE | Mécanique statique de goutte versus grille | Diagnostic de représentation; R_eff plus petit sur grille fine explique une part majeure du shift fréquentiel |
| `x13zd` | QUALIFICATION | TRANSPORT_SURFACE | Validation croisée décisive et rollback | Invalide x13t+x13w comme chemin général; point de production ramené à surf-tension-qualified-x13h-20260831 |

## x13ze post-rollback/run_ok

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x13ze` | DEMONSTRATION | FREE_SURFACE_KINETICS | Démonstrations run_ok impact/puddle stabilisées | Démonstration historique stabilisée; pas une nouvelle qualification physique |
| `x13zf` | DEMONSTRATION | FREE_SURFACE_KINETICS | Démonstration run_ok dripping qualitative | Démonstration qualitative historique stabilisée; non benchmark quantitatif |
| `x13zg` | TOOLING | FREE_SURFACE_KINETICS | Profil run_ok surface libre qualifié | Profil run_ok de référence; chaîne x13h explicitement figée |
| `x13zj` | TOOLING | RUN_OK | Harmonisation fluide de référence et LiveVis run_ok | Harmonisation documentaire/outillage historique attestée par README Git |
| `x13zk` | TOOLING | RUN_OK | Checker run_ok à sémantique physique | Contrôle sémantique run_ok; aucune nouvelle physique |
| `x13zl` | TOOLING | RUN_OK | Collection run_ok canonique homogène | Collection run_ok homogénéisée |
| `x13zn` | FIX | RUN_OK | Nettoyage runner injection | Correctif runner-only attesté; aucune modification solveur |

## x14 thermostat multi-espèces

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x14a` | QUALIFICATION | LIQUID_GAS | Smoke thermostat deux types | PASS des smokes thermostat deux types |
| `x14b` | QUALIFICATION | LIQUID_GAS | Qualification thermostat avec collision SRC active | PASS active-collision exact-grid |
| `x14c` | QUALIFICATION | LIQUID_GAS | Probe thermostat en grille décalée | PASS production-like shifted-grid probe |
| `x14e` | QUALIFICATION | LIQUID_GAS | Qualification thermostat sur chemin SRC de production | PASS chemin SRC production résident |
| `x14f` | QUALIFICATION | LIQUID_GAS | Qualification exacte thermostat sur src-q6-g-f | PASS x14f-fix1 exact src-q6-g-f |
| `x14i` | QUALIFICATION | LIQUID_GAS | Qualification finale thermostat src-q6-g-f avec grid shift | PASS production shifted-grid resident species thermostat |

## x14 interaction jet gaz-liquide

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x14an` | CAMPAIGN | LIQUID_GAS | Jet gazeux plan sur bain liquide | Campagne de construction/qualification; aucun PASS physique autonome inféré du runner |
| `x14ao` | CAMPAIGN | LIQUID_GAS | Buse planaire Darcy/chi paramétrable | Étape géométrique de campagne; pas de qualification autonome revendiquée |
| `x14ap` | CAMPAIGN | LIQUID_GAS | Buse Darcy/chi aux défauts de similitude expérimentale | Point de similitude de campagne; pas de PASS autonome |
| `x14aq` | CAMPAIGN | LIQUID_GAS | Réservoirs gazeux ambiants latéraux | Expérience de condition limite; non retenue comme validation autonome |
| `x14ar` | CAMPAIGN | LIQUID_GAS | Atmosphère hard-density sur le dessus hors buse | Expérience de condition limite; pas de PASS physique autonome |
| `x14as` | CAMPAIGN | LIQUID_GAS | Buse à sorties larges, pression gaz comme covariable | Topologie retenue pour x14at; pression gaz traitée comme covariable mesurée |
| `x14at` | QUALIFICATION | LIQUID_GAS | Validation externe Sato Stage-A | Validation externe ciblée: H/D=0.8 et Fr_m≈0.49–0.59 à 4.8–9.9% de Sato; H/D=1.7 REVIEW; pas de similitude dynamique complète |
| `x14au` | CALIBRATOR | LIQUID_GAS | Qualification viscosité associée au cas Sato | Liquide primaire INVALID; gaz REVIEW; cohérence d’échelle 2σ diagnostique seulement |
| `x14av` | DEMONSTRATION | LIQUID_GAS | Démonstration atomiseur air-assisté | DEMONSTRATION_DIAGNOSTIC_ONLY; aucune qualification physique d’atomisation |

## x2-x4b : diagnostic gravitaire et séquençage Q6-g force-aware

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x2` | DIAGNOSTIC | Q6_GF | Diagnostic liquide plein : force appliquée avant une projection Q6 trop tardive | Diagnostic causal; mène directement à x3 |
| `x3` | CODE | Q6_GF | Q6-g force-aware — preuve de concept prestream à deux solves | Preuve de concept validant la cause; supplantée par x4a |
| `x4a` | CODE | Q6_GF | Q6-g prestream_single — un solve Q6 par pas forcé | Référence mono-solve; supplantée par la fusion x4b |
| `x4b` | PERF | Q6_GF | Q6-g prestream_single_fused — fusion CUDA force + projection | Séquençage temporel Q6-g de référence pour la suite de 0493x |

## x5a-x5b : surface libre masquée, dam-break vide et gaz explicite

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x5a` | CODE | Q6_GF | Q6-g free_surface_masked — premier liquide partiellement rempli | Première fermeture liquide-vide; support numérique encore assimilé à l'interface |
| `x5a2` | QUALIFICATION | Q6_GF | Qualification dam-break liquide-vide du free_surface_masked | Qualification discriminante; motive la séparation support/interface de x6 |
| `x5b` | QUALIFICATION | Q6_GF | Qualification liquide-gaz : Q6-g liquide et gaz compressible explicite | Première qualification bi-espèces; couplage gaz-liquide encore collisionnel côté pression |

## x6a-x6g : séparation support/interface et pression gazeuse

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x6a` | DIAGNOSTIC | Q6_GF | Diagnostic EOS de pression gazeuse interfaciale | Diagnostic EOS préparatoire; aucune rétroaction sur le solveur |
| `x6b` | DIAGNOSTIC | Q6_GF | Diagnostic géométrique support Q6 / interface alpha=0.5 | Diagnostic géométrique; prépare la matérialisation résidente x6c |
| `x6c` | INFRA | Q6_GF | Infrastructure résidente du champ de phase alpha | Infrastructure géométrique résidente; base des stencils d'interface ultérieurs |
| `x6d` | CODE | Q6_GF | Expérience cut-face 1/theta sur le bord du carrier | Expérience active historique; architecture abandonnée au profit de x6f |
| `x6e` | DIAGNOSTIC | Q6_GF | Audit topologique de l'interface physique alpha=0.5 | Diagnostic architectural décisif; motive pressureMask séparé de x6f |
| `x6f` | CODE | Q6_GF | Stencil résident de pression sur l'interface physique alpha=0.5 | Architecture d'interface retenue; géométrie bornée par x6f2 avant x6g |
| `x6f2` | FIX | Q6_GF | Correction : géométrie de phase bornée avant filtrage | Correctif géométrique actif de la chaîne x6f/x6g |
| `x6g` | CODE | Q6_GF | Condition de pression gazeuse sur l'interface physique | Couplage pression gaz actif sur interface résidente; base du futur terme capillaire |

## x6h : cohérence correction de face -> particules

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x6h-A` | FIX | Q6_GF | Correctif des corrections de faces physiques basses | Correctif de reconstruction des faces basses actif dans Q6-g-f |
| `x6h-B0` | DIAGNOSTIC | Q6_GF | Diagnostic régional de divergence après application aux particules | Diagnostic sparse OFF en production; motive la reconstruction B1 |
| `x6h-B1` | CODE | Q6_GF | Reconstruction affine RT0/MAC des corrections face-vers-particule | Reconstruction face-particule active dans le profil Q6-g-f qualifié |

## x7a-x7e : restauration de densité dans Q6-g-f

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x7a` | CODE | Q6_GF | Kick viriel de densité CUDA résident | Expérience de restauration explicite; abandonnée au profit de la cible de divergence x7c/x7d |
| `x7b` | DIAGNOSTIC | Q6_GF | Sémantique continue et diagnostic de grille du viriel | Consolidation sémantique de l'ablation virielle; stratégie ensuite remplacée par x7c |
| `x7c` | CODE | Q6_GF | Restauration de densité intégrée au RHS Q6 | Mécanisme RHS retenu conceptuellement; paramétrage physique raffiné par x7d |
| `x7d` | CODE | Q6_GF | Constante de temps physique de restauration de densité | Paramétrage physique retenu; tau_rho=0.25 dans la chaîne qualifiée |
| `x7e` | QUALIFICATION | Q6_GF | Qualification combinée pression gaz x6g + restauration de densité x7d | Qualification de composition Q6-g-f; kick viriel explicite désactivé |

## x7d-v2-x7q : restauration signée, symétrie et fermeture de moment Q6-g-f

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x7d-v2` | CODE | Q6_GF | Gate cohérent de compression pour la restauration de densité | Actif dans le profil Q6-g-f qualifié; gate désactivé = comportement x7d historique |
| `x7d-v2-fix2` | FIX | Q6_GF | Première fermeture du moment périodique B1 au niveau cellule | Correctif intermédiaire actif historiquement; fermeture k=0 centrée cellule ensuite rendue exacte au niveau particulaire par x7q |
| `x7d-v2-signed1` | CODE | Q6_GF | Restauration de densité signée à gates cohérents | Actif dans le profil final signé; qualifié avec la chaîne x7q |
| `x7o` | CODE | Q6_GF | Symétrisation par réflexion du Q6 independent_masked | Actif; corrige le biais est/nord du fullDomain independent_masked |
| `x7p` | CODE | Q6_GF | Symétrisation par réflexion du Q6 commun | Actif; enlève l'orientation backward-difference historique du Q6 commun |
| `x7q` | CODE | Q6_GF | Fermeture exacte du moment périodique au niveau particulaire B1/RT0 | Actif automatiquement pour B1 + fullDomain + direction périodique; chemin partiel/dam-break historique inchangé |

## x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x7f` | CODE | Q6_GF | Extension Q6-g-f aux familles statiques multi-BC | Actif sur les familles statiques qualifiées; Darcy encore exclu à cette étape |
| `x7f-fix2` | FIX | Q6_GF | Correctif de garde wall-simple pour canal mixte | Correctif actif du périmètre x7f |
| `x7g` | CODE | Q6_GF | Darcy-Brinkman placé avant la projection Q6-g-f | Actif sur le sous-ensemble Darcy/chi qualifié |
| `x7h` | INFRA | Q6_GF | Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f | Infrastructure de démonstration et régression |
| `x7i` | BENCHMARK | Q6_GF | Benchmark physique multi-cas SRC / Q6 / Q6-g-f | Benchmark diagnostique de référence; sans seuil PASS/FAIL arbitraire |
| `x7j` | PERF | Q6_GF | CG Q6-g-f entièrement CUDA résident | Optimisation majeure du solve Q6-g-f; fallback hôte conservé |
| `x7k` | PERF | Q6_GF | Stripping des diagnostics Q6-g-f en production | Optimisation de télémétrie active en production |
| `x7l` | PERF | Q6_GF | Stripping de la télémétrie thermostat/espèces | Optimisation de télémétrie active; thermostat physique inchangé |
| `x7m` | CODE | Q6_GF | Garde topologique monophase par registre de phases | Étape initiale; complétée par x7m-fix1 |
| `x7m-fix1` | FIX | Q6_GF | Domaine de pression monophase persistant | Correctif structurel actif du chemin monophase |
| `x7n` | DIAGNOSTIC | Q6_GF | Calibrateur de fluide sélectionnable par chemin et diagnostic compression/bruit | Diagnostic/calibrateur de chemin; précède les corrections x7d-v2 et la qualification x7q |

## x8a-x8j : diagnostic, qualification et premier VK ouvert

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x8a` | DIAGNOSTIC | Q6_GF | Diagnostic exact du moment Darcy | Diagnostic opt-in; OFF en production |
| `x8b` | ANALYZER | Q6_GF | Attribution temporelle Darcy / résidu non-Darcy | Analyseur hors ligne; aucune modification du solveur |
| `x8c` | DIAGNOSTIC | Q6_GF | Localisation temporaire du moment par étapes | Instrumentation temporaire retirée après campagne; preuve historique conservée |
| `x8d` | QUALIFICATION | Q6_GF | Qualification indépendante Q6-g-f par Poiseuille et Brinkman | Qualification analytique du chemin Q6-g-f; aucun changement C++/CUDA |
| `x8e` | CALIBRATOR | Q6_GF | Recalibration viscosité Q6-g-f et raideur Darcy | Calibration Q6-g-f et carte de raideur Darcy; aucun changement du solveur |
| `x8f` | BENCHMARK | OPEN_BOUNDARY | Premier candidat von Karman Q6-g-f à inlet/outlet ouverts | Premier candidat VK ouvert; runner-only, ensuite prolongé/raffiné |
| `x8g` | QUALIFICATION | OPEN_BOUNDARY | Qualification full-face et bilan de masse du VK | Qualification full-face/mass-balance du candidat VK; runner-only |
| `x8h` | INFRA | OPEN_BOUNDARY | Restart hydrodynamique pour les longs runs VK | Infrastructure de continuation hydrodynamique; RNG non bitwise continu |
| `x8i` | ANALYZER | OPEN_BOUNDARY | Analyse du sillage VK établi par POD et sondes | Analyseur du sillage établi; aucune modification du solveur |
| `x8j` | ANALYZER | OPEN_BOUNDARY | Nondimensionnalisation VK et comparaison bibliographique | Analyse bibliographique/nondimensionnelle; enrichie plus tard par les diagnostics de flux x8n |

## x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x8k` | CODE | OPEN_BOUNDARY | Inlet segmenté à profil de Poiseuille local | Actif; sémantique de profil local retenue dans le benchmark Zovatto |
| `x8l` | CODE | OPEN_BOUNDARY | Première extrapolation Neumann passive de la vitesse de sortie | Étape intermédiaire conservée : extrapolation de vitesse retenue comme base par x8r, mais sémantique de projection x8l seule supersédée |
| `x8m` | BENCHMARK | OPEN_BOUNDARY | Benchmark de production Zovatto-Pedrizzetti Re_H=280 | Benchmark de production/restart Zovatto; première lignée sous x8l, ensuite réalignée sur la fermeture x8t |
| `x8n` | ANALYZER | OPEN_BOUNDARY | Diagnostic de conservation amont du débit et du flux massique | Diagnostic hors ligne du conditionnement et de la conservation amont; aucune modification du solveur |
| `x8q` | CODE | OPEN_BOUNDARY | Continuation cinétique locale de l'outlet Neumann | Actif pour outlet Neumann; forme finale local-bath après les sous-révisions x8q-fix1..fix4 |
| `x8r` | CODE | OPEN_BOUNDARY | Outlet de pression Neumann Q6-g-f | Actif; sémantique pression passive du mode openBoundaryOutletMode=neumann |
| `x8s` | PERF | OPEN_BOUNDARY | Déflation exacte des modes longitudinaux lents du CG | Actif uniquement dans la géométrie x8r pleine hauteur applicable; physique inchangée |
| `x8t` | CODE | OPEN_BOUNDARY | Cible de relaxation de densité sans mode moyen à outlet pression | Actif dans le couplage fullDomain + x8r + relaxation densité; autres topologies inchangées |

## x8 : conditions limites ouvertes et benchmark von Karman

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x8u` | INFRA | OPEN_BOUNDARY | Réalignement du runner Zovatto sur la fermeture x8t | Réintégration production de la fermeture x8t dans la lignée x8m; clôture documentaire du cycle x8 |

## x9 : tension superficielle, courbure et mouillage

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x9a` | DIAGNOSTIC | SURFACE_TENSION | Premier scaffold passif de courbure résident | Scaffold passif historique; géométrie seulement, sans tension superficielle active |
| `x9b` | DIAGNOSTIC | SURFACE_TENSION | Courbure passive binomiale + Scharr et LiveVis résident | Estimateur passif p1 conservé comme baseline; aucune physique capillaire active |
| `x9c` | QUALIFICATION | SURFACE_TENSION | Qualification du support de lissage de courbure | Qualification passive; sélectionne p3 pour la courbure de production, sans déplacer l'interface x6c |
| `x9d` | CODE | SURFACE_TENSION | Premier saut de Laplace actif dans Q6-g-f | Coeur actif de la capillarité bulk; sigma=0 est un no-op exact |
| `x9e` | DIAGNOSTIC | SURFACE_TENSION | Qualification diagnostique de goutte statique | Diagnostic/qualification au-dessus de x9d; physique inchangée |
| `x9f` | DIAGNOSTIC | SURFACE_TENSION | Diagnostic de bande interfaciale vraie et relaxation elliptique | Diagnostic de forme/relaxation au-dessus de x9e; aucune modification de la capillarité |
| `x9g` | CODE | SURFACE_TENSION | Généralisation de l'interface aux paires de phases A/B | Actif; abstraction de paire sans prétendre fournir un solveur immiscible symétrique général |
| `x9h` | CODE | SURFACE_TENSION | Provider géométrique résident de paroi | Géométrie-only qualifiée; capillarité/mouillage avec B=wall encore interdits à cette étape |
| `x9i` | CODE | SURFACE_TENSION | Première fermeture d'angle de contact par normale imposée | Prototype historique : angle local exact mais biais de div(n)/courbure; conservé comme baseline derrière un gate de test |
| `x9j` | CODE | SURFACE_TENSION | Fermeture d'angle par ghost-alpha de courbure | Prototype historique supplanté : améliore certains angles mais ne préserve pas suffisamment la géométrie multi-couche |
| `x9k` | CODE | SURFACE_TENSION | Ghost-alpha par miroir cisaillé | Prototype historique supplanté : angle robuste mais une transformation affine ne préserve pas un cercle, donc biais de courbure angle-dépendant |
| `x9l` | CODE | SURFACE_TENSION | Reconstruction de normale au mur-face | Expérience négative hors voisinage de 90 degrés; gardée comme comparaison et supplantée par x9m |
| `x9m` | CODE | SURFACE_TENSION | Fermeture statique de mouillage par ancre hors support | Fermeture statique préférée du cycle x9; robuste géométriquement, mais dynamique de ligne triple non universellement fermée |
| `x9n` | QUALIFICATION | SURFACE_TENSION | Qualification géométrique étendue de x9m | Qualification scripts-only de la robustesse géométrique statique x9m |
| `x9o` | QUALIFICATION | SURFACE_TENSION | Qualification de phase sous-maille tangentielle de x9m | Qualification scripts-only; quantifie la sensibilité résiduelle de x9m à la phase sous-maille |
| `x9p` | QUALIFICATION | SURFACE_TENSION | Qualification dynamique de goutte sessile x9m | Résultat dynamique partiel : sens mouillage/démouillage correct, mais équilibre comprimé vers 90 degrés et courbure de ligne triple encore bruitée |
| `x9q` | BENCHMARK | SURFACE_TENSION | Test de potentialité jet gravitaire / pincement / impact | Benchmark exploratoire sans seuil physique dur; démontre des changements de topologie et expose la faiblesse de courbure sous-résolue traitée par x9r |
| `x9r` | FIX | SURFACE_TENSION | Cutoff de résolution du saut capillaire | Correctif actif de courbure sous-résolue; seuil à choisir selon résolution/campagne, non constante physique universelle |
| `x9s` | BENCHMARK | SURFACE_TENSION | Benchmark paramétrable d'impact et splash | Démonstration/qualification morphologique qualitative; pas une mesure convergée de Weber critique |

## x9 : tension superficielle, courbure, mouillage et prélude cinétique

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x9t` | CODE | FREE_SURFACE_KINETICS | Première rétention cinétique liquide-vide conservative | Prototype actif de rétention cinétique; première étape du pont x9 vers la fermeture de surface libre x10 |
| `x9u` | CODE | FREE_SURFACE_KINETICS | Extension de la réflexion aux sorties de support | Étape active intermédiaire; couverture support-edge améliorée mais le choix de bain sera corrigé par x9w |
| `x9v` | DIAGNOSTIC | FREE_SURFACE_KINETICS | Diagnostic des voies de fuite de la fermeture x9u | Diagnostic passif; aucune nouvelle passe particulaire ni modification de physique |
| `x9w` | FIX | FREE_SURFACE_KINETICS | Bain de recul strictement bulk | Correctif actif de sélection du bain; recherche bornée à deux cellules et conservation P/K maintenue |
| `x9x` | CODE | FREE_SURFACE_KINETICS | Réflexion au crossing physique prédit | Étape active intermédiaire : déclenchement géométrique au crossing physique, sans nouvelle passe globale |
| `x9y` | FIX | FREE_SURFACE_KINETICS | Côté alpha pointwise et crossing par bissection bornée | Correctif géométrique actif de x9x; supprime l'aliasing centre-cellule sans buffer ou passe globale supplémentaire |
| `x9z` | CODE | FREE_SURFACE_KINETICS | Réflexion individuelle des donneurs et compensation affine du bain | Dernière étape x9 du mécanisme de rétention; loi individuelle explicitement réutilisée ensuite par x10a |

## Post-x14 / conditions limites ouvertes

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0414` | CODE | OPEN_BOUNDARY | Extension quadriface des open boundaries segmentées | QUALIFIED |

## 0490 : resampling conservatif multi-espèces et chemin CUDA résident

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0490A` | INFRA | MULTISPECIES_RESAMPLING | Registre des espèces | Jalon historique documenté |
| `0490B` | CODE | MULTISPECIES_RESAMPLING | Dépôt cellule–espèce | Jalon historique documenté |
| `0490C` | CODE | MULTISPECIES_RESAMPLING | Resampling conservatif par espèce | Jalon historique documenté |
| `0490D` | CODE | MULTISPECIES_RESAMPLING | Fermeture de masse sensible à la phase | Jalon historique documenté |
| `0490E` | CODE | MULTISPECIES_RESAMPLING | Garde de population par espèce | Jalon historique documenté |
| `0490F` | CODE | MULTISPECIES_RESAMPLING | Refill d'espèces mixtes | Jalon historique documenté |
| `0490G` | CODE | MULTISPECIES_RESAMPLING | Transferts donneur–receveur par espèce | Jalon historique documenté |
| `0490H` | CODE | MULTISPECIES_RESAMPLING | Dépôt cellule–espèce CUDA | Jalon historique documenté |
| `0490I` | CODE | MULTISPECIES_RESAMPLING | Fermeture de masse multi-espèces CUDA | Jalon historique documenté |
| `0490J` | CODE | MULTISPECIES_RESAMPLING | Garde de population multi-espèces CUDA | Jalon historique documenté |
| `0490K` | CODE | MULTISPECIES_RESAMPLING | Plan de transferts multi-espèces CUDA | Jalon historique documenté |
| `0490L` | QUALIFICATION | MULTISPECIES_RESAMPLING | Validation du resampling résident multi-espèces | Qualification historique |
| `0490M` | PERF | MULTISPECIES_RESAMPLING | Chemin rapide résident multi-espèces | Optimisation historique |
| `0490M-fix2` | FIX | MULTISPECIES_RESAMPLING | Fermeture conservative multi-espèces | Correctif historique |
| `0490N` | CODE | MULTISPECIES_RESAMPLING | Maintenance résidente multi-espèces | Jalon historique documenté |
| `0490N-fix1` | DIAGNOSTIC | MULTISPECIES_RESAMPLING | Télémétrie résidente par espèce | Diagnostic historique |
| `0490N-fix2` | FIX | MULTISPECIES_RESAMPLING | Matérialisation des transferts multiples | Correctif historique |
| `0490P` | PERF | MULTISPECIES_RESAMPLING | Politique cellule sur device / zéro CPU | Architecture historique |

## 0491 : Q6 multi-espèces — contrat, intégration CUDA et qualification

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0491A` | INFRA | SPECIES_Q6 | Contrat Q6 sensible à l'espèce | Jalon historique documenté |
| `0491B` | CODE | SPECIES_Q6 | Dépôt partagé et shadow CUDA species-Q6 | Jalon historique attesté par documentation technique |
| `0491C` | CODE | SPECIES_Q6 | Application CUDA opt-in du Q6 par espèce | Jalon historique attesté par documentation technique |
| `0491D` | QUALIFICATION | SPECIES_Q6 | Matrice des chemins species-Q6 | Qualification historique |
| `0491E` | QUALIFICATION | SPECIES_Q6 | Audit strict du Q6 résident par espèce | Qualification historique |
| `0491F` | QUALIFICATION | SPECIES_Q6 | Validation énergie et thermostat du species-Q6 | Qualification historique |
| `0491G` | QUALIFICATION | SPECIES_Q6 | Qualification frontières ouvertes et Darcy du species-Q6 | Qualification historique |
| `0491H` | QUALIFICATION | SPECIES_Q6 | Campagne consolidée de validation species-Q6 | Qualification historique consolidée |
| `0491H-fix1` | FIX | SPECIES_Q6 | Correctif final et qualification approfondie species-Q6 | Correctif historique qualifié |

## 0492 : refresh des run_ok et validation sémantique multi-espèces

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0492` | INFRA | RUN_OK_INFRA | Refresh et contrat des run_ok | Infrastructure runner historique qualifiée |

## 0493 : resampling multi-espèces résident — universalisation, performance et qualification physique

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0493A` | INFRA | MULTISPECIES_RESAMPLING | Routage universel du resampling multi-espèces résident | Jalon historique documenté |
| `0493B` | CODE | MULTISPECIES_RESAMPLING | Resampling CUDA résident activable par espèce | Jalon historique documenté |
| `0493C` | QUALIFICATION | MULTISPECIES_RESAMPLING | Qualification du resampling multi-espèces résident | Qualification historique |
| `0493C-fix3` | FIX | MULTISPECIES_RESAMPLING | Alignement du population guard medium sur gamma | Correctif historique attesté par Git |
| `0493D` | PERF | MULTISPECIES_RESAMPLING | Sélection parallèle déterministe des transferts résidents | Jalon d'optimisation attesté par le code |
| `0493D-fix1` | FIX | MULTISPECIES_RESAMPLING | Rejeu déterministe du state-update après sélection parallèle | Correctif historique attesté par Git |
| `0493E` | QUALIFICATION | MULTISPECIES_RESAMPLING | Qualification physique mono-espèce du resampling | Qualification physique historique |
| `0493F` | QUALIFICATION | MULTISPECIES_RESAMPLING | Qualification physique à deux espèces du resampling | Qualification physique historique |
| `0493F-fix2` | FIX | MULTISPECIES_RESAMPLING | Cas deux-espèces physiquement neutre | Correctif de qualification historique |
| `0493G` | CODE | MULTISPECIES_RESAMPLING | Restauration locale des moments par espèce | Correction physique historique |
| `0493H` | QUALIFICATION | MULTISPECIES_RESAMPLING | Diagnostic physique par onde de cisaillement périodique | Diagnostic physique historique |
| `0493I` | FIX | MULTISPECIES_RESAMPLING | Fermeture conservative mono-espèce sur le chemin résident | Correctif physique attesté par le code |
| `0493J` | CODE | MULTISPECIES_RESAMPLING | Fermeture conservative de l'énergie cinétique par espèce | Jalon historique documenté |

## 0493o : références SRC et réparation locale du support

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0493O0` | BENCHMARK | MULTISPECIES_RESAMPLING | Références SRC seules avant réparation locale du support | Référence historique pré-réparation |
| `0493O1` | CODE | MULTISPECIES_RESAMPLING | Population effective cible : split local piloté par Neff | Jalon historique documenté |
| `0493O1-fix2` | FIX | MULTISPECIES_RESAMPLING | Autorité CUDA du split-only local | Correctif de sûreté résident attesté par le code |
| `0493O2-fix1` | FIX | MULTISPECIES_RESAMPLING | Runner TG mono/dual-espèces pour la réparation de support | Sous-jalon historique explicitement attesté |
| `0493O3` | PERF | MULTISPECIES_RESAMPLING | Early-exit résident lorsqu'aucune paire cellule/espèce n'est pauvre | Optimisation résidente historique |
| `0493O4` | QUALIFICATION | MULTISPECIES_RESAMPLING | Qualification de la réparation de support en segmented-Darcy | Qualification historique |

## 0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0493W0` | BENCHMARK | SRC_CALIBRATION | Audit du régime cinétique du cas segmented-Darcy | Diagnostic historique du régime cinétique |
| `0493W1` | CALIBRATOR | SRC_CALIBRATION | Calibrateur constitutif du fluide SRC | Calibrateur historique |
| `0493W2` | BENCHMARK | SRC_CALIBRATION | Référence segmented-Darcy sur fluide SRC calibré | Référence physique calibrée |
| `0493W3` | FIX | BOUNDARY | Correction de l'injection sur cellule partielle d'une entrée segmentée | Correctif historique attesté par Git |
| `0493W4` | RUNNER | MULTISPECIES_RUNNER | Runner d'injection multi-espèces normalisé par famille de phase | Jalon de runner attesté par le code et les inventaires |
| `0493W5` | CODE | SPECIES_Q6 | Q6 multi-espèces independent_masked — étape périodique | Jalon historique documenté |
| `0493W6` | DIAGNOSTIC | SPECIES_Q6 | Diagnostic de divergence après application du Q6 masqué | Diagnostic historique documenté |
| `0493W7` | CODE | SPECIES_Q6 | Q6 independent_masked sur toutes les familles de frontières résidentes | Jalon historique documenté et qualifié |
| `0493W8` | QUALIFICATION | SPECIES_Q6 | Équivalence Taylor--Green mono / dual-identique du Q6 independent_masked | Qualification historique consolidée |

## Fiches détaillées

### `SRC/MPCD` — Collision particulaire SRC/MPCD

- **Clé unique :** `reference:SRC/MPCD`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** Socle actif
- **Confiance :** `B`

Streaming des particules, collision stochastique par cellule, rotation SRD, grid shift et thermostat. C'est le fluide mésoscopique de base.

### `Q6` — Projection quasi-incompressible

- **Clé unique :** `reference:Q6`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** Socle actif selon RUN_MODE
- **Confiance :** `B`

Projection du champ de vitesse/moment pour réduire la divergence. Les variantes récentes opèrent sur GPU résident.

### `Q9` — Relaxation basse fréquence du flux de masse

- **Clé unique :** `reference:Q9`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** Historique / séparée du chemin Q6-g-f actuel
- **Confiance :** `B`

Ancienne projection complémentaire du flux de masse à grande longueur d'onde.

### `Resampling` — Contrôle du support particulaire

- **Clé unique :** `reference:Resampling`
- **Nature / domaine :** `QUALIFICATION` / `CORE`
- **Statut :** Module séparé, OFF dans les qualifications surface libre récentes
- **Confiance :** `B`

Rééchantillonnage local conservatif pour maintenir population et masse cellulaire; distinct de Q6 et opt-in.

### `Q6 multi-espèces` — Projection sélective par espèce

- **Clé unique :** `reference:Q6 multi-espèces`
- **Nature / domaine :** `INFRA` / `CORE`
- **Statut :** Socle multi-espèces
- **Confiance :** `B`

Registre d'espèces; mode independent_masked pour projeter le liquide sans projeter directement le gaz.

### `Q6-g` — Q6 force-aware

- **Clé unique :** `reference:Q6-g`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** Introduit par x3, base de Q6-g-f
- **Confiance :** `B`

Inclut la force dans la vitesse tentative avant le streaming afin que la projection corrige la vitesse réellement utilisée pour transporter les particules.

### `Q6-g-f` — Q6 force-aware + interface + face-particule + densité

- **Clé unique :** `reference:Q6-g-f`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** Chaîne de projection de référence
- **Confiance :** `B`

Chaîne: vitesse tentative forcée, interface physique alpha=0.5, condition de pression, reconstruction face-particule B1/RT0 et relaxation lente de densité dans le même solveur CG.

### `x14d` — Collision commune + thermostats séparés

- **Clé unique :** `0493x14d`
- **ID canonique :** `0493x14d`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Actif dans x14
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Conserve SRC commun au mélange; seule la remise à température est faite par type.

### `x14g` — Cellules exactes post-stream/grid-shift

- **Clé unique :** `0493x14g`
- **ID canonique :** `0493x14g`
- **Nature / domaine :** `FIX` / `LIQUID_GAS`
- **Statut :** Correctif d'intégration actif
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Utilise les identifiants de cellule SRC persistants exacts pour thermostat par espèce.

### `x14j` — Goutte deux températures

- **Clé unique :** `0493x14j`
- **ID canonique :** `0493x14j`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Benchmark d'intégration
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Cas d'intégration thermostat liquide/gaz avant fermeture cinétique bilatérale.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14j_drop_radial.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14j_drop_two_temperature.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14j_diffuse_drop_two_temperature.sh`

### `x14k` — Géométrie cinétique bilatérale

- **Clé unique :** `0493x14k`
- **ID canonique :** `0493x14k`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Opt-in; change le modèle d'interface
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Autorise le côté gaz à consommer la même géométrie de relocalisation x10 que le liquide, avec sens de phase inversé.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14k_bilateral_x10u_drop.sh`

### `x14l` — Réflexion spéculaire du gaz

- **Clé unique :** `0493x14l`
- **ID canonique :** `0493x14l`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Qualifié pour imperméabilité normale dans cas tests
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Réfléchit la composante normale relative du gaz à l'interface mobile; tangentielle inchangée.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14l_gas_specular_drop.sh`

### `x14m` — Assemblage bilatéral + compatibilité x12a

- **Clé unique :** `0493x14m`
- **ID canonique :** `0493x14m`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Architecture intégrée
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Combine liquide x10/x12, gaz x14l et thermostat séparé; x12a reste côté liquide uniquement.

**Relations :**
- `REFERENCES` → `x12a` — Refroidissement thermique local des petites structures
- `REFERENCES` → `x14l` — Réflexion spéculaire du gaz

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14m_full_liquid_chain_gas_specular_drop.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14m_full_liquid_chain_gas_specular_drop_periodic.sh`

### `x14n` — Ablation fermeture gaz OFF

- **Clé unique :** `0493x14n`
- **ID canonique :** `0493x14n`
- **Nature / domaine :** `ABLATION` / `LIQUID_GAS`
- **Statut :** Ablation
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Coupe la fermeture cinétique gazeuse pour séparer pression et imperméabilité.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14n_fix1_no_kinetic_reflection_drop.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14n_gas_closure_off_drop.sh`

### `x14o` — Ablation pression gaz constante

- **Clé unique :** `0493x14o`
- **ID canonique :** `0493x14o`
- **Nature / domaine :** `ABLATION` / `LIQUID_GAS`
- **Statut :** Ablation
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Utilise une pression gazeuse constante choisie pour annuler la contribution de jauge.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14o_x6g_constant_pressure_ablation_drop.sh`

### `x14r` — Analyse volume accessible

- **Clé unique :** `0493x14r`
- **ID canonique :** `0493x14r`
- **Nature / domaine :** `ANALYZER` / `LIQUID_GAS`
- **Statut :** Diagnostic conduisant à x14s
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Analyse offline montrant que p=N kBT/A_cell sous-estime la pression si seule une fraction de cellule est accessible au gaz.

**Relations :**
- `BUILDS_ON` → `x14q` — Fit offline de fraction de volume accessible
- `REFERENCES` → `x14s` — EOS gaz volume accessible

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14r_accessible_volume_ramp.py`

### `x14s` — EOS gaz volume accessible

- **Clé unique :** `0493x14s`
- **ID canonique :** `0493x14s`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Actif dans x14 récent
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Corrige la pression gazeuse par la fraction de volume accessible dérivée de alpha Q6.

**Relations :**
- `IMPLEMENTS_RESULT_OF` → `x14r` — Analyse volume accessible

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14s_drop_shape_fourier.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14s_drop_shape_fourier.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14s_multiseed6_shape_step1000.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x14s_multiseed6_sigma256.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14s_x6g_accessible_volume_drop.sh`

### `x14t` — Piston pression thermodynamique

- **Clé unique :** `0493x14t`
- **ID canonique :** `0493x14t`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Qualification composante thermodynamique
- **Confiance :** `A`
- **Date :** `2026-09-03`
- **Commit :** `5dd346136d2da9d69952b9cade7ed8eb91a2b93f`

Benchmark plan qui qualifie la transmission moyenne de p_g par x6g/x14s sans terme impulsionnel direct.

**Relations :**
- `REFERENCES` → `x14s` — EOS gaz volume accessible
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14t_normal_pressure_piston.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x14t_normal_pressure_piston.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14t_normal_pressure_piston.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14t_normal_pressure_piston.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14t_normal_pressure_piston.sh`

### `x14u` — Gaz incident normal

- **Clé unique :** `0493x14u`
- **ID canonique :** `0493x14u`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Diagnostic conduisant à x14v
- **Confiance :** `A`
- **Date :** `2026-09-03`
- **Commit :** `5dd346136d2da9d69952b9cade7ed8eb91a2b93f`

Benchmark de flux de moment dirigé; montre que x14l seul rend imperméable mais ne restitue presque pas le moment perdu au liquide.

**Relations :**
- `REFERENCES` → `x14l` — Réflexion spéculaire du gaz
- `REFERENCES` → `x14v` — Kick cinétique excédentaire

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14U_NORMAL_KINETIC_IMPACT.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14u_normal_kinetic_impact.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x14u_normal_kinetic_impact.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14u_normal_kinetic_impact.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14u_normal_kinetic_impact.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14u_normal_kinetic_impact.sh`

### `x14v` — Kick cinétique excédentaire

- **Clé unique :** `0493x14v`
- **ID canonique :** `0493x14v`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Actif dans chaîne x14 candidate
- **Confiance :** `A`
- **Date :** `2026-09-03`
- **Commit :** `5dd346136d2da9d69952b9cade7ed8eb91a2b93f`

Transfère J_excess = J_raw - J_thermo au liquide afin d'ajouter le flux cinétique hors équilibre sans doubler la pression x6g.

**Relations :**
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14V_GAS_KINETIC_EXCESS_KICK.md`
- `ASSOCIATED_WITH` — `doc/README_0493X14X_X14V_ABLATION_OVERRIDE_FIX.md`
- `ASSOCIATED_WITH` — `doc/README_0493X14Y_X14V_PG_SUBTRACTION_ABLATION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14af_q6_x14v_global_balance.py`
- `ASSOCIATED_WITH` — `scripts/apply_0493x14v_gas_kinetic_excess_kick.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14af_q6_x14v_global_balance.sh`

### `x14w` — Couette biphasique

- **Clé unique :** `0493x14w`
- **ID canonique :** `0493x14w`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** PASS-like sur contrainte tangentielle
- **Confiance :** `A`
- **Date :** `2026-09-03`
- **Commit :** `5dd346136d2da9d69952b9cade7ed8eb91a2b93f`

Benchmark de transfert tangentiel; teste continuité de contrainte via collisions SRC communes sans frottement interfacial ad hoc.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14W_TWO_PHASE_COUETTE.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14w_two_phase_couette.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14w_two_phase_couette.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14w_two_phase_couette.sh`

### `x14x` — Goutte oscillante diphasique n=2

- **Clé unique :** `0493x14x`
- **ID canonique :** `0493x14x`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Qualification intégrée/tooling
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Runner intégré x6g+x9+x14l+x14v+chaîne liquide; banc pour forme, moment et fréquence.

**Relations :**
- `REFERENCES` → `x14l` — Réflexion spéculaire du gaz
- `REFERENCES` → `x14v` — Kick cinétique excédentaire
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14X_TWO_PHASE_OSCILLATING_DROP_N2.md`
- `ASSOCIATED_WITH` — `doc/README_0493X14X_X14V_ABLATION_OVERRIDE_FIX.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14x_oscillating_drop_n2.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x14x_oscillating_drop_two_phase.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14x_oscillating_drop_n2.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14x_oscillating_drop_two_phase.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14x_oscillating_drop_liquid_gas.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14x_two_phase_oscillating_drop_n2.sh`

### `x14y` — Ablation sans soustraction p_g

- **Clé unique :** `0493x14y`
- **ID canonique :** `0493x14y`
- **Nature / domaine :** `ABLATION` / `LIQUID_GAS`
- **Statut :** Rejeté: double comptage pression équilibre
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Transfère J_raw directement et supprime la soustraction thermodynamique.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14Y_X14V_PG_SUBTRACTION_ABLATION.md`

### `x14z` — Fermeture géométrique p_ref

- **Clé unique :** `0493x14z`
- **ID canonique :** `0493x14z`
- **Nature / domaine :** `ABLATION` / `LIQUID_GAS`
- **Statut :** Rejeté comme cause du défaut n=1
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Corrige la résultante du seul p_ref uniforme sur la polyligne x10n.

**Relations :**
- `REFERENCES` → `x10n` — Interface continue marching-squares mobile

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14Z_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE.md`

### `x14aa` — Traction thermodynamique absolue sur faces x6g

- **Clé unique :** `0493x14aa`
- **ID canonique :** `0493x14aa`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Non retenu: dégrade la géométrie locale de forme
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Déplace toute la traction sur la géométrie de faces Q6.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AA_X6G_FACE_THERMO_TRACTION.md`

### `x14ab` — p_ref sur x10n + jauge sur faces x6g

- **Clé unique :** `0493x14ab`
- **ID canonique :** `0493x14ab`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Non retenu
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Sépare référence et jauge mais garde traction variable sur normales axiales Q6.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AB_HYBRID_GAUGE_THERMO_TRACTION.md`

### `x14ac` — Projection globale minimum-L2

- **Clé unique :** `0493x14ac`
- **ID canonique :** `0493x14ac`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Principe conservé, local supplanté par x14ad
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Garde l'ancien échantillonnage local et corrige uniquement la résultante globale.

**Relations :**
- `SUPERSEDED_BY` → `x14ad` — Traction locale cohérente avec faces x6g

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AC_GAUGE_RESULTANT_PROJECTION.md`

### `x14ad` — Traction locale cohérente avec faces x6g

- **Clé unique :** `0493x14ad`
- **ID canonique :** `0493x14ad`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Retenu pour interfaces courbes x14
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Échantillonne la pression de jauge des faces représentées qui terminent chaque segment x10n, applique sur normale locale, puis corrige la résultante résiduelle.

**Relations :**
- `REFERENCES` → `x10n` — Interface continue marching-squares mobile

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AD_LOCAL_X6G_FACE_GAUGE_PROJECTION.md`

### `x14ae` — Diagnostic pertes scatter

- **Clé unique :** `0493x14ae`
- **ID canonique :** `0493x14ae`
- **Nature / domaine :** `DIAGNOSTIC` / `LIQUID_GAS`
- **Statut :** Diagnostic; pertes nulles sur cas discriminant
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Compte les kicks x14v qui ne trouvent aucun support liquide après CIC/fallback.

**Relations :**
- `REFERENCES` → `x14v` — Kick cinétique excédentaire

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AE_SCATTER_LOSS_DIAGNOSTIC.md`

### `x14af` — Diagnostic bilan global

- **Clé unique :** `0493x14af`
- **ID canonique :** `0493x14af`
- **Nature / domaine :** `DIAGNOSTIC` / `LIQUID_GAS`
- **Statut :** Diagnostic causal
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Mesure J_Q6 applique, J_thermo et x14v; identifie le mismatch Q6/B1 - traction reconstruite comme source de dérive.

**Relations :**
- `REFERENCES` → `x14v` — Kick cinétique excédentaire

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AF_X14AG_BALANCE_AND_DYNAMIC_DRAG.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14af_q6_x14v_global_balance.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14af_q6_x14v_global_balance.sh`

### `x14ag` — Traînée avec inlet/outlet

- **Clé unique :** `0493x14ag`
- **ID canonique :** `0493x14ag`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Abandonné
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Premier benchmark de traînée ouvert; évolution du gaz jusqu'à inversion du courant.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AF_X14AG_BALANCE_AND_DYNAMIC_DRAG.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14ag_drop_gas_poiseuille.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14ag_drop_gas_poiseuille.py`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14ag_drop_gas_poiseuille_drag.sh`

### `x14ah` — Traînée périodique-x

- **Clé unique :** `0493x14ah`
- **ID canonique :** `0493x14ah`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Benchmark intégré
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Canal périodique avec goutte entraînée par un profil gazeux; vérifie que la fermeture ne supprime pas la vraie traînée.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AH_CORRECTED_DYNAMIC_DRAG.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14ah_drop_gas_transient_poiseuille.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14ah_drop_gas_transient_poiseuille.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x14ah_drop_gas_transient_poiseuille.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x14ah_drop_gas_transient_poiseuille.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14ah_drop_gas_transient_poiseuille.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14ah_drop_gas_transient_poiseuille.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14ah_drop_gas_transient_poiseuille_drag.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14ah_drop_gas_transient_poiseuille_drag.sh`

### `x14ai` — Fermeture de résultante Q6 appliquée

- **Clé unique :** `0493x14ai`
- **ID canonique :** `0493x14ai`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Concept retenu mais version initiale supplantée
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Utilise la résultante B1/RT0 réellement appliquée comme cible globale de la projection de traction x14ad.

**Relations :**
- `REFERENCES` → `x14ad` — Traction locale cohérente avec faces x6g

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AI_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE.md`
- `ASSOCIATED_WITH` — `doc/README_0493X14AI_FIX1_POST_PERIODIC_RESULTANT.md`
- `ASSOCIATED_WITH` — `doc/src_mpcd_env_flags_inventory_snapshot_040926_x14ai.csv`
- `ASSOCIATED_WITH` — `doc/src_mpcd_params_inventory_snapshot_040926_x14ai.csv`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14ai_cost_ab.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14ai_cost_ab.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x14ai_drag_device_closure.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh`

### `x14ai-fix1` — Fermeture B1 exacte post-correction périodique

- **Clé unique :** `0493x14ai-fix1`
- **ID canonique :** `0493x14ai-fix1`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Seulement composante liquide fermée et isolée des frontières Q6 externes
- **Confiance :** `A`
- **Date :** `2026-09-04`
- **Commit :** `8a4fc4065a2682cebf0fe32cb9cdbd32de39aef5`

Corrige la cible x14ai pour inclure la correction uniforme périodique B1; ferme le moment global au roundoff.

**Relations :**
- `FIXES` → `x14ai` — Fermeture de résultante Q6 appliquée
- `REFERENCES` → `x14ai` — Fermeture de résultante Q6 appliquée

### `x14aj` — Goutte oscillante n=3 avec gaz

- **Clé unique :** `0493x14aj`
- **ID canonique :** `0493x14aj`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** REVIEW: fréquence ~12% lente dans campagne actuelle
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Qualification du mode n=3 de la chaîne x14ai-fix1.

**Relations :**
- `REFERENCES` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14aj_oscillating_drop_n3_two_phase.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14aj_oscillating_drop_n3_two_phase.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14aj_oscillating_drop_n3_two_phase.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14aj_oscillating_drop_n3_device_closure.sh`

### `x14ak` — Taylor-Culick diphasique - fluide x14

- **Clé unique :** `0493x14ak`
- **ID canonique :** `0493x14ak`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** REVIEW; ne pas utiliser pour isoler effet gaz
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

TC avec paramètres liquide x14 (gamma=20, dt=0.002, etc.); comparaison historique confondait changement de fluide et effet gaz.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14ak_taylor_culick_two_phase.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x14ak_taylor_culick_two_phase.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14ak_taylor_culick_two_phase.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14ak_taylor_culick_two_phase.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14ak_taylor_culick_two_phase_device_closure.sh`

### `x14al` — Taylor-Culick apparié au point x13h

- **Clé unique :** `0493x14al`
- **ID canonique :** `0493x14al`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Contrôle liquide reproduit; branche gaz à relire car EOS global kBT avait été mal aligné dans le premier runner
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Deux runs avec liquide initial identique: liquide seul vs même liquide + gaz, pour isoler le couplage gaz.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AL_TC_HISTORICAL_AB.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14al_taylor_culick_recording.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/compare_0493x14al_taylor_culick_ab.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x14al_taylor_culick_historical_ab.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14al_taylor_culick_recording.py`
- `ASSOCIATED_WITH` — `scripts/compare_0493x14al_taylor_culick_ab.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x14al_taylor_culick_historical_ab.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14al_taylor_culick_historical_ab.sh`

### `x14am` — Young-Laplace diphasique multi-rayons

- **Clé unique :** `0493x14am`
- **ID canonique :** `0493x14am`
- **Nature / domaine :** `DIAGNOSTIC` / `LIQUID_GAS`
- **Statut :** REVIEW/non décisif à sigma=10000: kappa_active et pression sont déjà connus comme métrologie bruyante/non monotone dans ce régime
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Screening multi-rayons avec x9e sans baseline sigma=0 longue.

**Relations :**
- `REFERENCES` → `x9e` — Qualification diagnostique de goutte statique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AM_YOUNG_LAPLACE_TWO_PHASE.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14am_young_laplace_two_phase.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14am_young_laplace_two_phase.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14am_young_laplace_two_phase.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14am_young_laplace_two_phase_multiradius.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x14am_young_laplace_two_phase_multiradius.sh.before_resolved_gas`

### `x0` — Démonstration dam-break bi-espèces du Q6 independent_masked

- **Clé unique :** `0493x0`
- **ID canonique :** `0493x0`
- **Nature / domaine :** `VISUALIZATION` / `SPECIES_Q6`
- **Statut :** Démonstration historique d'intégration
- **Confiance :** `A`

Introduit une démonstration qualitative d'une colonne liquide dense entourée d'un gaz compressible, avec speciesQ6Mode=independent_masked, q6Strength liquide=1 et gaz=0. Le cas sert d'intégration/visualisation du Q6 multi-espèces et non de benchmark surface libre calibré.

**Notes.** Le runner a d'abord utilisé un petit vent segmented pour le gaz; x1 remplace ensuite cette topologie par une boîte réellement fermée afin d'éliminer l'injection continue et le panache artificiel.

**Relations :**
- `BUILDS_ON` → `0493W8` — Équivalence Taylor--Green mono / dual-identique du Q6 independent_masked
- `DEMONSTRATES` → `x1` — Chemin de frontières closed-box CUDA résident

### `x1` — Chemin de frontières closed-box CUDA résident

- **Clé unique :** `0493x1`
- **ID canonique :** `0493x1`
- **Nature / domaine :** `CODE` / `BOUNDARY`
- **Statut :** Étape historique qualifiée pour la démonstration dam-break
- **Confiance :** `A`

Étend le chemin parois CUDA résident à une boîte rectangulaire statique non périodique sur les quatre faces. Le premier sous-ensemble accepte solid/specular, sans segment ouvert, obstacle immergé, domaine mobile ni resampling; Q6 independent_masked est exécuté de façon résidente avec boundaryFamily=closed_box.

**Notes.** Introduit pour supprimer le vent gazeux de x0, qui provoquait une injection continue et un panache artificiel. Le support est opt-in via MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1.

**Relations :**
- `EXTENDS` → `0493W7` — Q6 independent_masked sur toutes les familles de frontières résidentes

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X1_CLOSED_BOX_CUDA_RESIDENT.md`
- `ASSOCIATED_WITH` — `scripts/run_0493x1_closed_box_smoke.sh`

### `x10a` — Géométrie de crossing et seal du endpoint réfléchi

- **Clé unique :** `0493x10a`
- **ID canonique :** `0493x10a`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Étape géométrique historique; fondation des essais de confinement x10b-x10e, ensuite supplantée par la paroi mobile continue
- **Confiance :** `A`
- **Date :** `2026-08-22`

Affine la normale de réflexion au crossing physique alpha=0.5 et scelle géométriquement le endpoint d’une vraie traversée intérieure, sans changer la loi de vitesse/réaction x9z.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x9z` — Réflexion individuelle des donneurs et compensation affine du bain
- `REFERENCES` → `x9z` — Réflexion individuelle des donneurs et compensation affine du bain

### `x10b` — Rétention hard-r1 des particules de shell

- **Clé unique :** `0493x10b`
- **ID canonique :** `0493x10b`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Étape historique hard-r1; sur-confinement ensuite corrigé par x10h
- **Confiance :** `A`
- **Date :** `2026-08-22`

Étend x10a aux particules déjà côté extérieur mais reliées à un bain bulk direct : le endpoint est ramené par bracket/mirror vers le bulk, position seulement, sans nouvelle passe ni modification de réaction.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10a` — Géométrie de crossing et seal du endpoint réfléchi
- `REFERENCES` → `x10a` — Géométrie de crossing et seal du endpoint réfléchi
- `REFERENCES` → `x10h` — Rétention relative compatible avec interface mobile

### `x10biq` — Reconstruction Q2 biquadratique tensorielle

- **Clé unique :** `0493x10biq`
- **ID canonique :** `0493x10biq`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Vrai Q2 actif dans la chaîne x12; x10r/s/t doivent être OFF
- **Confiance :** `A`

Construit sur un stencil 3x3 un interpolant tensoriel biquadratique de l’alpha cinétique CIC et utilise la même enveloppe Q2 pour crossing et géométrie de recouvrement.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10cic` — Alpha cinétique CIC dédié
- `REFERENCES` → `x10p` — Résolution des recouvrements initiaux
- `REFERENCES` → `x10q` — Récupération large des recouvrements initiaux rares
- `REFERENCES` → `x10r` — Ablation vitesses endpoints full-vector

### `x10c` — Barrière universelle du endpoint final r=1

- **Clé unique :** `0493x10c`
- **ID canonique :** `0493x10c`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Étape historique de confinement universel; retirée par x10h car incompatible avec une interface réellement mobile
- **Confiance :** `A`
- **Date :** `2026-08-22`

Après réflexion donneur, réaction receveur et récupération shell, vérifie le endpoint réellement streamé de toute particule A en r=1 et corrige les endpoints encore dehors sans modifier la vitesse.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10b` — Rétention hard-r1 des particules de shell
- `REFERENCES` → `x10h` — Rétention relative compatible avec interface mobile

### `x10cic` — Alpha cinétique CIC dédié

- **Clé unique :** `0493x10cic`
- **ID canonique :** `0493x10cic`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Composant actif de la chaîne x12; orchestration encore appelée depuis le chemin Q6
- **Confiance :** `A`

Dépose un champ alpha CIC réservé à la géométrie cinétique, distinct du x6c utilisé par Q6/pression/capillarité; le dépôt est fusionné dans le passage total-A et n’ajoute pas de nouveau parcours O(Np).

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha

### `x10d` — Réaction analytique locale exactement conservative P/K

- **Clé unique :** `0493x10d`
- **ID canonique :** `0493x10d`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Branche analytique historique; définition conservée mais orchestration hard-r1 courante la bypass au profit de x10i/x10o
- **Confiance :** `A`
- **Date :** `2026-08-22`

Remplace en hard-r1 la translation+rescale des receveurs par une racine collective analytique par cellule, conservant exactement quantité de mouvement et énergie cinétique sans lambda ni energy floor.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10c` — Barrière universelle du endpoint final r=1
- `REFERENCES` → `x10i` — Réaction exacte par réservoirs mésoscopiques décalés
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

### `x10e` — Miroir tangent du endpoint final

- **Clé unique :** `0493x10e`
- **ID canonique :** `0493x10e`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Expérience de forme/isotropie historique, retirée avec la barrière universelle par x10h
- **Confiance :** `A`
- **Date :** `2026-08-22`

Ablation géométrique remplaçant le clamp x10c par un miroir local tangent du déplacement résiduel, tout en conservant la réaction analytique x10d; aucune vitesse ni passe particulaire supplémentaire.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10d` — Réaction analytique locale exactement conservative P/K
- `FIXES` → `x10c` — Barrière universelle du endpoint final r=1
- `REFERENCES` → `x10c` — Barrière universelle du endpoint final r=1
- `REFERENCES` → `x10d` — Réaction analytique locale exactement conservative P/K
- `REFERENCES` → `x10h` — Rétention relative compatible avec interface mobile

### `x10f` — Ablation réaction exacte sur réservoir liquide global

- **Clé unique :** `0493x10f`
- **ID canonique :** `0493x10f`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation causale; non production multi-gouttes, code conservé sans call-site actif
- **Confiance :** `A`
- **Date :** `2026-08-22`

Agrège la réaction P/K exacte sur tout le composant phase-A de l’appel afin de tester si le contre-kick cellule-local cause l’accumulation cardinale; explicitement limité à un seul composant liquide.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10e` — Miroir tangent du endpoint final
- `REFERENCES` → `x10d` — Réaction analytique locale exactement conservative P/K

### `x10g` — Réduction GPU hiérarchique de la réaction globale

- **Clé unique :** `0493x10g`
- **ID canonique :** `0493x10g`
- **Nature / domaine :** `PERF` / `FREE_SURFACE_KINETICS`
- **Statut :** Optimisation performance-only de x10f; physique identique, code conservé sans call-site actif
- **Confiance :** `A`
- **Date :** `2026-08-22`

Remplace uniquement les atomiques globaux contendus de x10f par une réduction cellules→partials par bloc→bloc final, en réutilisant exactement le finalizer et les équations x10f.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10f` — Ablation réaction exacte sur réservoir liquide global
- `REFERENCES` → `x10f` — Ablation réaction exacte sur réservoir liquide global

### `x10h` — Rétention relative compatible avec interface mobile

- **Clé unique :** `0493x10h`
- **ID canonique :** `0493x10h`
- **Nature / domaine :** `FIX` / `FREE_SURFACE_KINETICS`
- **Statut :** Sémantique legacy intégrée; barrière universelle supprimée, chemin ensuite bypassé par x10o en production x12
- **Confiance :** `A`
- **Date :** `2026-08-22`

Corrige le sur-confinement x10b/c/e : l’interface alpha=0.5 peut advecter; seules les particules réellement sortantes relativement au bain/interface et sélectionnées comme donneurs sont réfléchies/scellées.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10g` — Réduction GPU hiérarchique de la réaction globale
- `FIXES` → `x10c` — Barrière universelle du endpoint final r=1
- `FIXES` → `x10e` — Miroir tangent du endpoint final
- `REFERENCES` → `x10b` — Rétention hard-r1 des particules de shell
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

### `x10i` — Réaction exacte par réservoirs mésoscopiques décalés

- **Clé unique :** `0493x10i`
- **ID canonique :** `0493x10i`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Fallback hard-r1 legacy encore actif hors ablations continues; bypassé par x10o dans la chaîne x12
- **Confiance :** `A`
- **Date :** `2026-08-22`

Remplace le réservoir global x10f/g par une partition déterministe de blocs mésoscopiques décalée à chaque pas; chaque réservoir applique sa propre racine P/K exacte.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10h` — Rétention relative compatible avec interface mobile
- `FIXES` → `x10f` — Ablation réaction exacte sur réservoir liquide global
- `REFERENCES` → `x10f` — Ablation réaction exacte sur réservoir liquide global
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

### `x10j` — Ablation spéculaire dans le repère laboratoire

- **Clé unique :** `0493x10j`
- **ID canonique :** `0493x10j`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée : conservation de norme labo mais dripping fortement bloqué; OFF production
- **Confiance :** `A`
- **Date :** `2026-08-22`

Réfléchit simplement la vitesse sur la normale d’interface dans le repère laboratoire, sans contre-réaction collective, pour isoler le rôle de la réaction mésoscopique.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10i` — Réaction exacte par réservoirs mésoscopiques décalés

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10j_simple_specular.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10j_simple_specular_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10j_simple_specular_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10j_simple_specular_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10j_simple_specular_static_drop.sh`

### `x10k` — Ablation spéculaire dans le repère liquide local

- **Clé unique :** `0493x10k`
- **ID canonique :** `0493x10k`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée; améliore la covariance locale mais ne fournit pas la fermeture de production
- **Confiance :** `A`
- **Date :** `2026-08-22`

Réfléchit v-u_b sur la normale locale, conservant exactement |v-u_b| et imposant une composante relative normale entrante, sans contre-impulsion de l’interface.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10j` — Ablation spéculaire dans le repère laboratoire

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10k_local_frame_specular.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10k_local_frame_specular_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10k_local_frame_specular_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10k_local_frame_specular_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10k_local_frame_specular_static_drop.sh`

### `x10l` — Diagnostic passif pré-paroi cinétique

- **Clé unique :** `0493x10l`
- **ID canonique :** `0493x10l`
- **Nature / domaine :** `DIAGNOSTIC` / `FREE_SURFACE_KINETICS`
- **Statut :** Diagnostic observation-only encore activable; ON dans certains runners JFM, aucune modification vitesse/position
- **Confiance :** `A`
- **Date :** `2026-08-22`

Mesure après Q6/B1 et juste avant la fermeture cinétique les flux/vitesses normaux sortants afin de séparer la dynamique hydrodynamique projetée de l’action de la paroi cinétique.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10k` — Ablation spéculaire dans le repère liquide local

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10l_prewall_interface.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10l_prewall_interface_dual_diagnostic.sh`

### `x10m` — Paroi locale mobile alpha=0.5

- **Clé unique :** `0493x10m`
- **ID canonique :** `0493x10m`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Étape architecturale/ablation OFF production; scratch et primitives seront réutilisés par les étapes continues
- **Confiance :** `A`
- **Date :** `2026-08-22`

Introduit une primitive de collision événementielle avec un plan local alpha=0.5 mobile dont la vitesse normale provient du liquide post-Q6/B1; l’impulsion de paroi est auditée sans feedback.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10l` — Diagnostic passif pré-paroi cinétique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10m_moving_interface_wall.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10m_moving_interface_wall_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10m_moving_interface_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10m_moving_interface_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10m_moving_interface_static_drop.sh`

### `x10n` — Interface continue marching-squares mobile

- **Clé unique :** `0493x10n`
- **ID canonique :** `0493x10n`
- **Nature / domaine :** `INFRA` / `FREE_SURFACE_KINETICS`
- **Statut :** Architecture continue OFF comme mode autonome; primitives réutilisées par x10o, Q2, x12a et suites
- **Confiance :** `A`
- **Date :** `2026-08-22`

Reconstruit une polyligne alpha=0.5 continue sur la grille duale, avec endpoints partagés, normales et vitesses de segments, puis collisions événementielles jusqu’à trois impacts.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10m` — Paroi locale mobile alpha=0.5
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `REFERENCES` → `x12a` — Refroidissement thermique local des petites structures

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10n_continuous_interface.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10n_continuous_interface_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10n_continuous_interface_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10n_continuous_interface_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10n_continuous_interface_static_drop.sh`

### `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

- **Clé unique :** `0493x10o`
- **ID canonique :** `0493x10o`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Socle actif de la chaîne liquide qualifiée x12; priorité sur x10j/k/m/n
- **Confiance :** `A`
- **Date :** `2026-08-22`

Fonde la paroi cinétique de production sur l’interface continue : vitesse normale issue de l’hydrodynamique Q6 projetée et enveloppe thermique locale delta=min(deltaMax,C dt sqrt(kBT/m)).

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10n` — Interface continue marching-squares mobile
- `REFERENCES` → `x10j` — Ablation spéculaire dans le repère laboratoire

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10o_q6_thermal_interface.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10o_q6_thermal_interface_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dripping_high.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dripping_restart.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_static_drop.sh`

### `x10p` — Résolution des recouvrements initiaux

- **Clé unique :** `0493x10p`
- **ID canonique :** `0493x10p`
- **Nature / domaine :** `FIX` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif en production x12; aucune passe particulaire supplémentaire
- **Confiance :** `A`
- **Date :** `2026-08-22`

Avant le sweep, trouve le segment mobile fini le plus proche d’une particule initialement du mauvais côté; dépénètre toujours, et ne réfléchit la vitesse que si le mouvement relatif est sortant.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

### `x10q` — Récupération large des recouvrements initiaux rares

- **Clé unique :** `0493x10q`
- **ID canonique :** `0493x10q`
- **Nature / domaine :** `FIX` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif en production x12; complète x10p sans élargir le hot path normal
- **Confiance :** `A`
- **Date :** `2026-08-22`

Lorsque la recherche normale 3x3 ne trouve aucun segment pour l’événement initial, ajoute uniquement un fallback 7x7; les collisions swept ordinaires restent 3x3 et les overlaps profonds connus ne sont plus refusés.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10p` — Résolution des recouvrements initiaux
- `FIXES` → `x10p` — Résolution des recouvrements initiaux
- `REFERENCES` → `x10p` — Résolution des recouvrements initiaux

### `x10r` — Ablation vitesses endpoints full-vector

- **Clé unique :** `0493x10r`
- **ID canonique :** `0493x10r`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée : dripping dégradé; OFF production
- **Confiance :** `A`
- **Date :** `2026-08-26`

Teste des vitesses vectorielles complètes aux endpoints de segment pour améliorer la covariance galiléenne de la paroi thermique.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10r_galilean_compare.py`

### `x10s` — Ablation cinématique normale au segment

- **Clé unique :** `0493x10s`
- **ID canonique :** `0493x10s`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée/OFF; incompatible avec le vrai Q2 de production
- **Confiance :** `A`
- **Date :** `2026-08-26`

Projette la cinématique de la paroi thermique sur la normale du segment pour isoler la composante normale dans les tests de covariance.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10s_galilean_compare.py`

### `x10t` — Ablation cinématique tangentielle rigide

- **Clé unique :** `0493x10t`
- **ID canonique :** `0493x10t`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée : impulse parasite aggravée; OFF production
- **Confiance :** `A`
- **Date :** `2026-08-26`

Teste une cinématique tangentielle rigide de l’interface thermique pour mesurer l’effet des composantes tangentielles sur l’impulsion parasite.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10t_galilean_compare.py`

### `x10u` — Relocalisation conservative one-for-one

- **Clé unique :** `0493x10u`
- **ID canonique :** `0493x10u`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif dans la chaîne liquide qualifiée; requiert Q2 et x10p
- **Confiance :** `A`
- **Date :** `2026-08-29`

Après sélection CIC+Q2 du crossing/overlap, conserve exactement le même slot, la même masse et la même vitesse et miroire seulement la position vers le support liquide; contribution directe deltaM/deltaP/deltaK nulle.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10biq` — Reconstruction Q2 biquadratique tensorielle
- `BUILDS_ON` → `x10q` — Récupération large des recouvrements initiaux rares
- `REFERENCES` → `x10p` — Résolution des recouvrements initiaux

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14k_bilateral_x10u_drop.sh`

### `x10v` — Swap local full-vector one-for-one

- **Clé unique :** `0493x10v`
- **ID canonique :** `0493x10v`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif dans la chaîne liquide qualifiée; utilise un byte/particule et deux kernels conditionnels
- **Confiance :** `A`
- **Date :** `2026-08-29`

Après relocalisation x10u, échange littéralement les vecteurs vitesse entre la particule relocalisée et un candidat local de même masse, de façon pairwise conservative en P et K.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10u` — Relocalisation conservative one-for-one
- `REFERENCES` → `x10u` — Relocalisation conservative one-for-one

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x10v_off.sh`

### `x10w` — Limiter thermique local pairwise

- **Clé unique :** `0493x10w`
- **ID canonique :** `0493x10w`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Implémenté mais OFF production; exclusif avec x12a dans le snapshot audité
- **Confiance :** `A`
- **Date :** `2026-08-26`

Ajoute une redistribution locale pré-stream pour limiter le transport thermique de phase selon la résolution locale (courbure/épaisseur), avec conservation pairwise P/K; remplace un ancien limiter de position virtuelle.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10v` — Swap local full-vector one-for-one
- `REFERENCES` → `x12a` — Refroidissement thermique local des petites structures

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/collect_0493x10w_fix1_static_results.sh`
- `ASSOCIATED_WITH` — `scripts/collect_0493x10w_pairwise_static_results.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_dripping_ab_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_fix1_static_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_pairwise_static_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_static_qualification.sh`

### `x10x` — Qualification de l’enveloppe thermique en C et sigma

- **Clé unique :** `0493x10x`
- **ID canonique :** `0493x10x`
- **Nature / domaine :** `QUALIFICATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Outil de qualification/campagne; aucun nouveau mode C++
- **Confiance :** `A`
- **Date :** `2026-08-26`

Campagne scripts-only balayant l’épaisseur thermique via le coefficient C/sigmas et des cas de référence afin de caractériser la sensibilité de la paroi x10o sans nouvelle physique C++.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique

### `x10y` — Analyse loi taille-température de l’enveloppe

- **Clé unique :** `0493x10y`
- **ID canonique :** `0493x10y`
- **Nature / domaine :** `QUALIFICATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Analyse scripts-only; aucun nouveau mode C++
- **Confiance :** `A`
- **Date :** `2026-08-26`

Analyse les campagnes x10x pour tester la dépendance de l’épaisseur/effet thermique avec taille, température et échelle de particule.

**Notes.** Curation V4.18 fondée sur les patches historiques primaires et l’audit d’implémentation du snapshot 26/08/2026; distinguer les étapes historiques/ablations du chemin x12 qualifié.

**Relations :**
- `BUILDS_ON` → `x10x` — Qualification de l’enveloppe thermique en C et sigma
- `REFERENCES` → `x10x` — Qualification de l’enveloppe thermique en C et sigma

### `x11a` — Qualification Young–Laplace quantitative

- **Clé unique :** `0493x11a`
- **ID canonique :** `0493x11a`
- **Nature / domaine :** `QUALIFICATION` / `SURFACE_TENSION`
- **Statut :** Qualification historique quantitative; base de la calibration mécanique x12yl
- **Confiance :** `A`
- **Date :** `2026-08-22`
- **Commit :** `8f587696bac0f48a813025e5cb364603ba6cfeba`

Mesure sur gouttes statiques multi-rayons/multi-sigma la loi de Laplace avec la pression Q6 résolue x9e; la lecture finale utilise les baselines sigma=0 appariées consolidées par x11c.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x10q` — Récupération large des recouvrements initiaux rares
- `REFERENCES` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `REFERENCES` → `x12yl` — Calibrateur mécanique/statique de tension superficielle
- `REFERENCES` → `x9e` — Qualification diagnostique de goutte statique
- `SUPERSEDED_BY` → `x12yl` — Calibrateur mécanique/statique de tension superficielle

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11a_young_laplace.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11a_young_laplace_paired.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x11a_young_laplace_sigma0_baselines.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x11a_young_laplace_validation.sh`

### `x11b` — Qualification de dispersion des ondes capillaires

- **Clé unique :** `0493x11b`
- **ID canonique :** `0493x11b`
- **Nature / domaine :** `QUALIFICATION` / `SURFACE_TENSION`
- **Statut :** Qualification dynamique historique; base méthodologique du calibrateur x12cal
- **Confiance :** `A`
- **Date :** `2026-08-22`
- **Commit :** `8f587696bac0f48a813025e5cb364603ba6cfeba`

Excite des interfaces sinusoïdales résolues, suit les modes de Fourier et ajuste leur oscillation amortie pour comparer omega_num à la dispersion capillaire théorique.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x10q` — Récupération large des recouvrements initiaux rares
- `REFERENCES` → `x11a` — Qualification Young–Laplace quantitative
- `REFERENCES` → `x12cal` — Calibrateur dynamique de tension superficielle
- `SUPERSEDED_BY` → `x12cal` — Calibrateur dynamique de tension superficielle

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11b_capillary_wave.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11b_capillary_wave_earlyfit.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x11b_capillary_wave_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x11b_capillary_wave_validation.sh`

### `x11c` — Correction de protocole capillaire et baseline sigma=0

- **Clé unique :** `0493x11c`
- **ID canonique :** `0493x11c`
- **Nature / domaine :** `DIAGNOSTIC` / `SURFACE_TENSION`
- **Statut :** Correction analyse/protocole et support observation-only; aucune nouvelle physique capillaire
- **Confiance :** `A`
- **Date :** `2026-08-22`
- **Commit :** `8f587696bac0f48a813025e5cb364603ba6cfeba`

Corrige l’analyse x11 sans nouvelle force: Young–Laplace utilise p(sigma)-p(0), les ondes sont refittées sur la fenêtre précoce haut-SNR, et le support p3/x9e peut être construit à cadence diagnostic pour sigma=0 sans appliquer de potentiel capillaire.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x11a` — Qualification Young–Laplace quantitative
- `BUILDS_ON` → `x11b` — Qualification de dispersion des ondes capillaires
- `FIXES` → `x11a` — Qualification Young–Laplace quantitative
- `FIXES` → `x11b` — Qualification de dispersion des ondes capillaires
- `REFERENCES` → `x9e` — Qualification diagnostique de goutte statique

### `x12a` — Refroidissement thermique local des petites structures

- **Clé unique :** `0493x12a`
- **ID canonique :** `0493x12a`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif dans la chaîne liquide qualifiée; exclusif avec le limiter x10w
- **Confiance :** `A`
- **Date :** `2026-08-26`
- **Commit :** `5fea55644b841a0bd0c04ad8be908d04b3bbd6b6`

Ajoute la seule nouvelle physique runtime x12: fT=min(1,(Lloc/Rc)^2), où Lloc est la demi-distance à l’interface alpha=0.5 opposée le long de la normale Q2 intérieure; fT réduit localement l’enveloppe cinétique x10o et la cible thermostat.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x10v` — Swap local full-vector one-for-one
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `REFERENCES` → `x10w` — Limiter thermique local pairwise

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x12a_local_thermal_cooling.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_local_thermal_cooling_validation.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_minradius_splash_overnight.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_minradius_splash_overnight_fix1.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_obstacle_splash_darcy_chi.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_obstacle_splash_darcy_chi_fix1.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_obstacle_splash_darcy_chi_fix1_mono.sh`

### `x12b` — Prototype JFM D=320h sur obstacle Darcy/chi

- **Clé unique :** `0493x12b`
- **ID canonique :** `0493x12b`
- **Nature / domaine :** `BENCHMARK` / `FREE_SURFACE_KINETICS`
- **Statut :** Benchmark exploratoire de construction; pas encore une reproduction quantitative JFM 524
- **Confiance :** `A`
- **Date :** `2026-08-26`
- **Commit :** `5fea55644b841a0bd0c04ad8be908d04b3bbd6b6`

Construit un cas splash 2-D à goutte D=320h et marche obstacle Darcy/chi avec la chaîne x10v+x12a; il fixe une géométrie JFM-scaled mais se déclare encore exploratoire, sans nouvelle physique C++.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x12a` — Refroidissement thermique local des petites structures
- `REFERENCES` → `x10v` — Swap local full-vector one-for-one
- `REFERENCES` → `x12a` — Refroidissement thermique local des petites structures

### `x12c` — Benchmark JFM compact-Y à physique inchangée

- **Clé unique :** `0493x12c`
- **ID canonique :** `0493x12c`
- **Nature / domaine :** `BENCHMARK` / `FREE_SURFACE_KINETICS`
- **Statut :** Étape de production/compaction du benchmark; physique identique à x12b
- **Confiance :** `A`
- **Date :** `2026-08-26`
- **Commit :** `5fea55644b841a0bd0c04ad8be908d04b3bbd6b6`

Réduit le domaine vertical inutilisé du cas x12b en conservant h et la même chaîne physique, afin de rendre la campagne obstacle/splash plus exploitable sans modifier le solveur.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x12b` — Prototype JFM D=320h sur obstacle Darcy/chi
- `REFERENCES` → `x12b` — Prototype JFM D=320h sur obstacle Darcy/chi

### `x12cal` — Calibrateur dynamique de tension superficielle

- **Clé unique :** `0493x12cal`
- **ID canonique :** `0493x12cal`
- **Nature / domaine :** `CALIBRATOR` / `SURFACE_TENSION`
- **Statut :** Calibrateur dynamique courant; aucune nouvelle physique C++
- **Confiance :** `A`
- **Date :** `2026-08-26`
- **Commit :** `5fea55644b841a0bd0c04ad8be908d04b3bbd6b6`

Mesure sigma_eff dynamique par dispersion omega^2=(sigma/rho) k^3 tanh(kH) sur plusieurs modes/réalisations, avec politique PASS/REVIEW/INVALID; la propriété dynamique reste distincte de la calibration mécanique x12yl.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x11b` — Qualification de dispersion des ondes capillaires
- `BUILDS_ON` → `x12a` — Refroidissement thermique local des petites structures
- `REFERENCES` → `x12yl` — Calibrateur mécanique/statique de tension superficielle

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X12CAL_CAPILLARY_CALIBRATOR.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x12cal_capillary_calibrator.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x12cal_capillary_calibrator.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12cal_capillary_calibrator.sh`

### `x12d` — Cas de mesure JFM 524 à géométrie/We/Fr ciblés

- **Clé unique :** `0493x12d`
- **ID canonique :** `0493x12d`
- **Nature / domaine :** `BENCHMARK` / `FREE_SURFACE_KINETICS`
- **Statut :** Benchmark applicatif de mesure; géométrie/We/Fr ciblés mais Re numérique ~649 au lieu de Re expérimental 12200
- **Confiance :** `A`
- **Date :** `2026-08-26`
- **Commit :** `5fea55644b841a0bd0c04ad8be908d04b3bbd6b6`

Verrouille le cas de mesure obstacle JFM 524 avec géométrie et We/Fr proches de l’article, sur la chaîne x10o+CIC+Q2+x10p/q+x10u/v+x12a; l’écart de Reynolds du fluide numérique reste explicitement déclaré.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x12c` — Benchmark JFM compact-Y à physique inchangée
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `REFERENCES` → `x10p` — Résolution des recouvrements initiaux
- `REFERENCES` → `x10u` — Relocalisation conservative one-for-one
- `REFERENCES` → `x12a` — Refroidissement thermique local des petites structures

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12d_jfm524_overnight_campaign.sh`

### `x12yl` — Calibrateur mécanique/statique de tension superficielle

- **Clé unique :** `0493x12yl`
- **ID canonique :** `0493x12yl`
- **Nature / domaine :** `CALIBRATOR` / `SURFACE_TENSION`
- **Statut :** Calibrateur mécanique/statique courant; remplace x11a comme extraction scalaire de sigma_eff
- **Confiance :** `A`
- **Date :** `2026-08-26`
- **Commit :** `5fea55644b841a0bd0c04ad8be908d04b3bbd6b6`

Mesure sigma_eff mécanique par paires sigma/sigma0 sur gouttes résolues: dp_cap=p(sigma)-p(0)=sigma_eff<kappa>_active, en utilisant la courbure active mesurée et une politique explicite PASS/REVIEW/INVALID.

**Notes.** Curation V4.19 fondée sur les runners/analyseurs x11/x12, les README de calibrateurs, le code courant audité et les preuves Git multi-ref. x11a/b/c n’ajoutent aucune force; x12a est la seule nouvelle physique runtime x12; x12b/c/d/cal/yl sont orchestration/benchmark/calibration.

**Relations :**
- `BUILDS_ON` → `x11c` — Correction de protocole capillaire et baseline sigma=0
- `BUILDS_ON` → `x12a` — Refroidissement thermique local des petites structures
- `REFERENCES` → `x11a` — Qualification Young–Laplace quantitative
- `REFERENCES` → `x12cal` — Calibrateur dynamique de tension superficielle

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X12YL_YOUNG_LAPLACE_CALIBRATOR.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x12yl_young_laplace_calibrator.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x12yl_young_laplace_calibrator.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12yl_young_laplace_calibrator.sh`

### `x13a` — Pré-balayage intrinsèque SRC haut-Re

- **Clé unique :** `0493x13a`
- **ID canonique :** `0493x13a`
- **Nature / domaine :** `CALIBRATOR` / `TRANSPORT_SURFACE`
- **Statut :** Pré-balayage constitutif scripts-only; aucune physique solveur nouvelle
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Cartographie sans modification solveur la portée de transport SRC-only via H_h=c_s h/nu sur les candidats A0-A6, avant toute application coûteuse.

**Relations :**
- `BUILDS_ON` → `x12cal` — Calibrateur dynamique de tension superficielle

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13a_A0_A6_design.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13A_SRC_HIGH_RE_PRESWEEP.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13a_src_high_re_presweep.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13a_src_high_re_presweep.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh`

### `x13b` — Carte constitutive SRC H/C

- **Clé unique :** `0493x13b`
- **ID canonique :** `0493x13b`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Métrologie constitutive scripts-only; aucune modification src/include
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Mesure la viscosité transverse pure, la réponse longitudinale c_s/nu_L et l’axe gamma à paramètres microscopiques contrôlés, indépendamment d’une application.

**Relations :**
- `BUILDS_ON` → `x13a` — Pré-balayage intrinsèque SRC haut-Re

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13b_default_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/0493x13b_fluid_design.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13B_CONSTITUTIVE_TRANSPORT.md`
- `ASSOCIATED_WITH` — `doc/README_0493X13B_C_FRACTIONAL_SOUND_FIX1.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13b_constitutive_transport.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13b_constitutive_transport.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13b_constitutive_transport.sh`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13b_shear_state.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13b_sound_state_fractional.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13b_C_longitudinal_response.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13b_H_constitutive_shear.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13b_constitutive_transport.sh`

### `x13c` — Qualification statistique du transport et choix gamma

- **Clé unique :** `0493x13c`
- **ID canonique :** `0493x13c`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification constitutive multi-graines; gamma=8 retenu comme compromis coût/transport
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Enrichit H et C en multi-graines et longues longueurs d’onde; qualifie la localité et conduit au compromis économique gamma=8.

**Relations :**
- `BUILDS_ON` → `x13b` — Carte constitutive SRC H/C

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13c_default_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13C_TRANSPORT_QUALIFICATION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13c_C_longitudinal_statistics.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13c_H_gamma_multiseed.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13c_transport_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13c_C_longitudinal_statistics.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13c_H_gamma_multiseed.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13c_transport_qualification.sh`

### `x13d` — Follow-up longue longueur d’onde et amortissement

- **Clé unique :** `0493x13d`
- **ID canonique :** `0493x13d`
- **Nature / domaine :** `CALIBRATOR` / `TRANSPORT_SURFACE`
- **Statut :** Calibration constitutive du point G08 de référence
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Prolonge le cisaillement à Ny=256 et refit directement le mode longitudinal amorti pour extraire nu_L et c_s avec bootstrap.

**Relations :**
- `BUILDS_ON` → `x13c` — Qualification statistique du transport et choix gamma

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13d_H256_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13D_C_FASTFIT_FIX1.md`
- `ASSOCIATED_WITH` — `doc/README_0493X13D_TRANSPORT_FOLLOWUP.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13d_C_damped_mode.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13d_H_longwave_Ny256.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13d_C_fastfit_fix1.sh`
- `ASSOCIATED_WITH` — `scripts/check_0493x13d_transport_followup.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13d_C_damped_analysis.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13d_H_longwave_Ny256.sh`

### `x13e` — Qualification de portée Mach du point G08

- **Clé unique :** `0493x13e`
- **ID canonique :** `0493x13e`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification compressible scripts-only; aucune modification src/include
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Teste la convergence en longueur d’onde de la réponse compressible isotherme quand Ma augmente et traduit la plage qualifiée en besoins de résolution pour Re cible.

**Relations :**
- `BUILDS_ON` → `x13d` — Follow-up longue longueur d’onde et amortissement

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13e_default_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13E_COMPRESSIBLE_MACH_REACH.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13e_Ciso_mach_sweep.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13e_compressible_mach_reach.sh`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13e_longitudinal_velocity_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13e_Ciso_mach_sweep.sh`

### `x13f` — Optimisation locale du transport G08

- **Clé unique :** `0493x13f`
- **ID canonique :** `0493x13f`
- **Nature / domaine :** `CALIBRATOR` / `TRANSPORT_SURFACE`
- **Statut :** Optimisation/calibration du fluide, pas optimisation de code
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Balaye angle et lambda/h à gamma=8 puis requalifie les meilleurs candidats à plusieurs longueurs d’onde sans supposer le proxy SRD exact.

**Relations :**
- `BUILDS_ON` → `x13d` — Follow-up longue longueur d’onde et amortissement

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13f_S1_design_cost.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13F_G08_LOCAL_TRANSPORT_OPTIMIZATION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13f_S1_G08_local_screen.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13f_S2_G08_local_qualification.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13f_G08_local_transport_optimization.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13f_S1_G08_local_screen.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13f_S2_G08_local_qualification.sh`

### `x13g` — Qualification de reproductibilité statistique GPU

- **Clé unique :** `0493x13g`
- **ID canonique :** `0493x13g`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Règle méthodologique de reproductibilité; aucune modification solveur
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Compare répétitions byte-identiques et réalisations indépendantes pour montrer que la trajectoire GPU n’est pas une preuve bit-à-bit et imposer l’analyse en ensemble.

**Relations :**
- `BUILDS_ON` → `x13f` — Optimisation locale du transport G08

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13g_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13G_G08_REPRODUCIBILITY.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13g_H_reproducibility.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13g_H_reproducibility.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13g_H_reproducibility.sh`

### `x13h` — Point liquide de référence G08-120-L072

- **Clé unique :** `0493x13h`
- **ID canonique :** `0493x13h`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Référence liquide qualifiée; rollback final vers le tag surf-tension-qualified-x13h-20260831
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`
- **Tag :** `surf-tension-qualified-x13h-20260831`

Consolide gamma=8, angle 120°, lambda/h=0.72 comme fluide économique de référence; ce point est ensuite la base du tag surface-libre qualifié 7655b81.

**Notes.** Le commit d’introduction est distingué du commit/tag 7655b81 qui qualifie ensuite la chaîne surface libre.

**Relations :**
- `BUILDS_ON` → `x13h-A` — Acoustique du point final lambda/h=0.72
- `BUILDS_ON` → `x13h-B` — Viscosité et dépendance en densité du point final
- `BUILDS_ON` → `x13h-C` — Enveloppe Mach du point final

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13h_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13H_L072_QUALIFICATION.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13h_A_Cdamp_L072.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13h_B_density_transport_L072.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13h_A_Cdamp_L072.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13h_B_density_transport_L072.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13h_C_Mach_L072.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13h_L072_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13h_longitudinal_velocity_state.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13h_shear_state.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13h_sound_state_fractional.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13h_A_Cdamp_L072.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13h_B_density_transport_L072.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13h_C_Mach_L072.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13h_master.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13j_young_laplace_x13h_s120.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13l_oscillating_drop_n3_x13h.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13m_oscillating_drop_n4_x13h.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x13h.sh`

### `x13h-A` — Acoustique du point final lambda/h=0.72

- **Clé unique :** `0493x13h-a`
- **ID canonique :** `0493x13h-a`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Sous-qualification constitutive A du fluide final
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Qualifie le mode longitudinal amorti du point gamma=8, angle 120°, lambda/h=0.72 avec amplitudes multiples et bootstrap.

**Relations :**
- `BUILDS_ON` → `x13g` — Qualification de reproductibilité statistique GPU

### `x13h-B` — Viscosité et dépendance en densité du point final

- **Clé unique :** `0493x13h-b`
- **ID canonique :** `0493x13h-b`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Sous-qualification constitutive B du fluide final
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Cartographie la viscosité transverse du point lambda/h=0.72 versus gamma et longueur d’onde avec estimateur ensemble.

**Relations :**
- `BUILDS_ON` → `x13g` — Qualification de reproductibilité statistique GPU

### `x13h-C` — Enveloppe Mach du point final

- **Clé unique :** `0493x13h-c`
- **ID canonique :** `0493x13h-c`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Sous-qualification constitutive C du fluide final
- **Confiance :** `A`
- **Date :** `2026-08-27`
- **Commit :** `15aa7c3c41196dab5fa3c32fef676e8c3cfcd0ca`

Teste Ma=0.2,0.5,0.7,0.9 sur deux longueurs d’onde avec les coefficients A/B du même fluide.

**Relations :**
- `BUILDS_ON` → `x13g` — Qualification de reproductibilité statistique GPU

### `x13i` — Loi d’échelle en kBT du fluide x13h

- **Clé unique :** `0493x13i`
- **ID canonique :** `0493x13i`
- **Nature / domaine :** `CALIBRATOR` / `TRANSPORT_SURFACE`
- **Statut :** Calibration de similitude thermique du fluide x13h; scripts-only
- **Confiance :** `A`
- **Date :** `2026-08-28`
- **Commit :** `b532f5e446b5b66ef2070ef7270117cd5656a80b`

À gamma, angle et lambda/h fixes, teste les lois c_s, nu_T et D_self proportionnelles à sqrt(kBT), ainsi que l’invariance de H_h et Sc.

**Relations :**
- `BUILDS_ON` → `x13h` — Point liquide de référence G08-120-L072
- `REFERENCES` → `x13h` — Point liquide de référence G08-120-L072

### `x13j` — Calibrateur transport autonome + qualification Young–Laplace x13h

- **Clé unique :** `0493x13j`
- **ID canonique :** `0493x13j`
- **Nature / domaine :** `CALIBRATOR` / `TRANSPORT_SURFACE`
- **Statut :** Double rôle historique documenté; aucune nouvelle physique C++
- **Confiance :** `A`
- **Date :** `2026-08-28`
- **Commit :** `b532f5e446b5b66ef2070ef7270117cd5656a80b`

Le label x13j a deux usages historiques attestés dans le même lignage Git: calibrateur autonome SRC/Q6/Q6-G-F (nu_T,c_s,nu_L,Dself) et runner Young–Laplace du fluide x13h réutilisant x12yl.

**Notes.** Conflit/co-usage de label conservé explicitement; aucune identité artificielle x13j1/x13j2 n’est créée.

**Relations :**
- `BUILDS_ON` → `x13i` — Loi d’échelle en kBT du fluide x13h
- `REFERENCES` → `x12yl` — Calibrateur mécanique/statique de tension superficielle
- `REFERENCES` → `x13h` — Point liquide de référence G08-120-L072

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13j_src_transport.py`
- `ASSOCIATED_WITH` — `scripts/calibrate_src_transport_0493x13j.sh`
- `ASSOCIATED_WITH` — `scripts/check_0493x13j_src_transport.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13j_young_laplace_x13h_s120.sh`

### `x13k` — Qualification goutte oscillante n=2

- **Clé unique :** `0493x13k`
- **ID canonique :** `0493x13k`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification dynamique historique du point surface libre
- **Confiance :** `A`
- **Date :** `2026-08-29`
- **Commit :** `7655b81b1b2fd16eecefa8d8b3bebac4cd9f87f1`

Qualifie dynamiquement la chaîne surface libre sur le mode azimutal n=2 du fluide x13h, avec observable quadrupolaire robuste.

**Relations :**
- `BUILDS_ON` → `x13h` — Point liquide de référence G08-120-L072
- `REFERENCES` → `x13h` — Point liquide de référence G08-120-L072

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13k_oscillating_drop_2d.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x13k_oscillating_drop_2d.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13k_oscillating_drop_2d.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13k_oscillating_drop_2d.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`

### `x13l` — Qualification goutte oscillante n=3

- **Clé unique :** `0493x13l`
- **ID canonique :** `0493x13l`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification dynamique historique
- **Confiance :** `A`
- **Date :** `2026-08-29`
- **Commit :** `7655b81b1b2fd16eecefa8d8b3bebac4cd9f87f1`

Étend la qualification dynamique à n=3 avec observable d’ordre trois reconstruit hors ligne.

**Relations :**
- `BUILDS_ON` → `x13k` — Qualification goutte oscillante n=2

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13l_oscillating_drop_n3_state.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13l_oscillating_drop_n3_state.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13l_oscillating_drop_n3_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13l_n3_multiseed10.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13l_oscillating_drop_n3_x13h.sh`

### `x13m` — Qualification goutte oscillante n=4

- **Clé unique :** `0493x13m`
- **ID canonique :** `0493x13m`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification dynamique historique
- **Confiance :** `A`
- **Date :** `2026-08-29`
- **Commit :** `7655b81b1b2fd16eecefa8d8b3bebac4cd9f87f1`

Étend la qualification dynamique à n=4 avec observable d’ordre quatre reconstruit hors ligne.

**Relations :**
- `BUILDS_ON` → `x13l` — Qualification goutte oscillante n=3

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13m_oscillating_drop_n4_state.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13m_oscillating_drop_n4_state.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13m_oscillating_drop_n4_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13m_n4_multiseed10.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13m_oscillating_drop_n4_x13h.sh`

### `x13n` — Benchmark Taylor–Culick 2-D

- **Clé unique :** `0493x13n`
- **ID canonique :** `0493x13n`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Limite dynamique connue; référence de rollback G_TC≈0.795 à sigma=10000
- **Confiance :** `A`
- **Date :** `2026-08-29`
- **Commit :** `7655b81b1b2fd16eecefa8d8b3bebac4cd9f87f1`

Mesure la rétraction symétrique d’une nappe résolue; met en évidence G_TC trop faible malgré une résultante capillaire locale du rim proche de 2 sigma.

**Relations :**
- `BUILDS_ON` → `x13h` — Point liquide de référence G08-120-L072
- `REFERENCES` → `x13k` — Qualification goutte oscillante n=2
- `REFERENCES` → `x13l` — Qualification goutte oscillante n=3
- `REFERENCES` → `x13m` — Qualification goutte oscillante n=4

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13n_rim_momentum.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13n_rim_traction.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13n_rim_traction_v2.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13n_taylor_culick_sheet_2d.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x13n_taylor_culick_sheet_2d.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13n_rim_momentum.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13n_rim_traction.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13n_rim_traction_v2.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13n_taylor_culick_sheet_2d.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13n_taylor_culick_sheet_2d.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_multiseed3.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_sheet_2d_no_kinetic_closure.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_sheet_2d_specular.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x10v_off.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x13h.sh`

### `x13o` — Ablation swap normal-only

- **Clé unique :** `0493x13o`
- **ID canonique :** `0493x13o`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Ablation OFF production; le tag qualifié utilise le swap full-vector x10v
- **Confiance :** `A`
- **Date :** `2026-08-29`
- **Commit :** `7655b81b1b2fd16eecefa8d8b3bebac4cd9f87f1`

Ablation de x10v qui échange seulement la composante normale locale entre masses égales et conserve la tangentielle; flag présent au point qualifié mais OFF dans la chaîne de production.

**Relations :**
- `BUILDS_ON` → `x10v` — Swap local full-vector one-for-one
- `REFERENCES` → `x10v` — Swap local full-vector one-for-one
- `REFERENCES` → `x13n` — Benchmark Taylor–Culick 2-D

### `x13p` — Zone de crossing libre autour de l’interface

- **Clé unique :** `0493x13p`
- **ID canonique :** `0493x13p`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Expérience post-x13n; amélioration TC partielle mais non retenue
- **Confiance :** `A`
- **Date :** `2026-08-30`

Ablation qui désactive l’action position/vitesse one-for-one à l’intérieur d’une zone de quelques cellules de la paroi cinétique Q2, tout en gardant la relocalisation héritée hors zone.

**Notes.** Le log du 30/08 atteste explicitement cells=0/2 et la sémantique inside-zone:no-position/no-velocity-action.

**Relations :**
- `BUILDS_ON` → `x13o` — Ablation swap normal-only
- `REFERENCES` → `x13n` — Benchmark Taylor–Culick 2-D

### `x13q` — Turnover des orphelins de fermeture cinétique

- **Clé unique :** `0493x13q`
- **ID canonique :** `0493x13q`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Expérience de confinement post-x13n; absente du commit qualifié 7655b81
- **Confiance :** `A`
- **Date :** `2026-08-31`

Ablation post-x13p ajoutant un traitement dédié des particules orphelines de la fermeture cinétique via MPCD_X10_KINETIC_INTERFACE_ORPHAN_TURNOVER.

**Notes.** Sémantique détaillée conservée par le README/patcher historiques; V4.20 n’en déduit pas davantage que ce qu’attestent le nom et le flag.

**Relations :**
- `BUILDS_ON` → `x13p` — Zone de crossing libre autour de l’interface
- `REFERENCES` → `x13n` — Benchmark Taylor–Culick 2-D
- `REFERENCES` → `x13p` — Zone de crossing libre autour de l’interface

### `x13r` — Refroidissement direct des cellules interfaciales

- **Clé unique :** `0493x13r`
- **ID canonique :** `0493x13r`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Rejetée: fermeture discontinue et dépendante du masque; supersédée par x13t
- **Confiance :** `A`
- **Date :** `2026-08-31`

Ablation imposant un refroidissement quasi-nul sur les cellules immédiatement identifiées interfaciales afin d’isoler le rôle de l’agitation thermique dans le déficit Taylor–Culick.

**Relations :**
- `BUILDS_ON` → `x13n` — Benchmark Taylor–Culick 2-D
- `REFERENCES` → `x13t` — Refroidissement progressif unifié
- `SUPERSEDED_BY` → `x13t` — Refroidissement progressif unifié

### `x13s` — Refroidissement interfacial anisotrope

- **Clé unique :** `0493x13s`
- **ID canonique :** `0493x13s`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Rejetée comme fermeture générale; supersédée par x13t
- **Confiance :** `A`
- **Date :** `2026-08-31`

Ablation supprimant surtout l’agitation thermique normale tout en gardant une fraction tangentielle et une profondeur de couche configurable.

**Relations :**
- `BUILDS_ON` → `x13r` — Refroidissement direct des cellules interfaciales
- `REFERENCES` → `x13t` — Refroidissement progressif unifié
- `SUPERSEDED_BY` → `x13t` — Refroidissement progressif unifié

### `x13t` — Refroidissement progressif unifié

- **Clé unique :** `0493x13t`
- **ID canonique :** `0493x13t`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Expérience causale rejetée comme chemin général après x13zd
- **Confiance :** `A`
- **Date :** `2026-08-31`

Remplace les seuils abrupts x13r/s par fT=min(fGamma,fthin), combinant distance à interface et loi d’épaisseur locale; améliore G_TC mais ne ferme pas la population diffuse.

**Notes.** À RGamma/h=4, la campagne historique améliore G_TC mais laisse une population diffuse; le chemin est ensuite invalidé sur gouttes fermées.

**Relations :**
- `BUILDS_ON` → `x13s` — Refroidissement interfacial anisotrope
- `REFERENCES` → `x13r` — Refroidissement direct des cellules interfaciales
- `REFERENCES` → `x13zd` — Validation croisée décisive et rollback

### `x13u` — Combinaison x13t + relocalisation one-for-one

- **Clé unique :** `0493x13u`
- **ID canonique :** `0493x13u`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Expérimental/rejeté; x13u fixe la combinaison mais pas la fermeture générale
- **Confiance :** `A`
- **Date :** `2026-08-31`

Gate expérimental combinant le champ thermique x13t avec la relocalisation x10u sous rétention dure; ses fixes corrigent la portée et la conservation du champ x13t dans l’orchestration.

**Relations :**
- `BUILDS_ON` → `x13t` — Refroidissement progressif unifié
- `REFERENCES` → `x10u` — Relocalisation conservative one-for-one
- `REFERENCES` → `x13t` — Refroidissement progressif unifié

### `x13v` — Séparation position one-for-one / swap vitesse

- **Clé unique :** `0493x13v`
- **ID canonique :** `0493x13v`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Expérimental/rejeté; outil causal de séparation de x10u et x10v
- **Confiance :** `A`
- **Date :** `2026-08-31`

Sépare explicitement la relocalisation spatiale x10u du swap full-vector x10v afin de mesurer leurs contributions respectives sous x13t.

**Relations :**
- `BUILDS_ON` → `x13u` — Combinaison x13t + relocalisation one-for-one
- `REFERENCES` → `x10u` — Relocalisation conservative one-for-one
- `REFERENCES` → `x10v` — Swap local full-vector one-for-one
- `REFERENCES` → `x13t` — Refroidissement progressif unifié

### `x13w` — Escape → inactive → reseed local

- **Clé unique :** `0493x13w`
- **ID canonique :** `0493x13w`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Rejeté: contraction artificielle du support de phase
- **Confiance :** `A`
- **Date :** `2026-08-31`

Convertit un crossing sortant confirmé en slot inactif puis recrée une particule de même masse/type côté liquide; le mécanisme ferme les fuites mais transporte artificiellement le support vers l’intérieur.

**Relations :**
- `BUILDS_ON` → `x13t` — Refroidissement progressif unifié
- `REFERENCES` → `x13v` — Séparation position one-for-one / swap vitesse

### `x13w-fix3` — Reseed sur moyenne pré-échappement

- **Clé unique :** `0493x13w-fix3`
- **ID canonique :** `0493x13w-fix3`
- **Nature / domaine :** `FIX` / `TRANSPORT_SURFACE`
- **Statut :** Correctif utilisé dans x13zd; mécanisme x13w reste invalidé physiquement
- **Confiance :** `A`
- **Date :** `2026-08-31`

Corrige le biais de vitesse de reseed en utilisant une moyenne locale pré-échappement plutôt que la moyenne survivante après sélection des vitesses sortantes.

**Relations :**
- `FIXES` → `x13w` — Escape → inactive → reseed local
- `REFERENCES` → `x13w` — Escape → inactive → reseed local
- `REFERENCES` → `x13zd` — Validation croisée décisive et rollback

### `x13x` — Sweep de rétention probabiliste

- **Clé unique :** `0493x13x`
- **ID canonique :** `0493x13x`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Aucun compromis robuste vitesse/confinement; non production
- **Confiance :** `A`
- **Date :** `2026-08-31`

Reconnecte la fraction de rétention r pour interpoler entre hard retention et crossing naturel, puis mesure conjointement G_TC et fuite/diffusion du support.

**Relations :**
- `BUILDS_ON` → `x13w-fix3` — Reseed sur moyenne pré-échappement

### `x13z` — Exploration de changements de grille

- **Clé unique :** `0493x13z`
- **ID canonique :** `0493x13z`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Gains séduisants mais non suffisants pour validation
- **Confiance :** `A`
- **Date :** `2026-08-31`

Teste des représentations de grille alternatives qui peuvent augmenter G_TC mais changent aussi bruit/statistique et physique subgrid; aucun cas ne constitue à lui seul une convergence.

**Relations :**
- `BUILDS_ON` → `x13x` — Sweep de rétention probabiliste

### `x13za` — Comparaison gouttes oscillantes entre grilles

- **Clé unique :** `0493x13za`
- **ID canonique :** `0493x13za`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Diagnostic de dépendance de grille de la dynamique capillaire
- **Confiance :** `A`
- **Date :** `2026-08-31`

Compare n=2/3/4 sur grilles 256 et 320 avec la chaîne qualifiée pour isoler l’effet de représentation avant d’attribuer le gain Taylor–Culick à une fermeture.

**Relations :**
- `BUILDS_ON` → `x13z` — Exploration de changements de grille
- `REFERENCES` → `x13k` — Qualification goutte oscillante n=2

### `x13zb` — Comparaison Young–Laplace entre grilles

- **Clé unique :** `0493x13zb`
- **ID canonique :** `0493x13zb`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Diagnostic; la régression brute forte-sigma n’est pas une mesure physique robuste de sigma_eff
- **Confiance :** `A`
- **Date :** `2026-08-31`

Tente une comparaison mécanique Young–Laplace entre représentations de grille et révèle une forte sensibilité du protocole de baseline/pression à forte sigma.

**Relations :**
- `BUILDS_ON` → `x13za` — Comparaison gouttes oscillantes entre grilles
- `REFERENCES` → `x12yl` — Calibrateur mécanique/statique de tension superficielle

### `x13zb2` — Baseline sigma=0 courte pour comparaison de grille

- **Clé unique :** `0493x13zb2`
- **ID canonique :** `0493x13zb2`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Essai de protocole; ne ferme pas le biais de baseline
- **Confiance :** `A`
- **Date :** `2026-08-31`

Sous-étape de protocole qui raccourcit la baseline sigma=0 afin de limiter la dérive géométrique de la goutte libre pendant la comparaison Young–Laplace.

**Relations :**
- `BUILDS_ON` → `x13zb` — Comparaison Young–Laplace entre grilles

### `x13zb3` — Audit de stabilité et rebaseline Young–Laplace

- **Clé unique :** `0493x13zb3`
- **ID canonique :** `0493x13zb3`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Diagnostic de baseline; motive l’abandon de la référence libre longue sigma=0
- **Confiance :** `A`
- **Date :** `2026-08-31`

Analyse la stabilité des baselines et relance uniquement les références nécessaires; met en évidence qu’une longue goutte sigma=0 n’est pas un état mécanique apparié stable.

**Relations :**
- `BUILDS_ON` → `x13zb2` — Baseline sigma=0 courte pour comparaison de grille

### `x13zc` — Mécanique statique de goutte versus grille

- **Clé unique :** `0493x13zc`
- **ID canonique :** `0493x13zc`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Diagnostic de représentation; R_eff plus petit sur grille fine explique une part majeure du shift fréquentiel
- **Confiance :** `A`
- **Date :** `2026-08-31`

Analyse rayon effectif, courbure active, clipping et métriques mécaniques sur les deux grilles pour expliquer les décalages de fréquence et séparer géométrie de tension effective.

**Relations :**
- `BUILDS_ON` → `x13zb3` — Audit de stabilité et rebaseline Young–Laplace

### `x13zd` — Validation croisée décisive et rollback

- **Clé unique :** `0493x13zd`
- **ID canonique :** `0493x13zd`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Invalide x13t+x13w comme chemin général; point de production ramené à surf-tension-qualified-x13h-20260831
- **Confiance :** `A`
- **Date :** `2026-08-31`

Teste la meilleure fermeture expérimentale x13t+x13w-fix3 sur gouttes oscillantes n=2/3/4 et deux grilles; montre contraction du support et dégradation modale, puis motive le retour au tag 7655b81.

**Notes.** Le commit 3daf archive les fichiers expérimentaux après coup; il est enregistré comme preuve, pas comme commit d’introduction.

**Relations :**
- `BUILDS_ON` → `x13w-fix3` — Reseed sur moyenne pré-échappement
- `BUILDS_ON` → `x13zc` — Mécanique statique de goutte versus grille
- `DIAGNOSES` → `x13t` — Refroidissement progressif unifié
- `DIAGNOSES` → `x13w` — Escape → inactive → reseed local
- `REFERENCES` → `x13h` — Point liquide de référence G08-120-L072
- `REFERENCES` → `x13t` — Refroidissement progressif unifié
- `REFERENCES` → `x13w` — Escape → inactive → reseed local
- `REFERENCES` → `x13w-fix3` — Reseed sur moyenne pré-échappement

### `x13ze` — Démonstrations run_ok impact/puddle stabilisées

- **Clé unique :** `0493x13ze`
- **ID canonique :** `0493x13ze`
- **Nature / domaine :** `DEMONSTRATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Démonstration historique stabilisée; pas une nouvelle qualification physique
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `a18d274ba28d0a8ce14432fdc5fa52a132b5410f`

Wrapper commun autour du cas splash historique, figé sur la chaîne surface libre qualifiée x10o+CIC+Q2+x10p/q+x10u+x10v full-vector swap+x12a.

**Relations :**
- `BUILDS_ON` → `x13h` — Point liquide de référence G08-120-L072
- `REFERENCES` → `x10o` — Paroi cinétique Q6 hydrodynamique à enveloppe thermique
- `REFERENCES` → `x10p` — Résolution des recouvrements initiaux
- `REFERENCES` → `x10u` — Relocalisation conservative one-for-one
- `REFERENCES` → `x10v` — Swap local full-vector one-for-one
- `REFERENCES` → `x12a` — Refroidissement thermique local des petites structures

### `x13zf` — Démonstration run_ok dripping qualitative

- **Clé unique :** `0493x13zf`
- **ID canonique :** `0493x13zf`
- **Nature / domaine :** `DEMONSTRATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Démonstration qualitative historique stabilisée; non benchmark quantitatif
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `a18d274ba28d0a8ce14432fdc5fa52a132b5410f`

Réutilise la géométrie/forçage dripping retenus avec la chaîne surface libre qualifiée; montre croissance, pincement, chute et impact sans prétendre calibrer un robinet ni un Weber critique.

**Relations :**
- `BUILDS_ON` → `x13h` — Point liquide de référence G08-120-L072

### `x13zg` — Profil run_ok surface libre qualifié

- **Clé unique :** `0493x13zg`
- **ID canonique :** `0493x13zg`
- **Nature / domaine :** `TOOLING` / `FREE_SURFACE_KINETICS`
- **Statut :** Profil run_ok de référence; chaîne x13h explicitement figée
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `a18d274ba28d0a8ce14432fdc5fa52a132b5410f`

Bibliothèque shell commune qui impose aux démonstrations liquides le point de référence taggé x13h et désactive les fallbacks non qualifiés.

**Relations :**
- `BUILDS_ON` → `x13h` — Point liquide de référence G08-120-L072
- `REFERENCES` → `x13h` — Point liquide de référence G08-120-L072

### `x13zj` — Harmonisation fluide de référence et LiveVis run_ok

- **Clé unique :** `0493x13zj`
- **ID canonique :** `0493x13zj`
- **Nature / domaine :** `TOOLING` / `RUN_OK`
- **Statut :** Harmonisation documentaire/outillage historique attestée par README Git
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `a18d274ba28d0a8ce14432fdc5fa52a132b5410f`

Harmonise la collection run_ok autour du fluide de référence et des conventions de visualisation, sans introduire de nouvelle physique solveur.

### `x13zk` — Checker run_ok à sémantique physique

- **Clé unique :** `0493x13zk`
- **ID canonique :** `0493x13zk`
- **Nature / domaine :** `TOOLING` / `RUN_OK`
- **Statut :** Contrôle sémantique run_ok; aucune nouvelle physique
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `a18d274ba28d0a8ce14432fdc5fa52a132b5410f`

Fait évoluer le checker vers la présence et la cohérence des paramètres physiques requis sans figer les anciennes valeurs littérales locales.

### `x13zl` — Collection run_ok canonique homogène

- **Clé unique :** `0493x13zl`
- **ID canonique :** `0493x13zl`
- **Nature / domaine :** `TOOLING` / `RUN_OK`
- **Statut :** Collection run_ok homogénéisée
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `a18d274ba28d0a8ce14432fdc5fa52a132b5410f`

Remplacement canonique de la collection run_ok par un ensemble homogène fondé sur le fluide de référence; jalon d’outillage historique, pas qualification solveur nouvelle.

### `x13zn` — Nettoyage runner injection

- **Clé unique :** `0493x13zn`
- **ID canonique :** `0493x13zn`
- **Nature / domaine :** `FIX` / `RUN_OK`
- **Statut :** Correctif runner-only attesté; aucune modification solveur
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `a18d274ba28d0a8ce14432fdc5fa52a132b5410f`

Supprime des doublons de configuration et corrige une collision de portée dynamique Bash dans le runner injection; portée outillage seulement.

**Relations :**
- `BUILDS_ON` → `x13zl` — Collection run_ok canonique homogène

### `x14a` — Smoke thermostat deux types

- **Clé unique :** `0493x14a`
- **ID canonique :** `0493x14a`
- **Nature / domaine :** `QUALIFICATION` / `LIQUID_GAS`
- **Statut :** PASS des smokes thermostat deux types
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Vérifie cibles thermiques par type, conservation du moment par type sans rotation SRC et rapport de vitesses thermiques attendu sur le chemin CUDA résident.

### `x14an` — Jet gazeux plan sur bain liquide

- **Clé unique :** `0493x14an`
- **ID canonique :** `0493x14an`
- **Nature / domaine :** `CAMPAIGN` / `LIQUID_GAS`
- **Statut :** Campagne de construction/qualification; aucun PASS physique autonome inféré du runner
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Premier runner application-scale du chargement normal gaz→liquide avec bain, jet supérieur et sorties latérales; x14ai est forcé OFF car le liquide touche des frontières externes.

**Relations :**
- `REFERENCES` → `x14ai` — Fermeture de résultante Q6 appliquée

### `x14ao` — Buse planaire Darcy/chi paramétrable

- **Clé unique :** `0493x14ao`
- **ID canonique :** `0493x14ao`
- **Nature / domaine :** `CAMPAIGN` / `LIQUID_GAS`
- **Statut :** Étape géométrique de campagne; pas de qualification autonome revendiquée
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Insère une buse de longueur finie via le chemin Darcy/Brinkman chi déjà qualifié tout en conservant la chaîne d’interaction x14.

**Relations :**
- `BUILDS_ON` → `x14an` — Jet gazeux plan sur bain liquide

### `x14ap` — Buse Darcy/chi aux défauts de similitude expérimentale

- **Clé unique :** `0493x14ap`
- **ID canonique :** `0493x14ap`
- **Nature / domaine :** `CAMPAIGN` / `LIQUID_GAS`
- **Statut :** Point de similitude de campagne; pas de PASS autonome
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Fixe les défauts géométriques et adimensionnels de la buse en vue d’une comparaison externe, sans modifier la chaîne solveur.

**Relations :**
- `BUILDS_ON` → `x14ao` — Buse planaire Darcy/chi paramétrable

### `x14aq` — Réservoirs gazeux ambiants latéraux

- **Clé unique :** `0493x14aq`
- **ID canonique :** `0493x14aq`
- **Nature / domaine :** `CAMPAIGN` / `LIQUID_GAS`
- **Statut :** Expérience de condition limite; non retenue comme validation autonome
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Teste une segmentation supérieure avec réservoirs hard-density à vitesse moyenne nulle aux extrémités et sorties passives conservées près de la buse.

**Relations :**
- `BUILDS_ON` → `x14ap` — Buse Darcy/chi aux défauts de similitude expérimentale

### `x14ar` — Atmosphère hard-density sur le dessus hors buse

- **Clé unique :** `0493x14ar`
- **ID canonique :** `0493x14ar`
- **Nature / domaine :** `CAMPAIGN` / `LIQUID_GAS`
- **Statut :** Expérience de condition limite; pas de PASS physique autonome
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Variante de condition limite où la zone supérieure accessible hors parois de buse est reconstruite comme atmosphère; test causal de la pression gazeuse ambiante.

**Relations :**
- `BUILDS_ON` → `x14ap` — Buse Darcy/chi aux défauts de similitude expérimentale

### `x14as` — Buse à sorties larges, pression gaz comme covariable

- **Clé unique :** `0493x14as`
- **ID canonique :** `0493x14as`
- **Nature / domaine :** `CAMPAIGN` / `LIQUID_GAS`
- **Statut :** Topologie retenue pour x14at; pression gaz traitée comme covariable mesurée
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Fige la topologie à sorties larges qui fonctionne; la pression gazeuse n’est pas forcée à sa référence initiale mais mesurée comme condition génératrice de la cavité.

**Relations :**
- `BUILDS_ON` → `x14ap` — Buse Darcy/chi aux défauts de similitude expérimentale
- `REFERENCES` → `x14at` — Validation externe Sato Stage-A

### `x14at` — Validation externe Sato Stage-A

- **Clé unique :** `0493x14at`
- **ID canonique :** `0493x14at`
- **Nature / domaine :** `QUALIFICATION` / `LIQUID_GAS`
- **Statut :** Validation externe ciblée: H/D=0.8 et Fr_m≈0.49–0.59 à 4.8–9.9% de Sato; H/D=1.7 REVIEW; pas de similitude dynamique complète
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Compare la profondeur de cavité d’un jet gazeux incident à Sato et al. en similitude partielle géométrie/Bo_D/Fr_m mesuré.

**Relations :**
- `BUILDS_ON` → `x14as` — Buse à sorties larges, pression gaz comme covariable

### `x14au` — Qualification viscosité associée au cas Sato

- **Clé unique :** `0493x14au`
- **ID canonique :** `0493x14au`
- **Nature / domaine :** `CALIBRATOR` / `LIQUID_GAS`
- **Statut :** Liquide primaire INVALID; gaz REVIEW; cohérence d’échelle 2σ diagnostique seulement
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Réévalue les viscosités liquide et gaz aux échelles primaire et application pour propager Re/Oh dans l’interprétation de x14at.

**Relations :**
- `DIAGNOSES` → `x14at` — Validation externe Sato Stage-A
- `REFERENCES` → `x14at` — Validation externe Sato Stage-A

### `x14av` — Démonstration atomiseur air-assisté

- **Clé unique :** `0493x14av`
- **ID canonique :** `0493x14av`
- **Nature / domaine :** `DEMONSTRATION` / `LIQUID_GAS`
- **Statut :** DEMONSTRATION_DIAGNOSTIC_ONLY; aucune qualification physique d’atomisation
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672`

Assemble un jet liquide et deux arrivées gazeuses avec diagnostics de pénétration, largeur et composants détachés. Le runner/analyseur se déclare explicitement démonstration diagnostique, sans critère PASS/FAIL d’atomisation physique.

**Relations :**
- `BUILDS_ON` → `x14v` — Kick cinétique excédentaire

### `x14b` — Qualification thermostat avec collision SRC active

- **Clé unique :** `0493x14b`
- **ID canonique :** `0493x14b`
- **Nature / domaine :** `QUALIFICATION` / `LIQUID_GAS`
- **Statut :** PASS active-collision exact-grid
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Qualification dynamique sur grille non décalée afin de reconstruire exactement les cellules du thermostat final.

### `x14c` — Probe thermostat en grille décalée

- **Clé unique :** `0493x14c`
- **ID canonique :** `0493x14c`
- **Nature / domaine :** `QUALIFICATION` / `LIQUID_GAS`
- **Statut :** PASS production-like shifted-grid probe
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Probe production-like avec collision SRC, signe aléatoire et grid shift; contrôle exactement les invariants accessibles et rapporte la température apparente globale.

### `x14e` — Qualification thermostat sur chemin SRC de production

- **Clé unique :** `0493x14e`
- **ID canonique :** `0493x14e`
- **Nature / domaine :** `QUALIFICATION` / `LIQUID_GAS`
- **Statut :** PASS chemin SRC production résident
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Vérifie le thermostat séparé par type après collision SRC commune sur l’état particulaire/cellulaire CUDA résident partagé.

**Relations :**
- `QUALIFIES` → `x14d` — Collision commune + thermostats séparés

### `x14f` — Qualification exacte thermostat sur src-q6-g-f

- **Clé unique :** `0493x14f`
- **ID canonique :** `0493x14f`
- **Nature / domaine :** `QUALIFICATION` / `LIQUID_GAS`
- **Statut :** PASS x14f-fix1 exact src-q6-g-f
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Audit exact par cellule du thermostat séparé par type sur le chemin liquide/gaz src-q6-g-f, avec grid shift volontairement désactivé pour la métrologie.

**Relations :**
- `QUALIFIES` → `x14d` — Collision commune + thermostats séparés

### `x14i` — Qualification finale thermostat src-q6-g-f avec grid shift

- **Clé unique :** `0493x14i`
- **ID canonique :** `0493x14i`
- **Nature / domaine :** `QUALIFICATION` / `LIQUID_GAS`
- **Statut :** PASS production shifted-grid resident species thermostat
- **Confiance :** `A`
- **Date :** `2026-09-01`
- **Commit :** `c3107ec1e486ce1c5b9829c4a7a2473c16438908`

Reconstitue les cellules de collision SRC décalées depuis l’audit résident et ferme la qualification production du bridge x14g.

**Relations :**
- `QUALIFIES` → `x14g` — Cellules exactes post-stream/grid-shift
- `REFERENCES` → `x14g` — Cellules exactes post-stream/grid-shift

### `x14p` — Audit offline alpha/volume gazeux accessible

- **Clé unique :** `0493x14p`
- **ID canonique :** `0493x14p`
- **Nature / domaine :** `DIAGNOSTIC` / `LIQUID_GAS`
- **Statut :** Diagnostic offline; aucune loi CUDA proposée à ce stade
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Teste hors solveur si le déficit de comptage gazeux sur cellules de trace est expliqué par la fraction de volume accessible dérivée des champs alpha existants.

### `x14q` — Fit offline de fraction de volume accessible

- **Clé unique :** `0493x14q`
- **ID canonique :** `0493x14q`
- **Nature / domaine :** `DIAGNOSTIC` / `LIQUID_GAS`
- **Statut :** Diagnostic offline; explicitement pas une proposition CUDA
- **Confiance :** `A`
- **Date :** `2026-09-02`
- **Commit :** `20a59200575ca6ffc1e23e7d9211594cf24fe2ec`

Compare une petite famille de lois identité/shift/scale/affine/power sur les échantillons x14p pour diagnostiquer le biais de pression interfacial.

**Relations :**
- `BUILDS_ON` → `x14p` — Audit offline alpha/volume gazeux accessible
- `REFERENCES` → `x14p` — Audit offline alpha/volume gazeux accessible

### `x2` — Diagnostic liquide plein : force appliquée avant une projection Q6 trop tardive

- **Clé unique :** `0493x2`
- **ID canonique :** `0493x2`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic causal; mène directement à x3
- **Confiance :** `A`

Isole un liquide mono-espèce entièrement rempli dans la boîte fermée sous gravité. Le Q6 common maintient une faible divergence post-collision, mais le kick-and-drift historique déplace les particules avant cette projection; le déplacement déterministe d'ordre g*dt^2 s'accumule au mur inférieur et explique la lente sédimentation observée.

**Notes.** Le profil liquid-only est ajouté au générateur x0. Cas de référence utilisé ensuite par x3/x4a/x4b : boîte fermée, resampling OFF, gravité gY=-0.5 et dt=0.005 dans la campagne historique.

**Relations :**
- `BUILDS_ON` → `x1` — Chemin de frontières closed-box CUDA résident

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x2_liquid_only_q6.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x2_liquid_only_q6_common.sh`

### `x3` — Q6-g force-aware — preuve de concept prestream à deux solves

- **Clé unique :** `0493x3`
- **ID canonique :** `0493x3`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Preuve de concept validant la cause; supplantée par x4a
- **Confiance :** `A`

Introduit q6ForceProjectionMode=prestream : la force est appliquée à la vitesse résidente, cette vitesse tentative est projetée par Q6 avant le streaming, puis le solve Q6 post-collision historique est conservé. Le chemin démontre que la vitesse de transport, et non seulement la vitesse post-collision, doit satisfaire la contrainte incompressible.

**Notes.** Mode opt-in limité historiquement au CUDA Q6, périodique ou closed-box statique, sans resampling/open/Darcy/immersed/capacity. Le contrôle TG à force nulle impose la neutralité et le liquide fermé vérifie la suppression de la sédimentation g*dt^2.

**Relations :**
- `BUILDS_ON` → `x2` — Diagnostic liquide plein : force appliquée avant une projection Q6 trop tardive
- `IMPLEMENTS` → `Q6-g` — Q6 force-aware
- `SUPERSEDED_BY` → `x4a` — Q6-g prestream_single — un solve Q6 par pas forcé

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X3_Q6_FORCE_PRESTREAM_TEST.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x3_q6_force_projection_tg.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x3_liquid_only_q6_force_prestream.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x3_q6_force_projection_tg.sh`

### `x4a` — Q6-g prestream_single — un solve Q6 par pas forcé

- **Clé unique :** `0493x4a`
- **ID canonique :** `0493x4a`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Référence mono-solve; supplantée par la fusion x4b
- **Confiance :** `A`

Ajoute q6ForceProjectionMode=prestream_single. Après force -> Q6 -> streaming, collision SRC et thermostat relatif ne déplacent pas les particules; le solve post-collision est donc omis et la vitesse issue de collision est projetée au début du pas suivant avant tout nouveau transport.

**Notes.** Conserve le mode x3 à deux solves comme référence. La campagne liquide fermée historique réduit le coût d'environ 142.9 s à 95.5 s sur 1000 pas sans réintroduire la dérive gravitaire.

**Relations :**
- `BUILDS_ON` → `x3` — Q6-g force-aware — preuve de concept prestream à deux solves
- `REFERENCES` → `x4b` — Q6-g prestream_single_fused — fusion CUDA force + projection
- `SUPERSEDED_BY` → `x4b` — Q6-g prestream_single_fused — fusion CUDA force + projection

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X4A_Q6_FORCE_SINGLE_SOLVE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x4a_q6_force_single_tg.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x4a_liquid_only_q6_force_single.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x4a_q6_force_single_tg.sh`

### `x4b` — Q6-g prestream_single_fused — fusion CUDA force + projection

- **Clé unique :** `0493x4b`
- **ID canonique :** `0493x4b`
- **Nature / domaine :** `PERF` / `Q6_GF`
- **Statut :** Séquençage temporel Q6-g de référence pour la suite de 0493x
- **Confiance :** `A`

Ajoute q6ForceProjectionMode=prestream_single_fused : le dépôt CUDA construit directement le moment tentative m(v+a dt), le solveur Q6 projette ce champ, puis un même passage particulaire applique la force physique et la correction Q6 avant streaming. Le momentum apporté par la force reste distinct de la correction de momentum Q6.

**Notes.** Supprime le dernier passage particulaire dédié au kick tout en gardant x4a comme référence physique/numérique. En contrôle historique, environ 91.9 s/1000 pas et stabilité sur 5000 pas.

**Relations :**
- `BUILDS_ON` → `x4a` — Q6-g prestream_single — un solve Q6 par pas forcé

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X4B_Q6_FORCE_CUDA_FUSION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x4b_q6_force_fusion_tg.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x4b_liquid_only_q6_force_fused.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x4b_q6_force_fusion_tg.sh`

### `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli

- **Clé unique :** `0493x5a`
- **ID canonique :** `0493x5a`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Première fermeture liquide-vide; support numérique encore assimilé à l'interface
- **Confiance :** `A`

Conserve le séquençage prestream_single_fused de x4b et introduit speciesQ6Mode=free_surface_masked pour une unique espèce liquide projetée. Le support de pression est construit à partir du remplissage absolu mass/referenceCellMass; une face active/inactive impose encore une pression de jauge nulle à demi-maille, avec le facteur deux correspondant dans le Laplacien et la correction de vitesse.

**Notes.** Cas initial volontairement étroit : liquide horizontal partiel dans une boîte fermée statique, gaz absent, resampling/Darcy/virial/open/immersed OFF. Le runner historique utilise typiquement speciesQ6MinOccupancyFraction=0.25 comme seuil de support brut.

**Relations :**
- `BUILDS_ON` → `x4b` — Q6-g prestream_single_fused — fusion CUDA force + projection
- `REFERENCES` → `x4b` — Q6-g prestream_single_fused — fusion CUDA force + projection

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x5a_partial_liquid.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x5a_nonregression.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x5a_partial_liquid_free_surface.sh`

### `x5a2` — Qualification dam-break liquide-vide du free_surface_masked

- **Clé unique :** `0493x5a2`
- **ID canonique :** `0493x5a2`
- **Nature / domaine :** `QUALIFICATION` / `Q6_GF`
- **Statut :** Qualification discriminante; motive la séparation support/interface de x6
- **Confiance :** `A`

Soumet l'opérateur x5a inchangé à une interface fortement déformable : une colonne liquide est libérée dans une boîte fermée autrement vide. Le générateur ajoute le profil empty-outside-column et les diagnostics suivent géométrie, support et solveur. La campagne est robuste avant impact mais la fragmentation post-impact montre que le bord du support numérique ne peut pas être identifié à l'interface physique.

**Notes.** Aucun changement Q6/force/collision/thermostat/BC dans ce jalon. Cas historique : liquid-vacuum, free_surface_masked, prestream_single_fused, gaz absent.

**Relations :**
- `BUILDS_ON` → `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli
- `DIAGNOSES` → `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli
- `QUALIFIES` → `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli
- `REFERENCES` → `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X5A2_DYNAMIC_FREE_SURFACE_DAM_BREAK.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x5a2_dynamic_free_surface.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x5a2_generator_profiles.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x5a2_dynamic_free_surface_dam_break.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x5a2_nonregression.sh`

### `x5b` — Qualification liquide-gaz : Q6-g liquide et gaz compressible explicite

- **Clé unique :** `0493x5b`
- **ID canonique :** `0493x5b`
- **Nature / domaine :** `QUALIFICATION` / `Q6_GF`
- **Statut :** Première qualification bi-espèces; couplage gaz-liquide encore collisionnel côté pression
- **Confiance :** `A`

Ajoute la première qualification dynamique bi-espèces au-dessus de x5a/x5a2 sans modifier l'opérateur CUDA. Le liquide seul est projeté par free_surface_masked; le gaz est enregistré avec q6StrengthDeclared=0, reçoit la force et participe aux collisions SRC multi-espèces mais reste compressible et ne reçoit aucune correction Q6 directe. À ce stade la pression gazeuse n'est pas injectée dans la condition de pression Q6.

**Notes.** Le cas historique utilise dix particules/cellule dans les deux phases et un rapport de masses 1000. Il constitue un stress-test de gaz fortement stratifié, pas un modèle quantitatif de l'air; il mène au diagnostic EOS gaz x6a.

**Relations :**
- `BUILDS_ON` → `x5a2` — Qualification dam-break liquide-vide du free_surface_masked
- `EXTENDS` → `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli
- `REFERENCES` → `x5a` — Q6-g free_surface_masked — premier liquide partiellement rempli
- `REFERENCES` → `x5a2` — Qualification dam-break liquide-vide du free_surface_masked

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X5B_LIQUID_GAS_FREE_SURFACE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x5b_liquid_gas_free_surface.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x5b_nonregression.sh`

### `x6a` — Diagnostic EOS de pression gazeuse interfaciale

- **Clé unique :** `0493x6a`
- **ID canonique :** `0493x6a`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic EOS préparatoire; aucune rétroaction sur le solveur
- **Confiance :** `A`

Reconstruit, sans modifier l'opérateur Q6, la pression idéale du gaz p_g=N_g kBT/A_cell et le potentiel phi_g=dt*p_g/rho_l,ref sur les faces liquide/non-liquide du support free_surface_masked. Le champ est audité mais n'est pas consommé par la projection; pGamma reste nul.

**Notes.** Agrège les espèces phaseFamily=gas dans chaque cellule. Le diagnostic mesure l'EOS idéale, pas encore le tenseur de contrainte MPCD complet. Introduit le buffer de potentiel gazeux réutilisé physiquement par x6g.

**Relations :**
- `BUILDS_ON` → `x5b` — Qualification liquide-gaz : Q6-g liquide et gaz compressible explicite

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6A_Q6_PHASE_PRESSURE_DIAGNOSTIC.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6a_phase_pressure.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6a_phase_pressure_diagnostic.sh`

### `x6b` — Diagnostic géométrique support Q6 / interface alpha=0.5

- **Clé unique :** `0493x6b`
- **ID canonique :** `0493x6b`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic géométrique; prépare la matérialisation résidente x6c
- **Confiance :** `A`

Reconstruit à cadence sparse un remplissage de phase à partir des masses cellule-espèce et audite support numérique, crossing alpha=0.5, distances sous-maille et normales, sans créer de champ géométrique résident ni modifier l'opérateur. Cette étape formalise la différence entre le carrier Q6 et l'interface physique.

**Notes.** Une seule passe CUDA O(Ncells) aux pas d'audit; aucune passe particulaire et aucun champ O(Ncells) permanent. x6a est volontairement désactivé dans le runner de référence afin d'isoler le coût géométrique.

**Relations :**
- `BUILDS_ON` → `x6a` — Diagnostic EOS de pression gazeuse interfaciale
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6B_PHASE_GEOMETRY_DIAGNOSTIC.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6b_phase_geometry.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6b_phase_geometry_diagnostic.sh`

### `x6c` — Infrastructure résidente du champ de phase alpha

- **Clé unique :** `0493x6c`
- **ID canonique :** `0493x6c`
- **Nature / domaine :** `INFRA` / `Q6_GF`
- **Statut :** Infrastructure géométrique résidente; base des stencils d'interface ultérieurs
- **Confiance :** `A`

Matérialise sur GPU, à chaque solve Q6 free_surface_masked, un champ rawFill issu des masses liquides puis un champ alpha filtré par un stencil cinq points conservatif avec lambda=0.125. À son introduction ces champs sont construits mais non consommés par la projection; ils deviennent ensuite la géométrie commune de x6d/x6e/x6f/x6g.

**Notes.** Deux passes CUDA O(Ncells) par solve. Le lambda=0.125 est fixé dans le code à ce stade. x6f2 corrigera plus tard la source géométrique en bornant rawFill avant filtrage tout en conservant rawFill comme diagnostic non borné.

**Relations :**
- `BUILDS_ON` → `x6b` — Diagnostic géométrique support Q6 / interface alpha=0.5
- `REFERENCES` → `x6d` — Expérience cut-face 1/theta sur le bord du carrier
- `REFERENCES` → `x6e` — Audit topologique de l'interface physique alpha=0.5
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6C_PHASE_GEOMETRY_RESIDENT.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6c_phase_geometry_resident.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6c_phase_geometry_resident.sh`

### `x6d` — Expérience cut-face 1/theta sur le bord du carrier

- **Clé unique :** `0493x6d`
- **ID canonique :** `0493x6d`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Expérience active historique; architecture abandonnée au profit de x6f
- **Confiance :** `A`

Premier consommateur actif du champ alpha résident : sur une face active/inactive du carrier qui encadre alpha=0.5, remplace le facteur demi-maille par la distance sous-maille theta et utilise 1/theta dans l'opérateur/correction; les petits theta gardent le facteur 2 de stabilisation. La pression interfaciale reste pGamma=0.

**Notes.** x6d suppose encore carrier boundary == physical interface. x6e montre que cette identification est fausse dans les géométries déformées. x6d reste un chemin de comparaison, mutuellement exclusif avec x6f.

**Relations :**
- `BUILDS_ON` → `x6c` — Infrastructure résidente du champ de phase alpha
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `SUPERSEDED_BY` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6D_GUARDED_CUTFACE_ZERO_PRESSURE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6d_cutface_geometry.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6d_cutface_geometry_zero_pressure.sh`

### `x6e` — Audit topologique de l'interface physique alpha=0.5

- **Clé unique :** `0493x6e`
- **ID canonique :** `0493x6e`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic architectural décisif; motive pressureMask séparé de x6f
- **Confiance :** `A`

Scanne toutes les faces de grille traversant alpha=0.5 indépendamment du carrier Q6 et classe les crossings active-active, active-inactive et inactive-inactive. Le diagnostic démontre que l'interface physique traverse fréquemment des paires de cellules encore toutes deux dans le carrier et invalide l'architecture cut-face x6d.

**Notes.** Le scan est fusionné dans l'audit sparse x6c et n'ajoute ni champ ni passe de production. Les crossings active-inactive sont séparés selon le côté liquide/externe afin de mesurer exactement la couverture du chemin x6d.

**Relations :**
- `BUILDS_ON` → `x6c` — Infrastructure résidente du champ de phase alpha
- `DIAGNOSES` → `x6d` — Expérience cut-face 1/theta sur le bord du carrier
- `REFERENCES` → `x6d` — Expérience cut-face 1/theta sur le bord du carrier
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6E_PHASE_INTERFACE_TOPOLOGY.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6e_phase_interface_topology.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6e_phase_interface_topology.sh`

### `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5

- **Clé unique :** `0493x6f`
- **ID canonique :** `0493x6f`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Architecture d'interface retenue; géométrie bornée par x6f2 avant x6g
- **Confiance :** `A`

Sépare le carrier de particules du domaine de pression : pressureMask=carrierMask AND alpha>=0.5. Une passe CUDA prépare une fois par solve les coefficients east/north des faces (1 intérieur, 1/theta crossing physique, 2 small-theta, 0 sans couplage), ensuite réutilisés à chaque itération CG. Le pGamma reste nul dans cette étape.

**Notes.** x6f supprime l'identification carrier boundary == pressure boundary réfutée par x6e. Les pertes de carrier sans crossing physique ne deviennent pas des surfaces p=0 artificielles. External BC et Darcy/chi restent gérés par leurs chemins existants.

**Relations :**
- `BUILDS_ON` → `x6e` — Audit topologique de l'interface physique alpha=0.5
- `REFERENCES` → `x6f2` — Correction : géométrie de phase bornée avant filtrage
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6F_PHASE_INTERFACE_STENCIL.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6f_phase_interface_stencil.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6f_phase_interface_stencil.sh`

### `x6f2` — Correction : géométrie de phase bornée avant filtrage

- **Clé unique :** `0493x6f2`
- **ID canonique :** `0493x6f2`
- **Nature / domaine :** `FIX` / `Q6_GF`
- **Statut :** Correctif géométrique actif de la chaîne x6f/x6g
- **Confiance :** `A`

Sépare l'occupation liquide brute, volontairement non bornée, de la géométrie d'interface : le filtre x6c consomme désormais geom0=clamp(rawFill,0,1), puis alpha=geom0+lambda*sum(geom0_nb-geom0). Cette correction empêche une forte sur-occupation voisine de créer artificiellement alpha>0.5 dans une cellule vide.

**Notes.** Aucun champ résident ni passe CUDA supplémentaire. rawFill reste disponible comme diagnostic d'occupation non bornée; seule sa réinterprétation comme source géométrique est corrigée. Avec lambda=0.125, le filtre de geom0 borné reste une combinaison convexe et alpha demeure dans [0,1].

**Relations :**
- `BUILDS_ON` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `FIXES` → `x6c` — Infrastructure résidente du champ de phase alpha
- `FIXES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique

### `x6g` — Condition de pression gazeuse sur l'interface physique

- **Clé unique :** `0493x6g`
- **ID canonique :** `0493x6g`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Couplage pression gaz actif sur interface résidente; base du futur terme capillaire
- **Confiance :** `A`

Réutilise le stencil x6f/x6f2 pour imposer p_l|Gamma=p_g. Sur chaque face alpha=0.5, construit phiGamma=dt*(p_g-p_ref)/rho_l,ref à partir du gaz côté alpha<0.5 (EOS ou pression constante), l'injecte dans le RHS et la correction de face sans modifier la matrice CG. Cette face deviendra ensuite le point d'insertion de p_g+sigma*kappa.

**Notes.** Requiert x6f et la géométrie x6c corrigée par x6f2. Le mode EOS exige au moins une espèce gas. La trace EOS est évaluée dans la cellule côté gaz afin d'éviter une dilution par le liquide d'une cellule mixte.

**Relations :**
- `BUILDS_ON` → `x6f2` — Correction : géométrie de phase bornée avant filtrage
- `EXTENDS` → `x6a` — Diagnostic EOS de pression gazeuse interfaciale
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6f2` — Correction : géométrie de phase bornée avant filtrage

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AA_X6G_FACE_THERMO_TRACTION.md`
- `ASSOCIATED_WITH` — `doc/README_0493X14AD_LOCAL_X6G_FACE_GAUGE_PROJECTION.md`
- `ASSOCIATED_WITH` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `ASSOCIATED_WITH` — `doc/README_0493X7E_X6G_X7D_COMBINATION.md`
- `ASSOCIATED_WITH` — `doc/src_mpcd_env_flags_inventory_consolidated_0493x6g.csv`
- `ASSOCIATED_WITH` — `doc/src_mpcd_params_inventory_consolidated_0493x6g.csv`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6g_phase_gas_pressure.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7e_x6g_x7d_combination.py`
- `ASSOCIATED_WITH` — `scripts/compare_0493x6g_dam_break.py`
- `ASSOCIATED_WITH` — `scripts/compare_0493x6g_states.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6g_final_dam_break.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x6g_phase_gas_pressure.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x6g_validation.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x7e_x6g_x7d_validation.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14o_x6g_constant_pressure_ablation_drop.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14s_x6g_accessible_volume_drop.sh`

### `x6h-A` — Correctif des corrections de faces physiques basses

- **Clé unique :** `0493x6h-a`
- **ID canonique :** `0493x6h-a`
- **Nature / domaine :** `FIX` / `Q6_GF`
- **Statut :** Correctif de reconstruction des faces basses actif dans Q6-g-f
- **Confiance :** `A`

Corrige l'asymétrie du stockage east/north des corrections Q6 : sur une frontière physique basse non périodique, aucune cellule propriétaire west/south n'existe pour fournir la correction de face. x6h-A reconstruit alors cette correction avec la même convention target-before que les faces hautes, sous contrôle du pressureMask, afin de ne pas injecter de kick dans les seules cellules de carrier.

**Notes.** Le correctif agit dans la reconstruction face-vers-cellule après le solve FV et ne change ni la matrice CG ni la définition de l'interface. Il fournit aussi les faces west/south cohérentes dont B1 a besoin pour reconstruire un champ particulaire affine.

**Relations :**
- `BUILDS_ON` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `FIXES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5

### `x6h-B0` — Diagnostic régional de divergence après application aux particules

- **Clé unique :** `0493x6h-b0`
- **ID canonique :** `0493x6h-b0`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic sparse OFF en production; motive la reconstruction B1
- **Confiance :** `A`

Ajoute, uniquement à cadence d'audit, un redépôt post-application et localise la divergence résiduelle par régions bulk, interface, paroi, paroi-interface, coin et coin-interface. Le diagnostic montre où la correction FV projetée perd sa cohérence lorsqu'elle est convertie en incréments particulaires puis redéposée.

**Notes.** Le buffer d'accumulation est alloué paresseusement et la passe supplémentaire n'existe pas lorsque MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0 est désactivé. Ce jalon ne modifie aucune vitesse ni aucun opérateur Q6.

**Relations :**
- `BUILDS_ON` → `x6h-A` — Correctif des corrections de faces physiques basses
- `DIAGNOSES` → `x6h-A` — Correctif des corrections de faces physiques basses

### `x6h-B1` — Reconstruction affine RT0/MAC des corrections face-vers-particule

- **Clé unique :** `0493x6h-b1`
- **ID canonique :** `0493x6h-b1`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Reconstruction face-particule active dans le profil Q6-g-f qualifié
- **Confiance :** `A`

Remplace, dans le chemin free_surface_masked force+Q6 fusionné, l'application d'un incrément constant par cellule par une reconstruction affine aux positions particulaires entre les corrections des faces opposées. Les faces west/south sont déduites des moyennes cellulaires et des faces east/north, avec x6h-A pour les frontières basses; la divergence discrète du champ reconstruit est ainsi celle du champ FV projeté.

**Notes.** Le premier chemin B1 est volontairement limité à exactement une espèce Q6 projetée et réutilise les buffers east/north existants; il n'ajoute ni stockage de faces persistant par espèce ni seconde passe particulaire. Les extensions périodiques ultérieures, notamment x7q, ferment ensuite exactement le mode k=0 réellement appliqué.

**Relations :**
- `BUILDS_ON` → `x6h-B0` — Diagnostic régional de divergence après application aux particules
- `EXTENDS` → `x6h-A` — Correctif des corrections de faces physiques basses
- `REFERENCES` → `x6h-A` — Correctif des corrections de faces physiques basses

### `x7a` — Kick viriel de densité CUDA résident

- **Clé unique :** `0493x7a`
- **ID canonique :** `0493x7a`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Expérience de restauration explicite; abandonnée au profit de la cible de divergence x7c/x7d
- **Confiance :** `A`

Porte sur le chemin free_surface_masked Q6-g-f le mécanisme historique de restauration de densité sous forme d'un kick explicite post-projection : Pvir/rhoRef=kVirial*(rawFill-1), puis duVir=-betaEOS*dt*grad(Pvir/rhoRef). Le kick est limité au bulk liquide, avec correction uniforme optionnelle du moment net, et est fusionné dans le redépôt final des moments cellule.

**Notes.** Chemin initial étroit : exactement une phase liquide et une espèce liquide projetée, x6c+x6f+B1, pas de couplage viriel gaz/interface. virialDensityKickEnable=false reste le défaut. Le mécanisme est ensuite clarifié sémantiquement par x7b puis rendu mutuellement exclusif avec x7c.

**Relations :**
- `BUILDS_ON` → `x6h-B1` — Reconstruction affine RT0/MAC des corrections face-vers-particule
- `REFERENCES` → `x7c` — Restauration de densité intégrée au RHS Q6
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité
- `SUPERSEDED_BY` → `x7c` — Restauration de densité intégrée au RHS Q6

### `x7b` — Sémantique continue et diagnostic de grille du viriel

- **Clé unique :** `0493x7b`
- **ID canonique :** `0493x7b`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Consolidation sémantique de l'ablation virielle; stratégie ensuite remplacée par x7c
- **Confiance :** `A`

Fixe la convention continue du mécanisme x7a sans modifier son update numérique lorsque kVirial et betaEOS sont explicites : kVirial porte des unités de vitesse au carré et ne se redimensionne pas avec dx/dy; la résolution temporelle est suivie séparément par cVir=sqrt(betaEOS*kVirial) et les nombres de Courant viriels. Le candidat K32 qualifié devient le défaut lorsque le viriel est activé.

**Notes.** Le patch se déclare explicitement semantic/diagnostic. Il conserve virialDensityKickEnable=false par défaut et retient kVirial=0.10666666666666667, betaEOS=0.05 comme calibration continue K32 après qualification trois seeds.

**Relations :**
- `BUILDS_ON` → `x7a` — Kick viriel de densité CUDA résident
- `REFERENCES` → `x7a` — Kick viriel de densité CUDA résident
- `REFERENCES` → `x7c` — Restauration de densité intégrée au RHS Q6
- `SUPERSEDED_BY` → `x7c` — Restauration de densité intégrée au RHS Q6

### `x7c` — Restauration de densité intégrée au RHS Q6

- **Clé unique :** `0493x7c`
- **ID canonique :** `0493x7c`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Mécanisme RHS retenu conceptuellement; paramétrage physique raffiné par x7d
- **Confiance :** `A`

Remplace le kick viriel explicite post-projection par une contrainte de divergence directement dans le solve Q6 : dans le bulk liquide, div(u_proj)=beta_rho*(rawFill-1)/dt. Les cellules sur la bande d'interface conservent le traitement de pression x6f/x6g; beta=0 est un no-op exact.

**Notes.** q6DensityRelaxationBeta est sans dimension et défini par pas. Le chemin est limité au sous-ensemble x6c+x6f, force fusionnée, B1, une espèce liquide projetée. x7c et le kick viriel explicite x7a/x7b sont mutuellement exclusifs.

**Relations :**
- `BUILDS_ON` → `x7b` — Sémantique continue et diagnostic de grille du viriel
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité

### `x7d` — Constante de temps physique de restauration de densité

- **Clé unique :** `0493x7d`
- **ID canonique :** `0493x7d`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Paramétrage physique retenu; tau_rho=0.25 dans la chaîne qualifiée
- **Confiance :** `A`

Consolide l'opérateur x7c sans en changer le kernel : l'entrée physique préférée devient q6DensityRelaxationTime=tau_rho, avec div(u_proj)=(rawFill-1)/tau_rho et betaParPas=dt/tau_rho. Le beta par pas x7c reste disponible pour compatibilité mais est mutuellement exclusif avec tau_rho positif. Une campagne coarse/fine à temps physique égal vérifie la sémantique de l'opérateur sous raffinement.

**Notes.** Qualification historique : 300x150 dt=0.005 beta=0.02 correspond à tau_rho=0.25; à 600x300 dt=0.0025, le même tau donne betaParPas=0.01. Le test est un diagnostic de scaling de l'opérateur, pas une preuve complète de convergence continue MPCD.

**Relations :**
- `BUILDS_ON` → `x7c` — Restauration de densité intégrée au RHS Q6
- `REFERENCES` → `x7c` — Restauration de densité intégrée au RHS Q6

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7D_DENSITY_RELAXATION_TIME_GRID_REFINEMENT.md`
- `ASSOCIATED_WITH` — `doc/README_0493X7E_X6G_X7D_COMBINATION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7d_density_rhs_grid_refinement.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7d_signed_traction_scan.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7e_x6g_x7d_combination.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7d_density_rhs_grid_refinement.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x7e_x6g_x7d_validation.sh`

### `x7d-v2` — Gate cohérent de compression pour la restauration de densité

- **Clé unique :** `0493x7d-v2`
- **ID canonique :** `0493x7d-v2`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif dans le profil Q6-g-f qualifié; gate désactivé = comportement x7d historique
- **Confiance :** `A`
- **Date :** `2026-08-11`
- **Commit :** `1d6eae3b0e6c8c698557207435a7893043f21042`

Remplace, lorsque le gate est activé, la restauration x7d appliquée à chaque fluctuation locale par une admission des défauts positifs cohérents : la cellule et au moins un voisin de face doivent dépasser le même seuil. Après admission, le défaut complet rawFill-1 est conservé dans la cible de divergence; le seuil n'est pas soustrait.

**Notes.** Motivé par x7n, qui sépare compression structurée et bruit d'occupation. Le patch initial part du checkpoint c47f49f; son patcher a avorté après avoir écrit une partie des fichiers et x7d-v2-fix1 ne fait que terminer ces call-sites. Ce fix1 d'installation n'est donc pas un jalon canonique. Profil final documenté : gate=true, seuil positif 3/gamma.

**Relations :**
- `BUILDS_ON` → `x7n` — Calibrateur de fluide sélectionnable par chemin et diagnostic compression/bruit
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité

### `x7d-v2-fix2` — Première fermeture du moment périodique B1 au niveau cellule

- **Clé unique :** `0493x7d-v2-fix2`
- **ID canonique :** `0493x7d-v2-fix2`
- **Nature / domaine :** `FIX` / `Q6_GF`
- **Statut :** Correctif intermédiaire actif historiquement; fermeture k=0 centrée cellule ensuite rendue exacte au niveau particulaire par x7q
- **Confiance :** `A`
- **Date :** `2026-08-11`
- **Commit :** `1d6eae3b0e6c8c698557207435a7893043f21042`

Dans le chemin monophase fullDomain avec B1 et direction périodique, accumule la correction Q6 massiquement au niveau cellule puis retire son mode uniforme k=0 lors de l'application B1. Les directions non périodiques et les domaines partiels avec traction interfaciale restent inchangés.

**Notes.** La correction est physique : un gradient de pression interne ne doit pas changer le moment total de l'espèce projetée dans une direction périodique. Le sous-fix fix2a enlève seulement une dépendance indue à projectionMomentumCorrectionEnable et est conservé comme preuve attachée, pas comme jalon séparé.

**Relations :**
- `FIXES` → `x7d-v2` — Gate cohérent de compression pour la restauration de densité
- `REFERENCES` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `x7d-v2-signed1` — Restauration de densité signée à gates cohérents

- **Clé unique :** `0493x7d-v2-signed1`
- **ID canonique :** `0493x7d-v2-signed1`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif dans le profil final signé; qualifié avec la chaîne x7q
- **Confiance :** `A`
- **Date :** `2026-08-11`
- **Commit :** `1d6eae3b0e6c8c698557207435a7893043f21042`

Conserve la branche positive cohérente de x7d-v2 et ajoute une branche négative de traction/déplétion : un défaut négatif n'est admis que si la cellule et au moins un voisin de face franchissent le seuil négatif; le défaut complet est alors multiplié par q6DensityRelaxationTractionGain. Gain nul est un no-op exact.

**Notes.** Le patcher signed1 exige explicitement un état x7d-v2/fix2a déjà qualifié, ce qui fixe son ordre historique après la première fermeture de moment. Profil final documenté : seuil positif 3/gamma, seuil négatif 6/gamma, tractionGain=1.0, tau_rho=0.25.

**Relations :**
- `BUILDS_ON` → `x7d-v2-fix2` — Première fermeture du moment périodique B1 au niveau cellule
- `REFERENCES` → `x7d-v2` — Gate cohérent de compression pour la restauration de densité
- `REFERENCES` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d

- **Clé unique :** `0493x7e`
- **ID canonique :** `0493x7e`
- **Nature / domaine :** `QUALIFICATION` / `Q6_GF`
- **Statut :** Qualification de composition Q6-g-f; kick viriel explicite désactivé
- **Confiance :** `A`

Valide sans modifier l'opérateur CUDA l'assemblage additif, dans un même RHS et un même solve CG, de la condition de pression interfaciale x6g et de la cible de divergence bulk x7d. La qualification réutilise la suite d'invariants x6g et le raffinement coarse/fine x7d avec tau_rho=0.25 et B1 actif.

**Notes.** RHS = -div(u*) + contribution Dirichlet x6g(p_g-p_ref) + cible bulk x7d. x6g agit aux faces alpha=0.5, x7d dans le bulk liquide, tous deux réutilisent pressureMask/stencil x6f et B1 pour l'application particulaire.

**Relations :**
- `BUILDS_ON` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `BUILDS_ON` → `x7d` — Constante de temps physique de restauration de densité
- `QUALIFIES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `QUALIFIES` → `x7d` — Constante de temps physique de restauration de densité
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7E_X6G_X7D_COMBINATION.md`
- `ASSOCIATED_WITH` — `doc/src_mpcd_env_flags_inventory_consolidated_0493x7e_q6_g_f.csv`
- `ASSOCIATED_WITH` — `doc/src_mpcd_params_inventory_consolidated_0493x7e_q6_g_f.csv`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7e_x6g_x7d_combination.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7e_x6g_x7d_validation.sh`

### `x7f` — Extension Q6-g-f aux familles statiques multi-BC

- **Clé unique :** `0493x7f`
- **ID canonique :** `0493x7f`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif sur les familles statiques qualifiées; Darcy encore exclu à cette étape
- **Confiance :** `A`

Généralise le chemin free_surface_masked + prestream_single_fused du dam-break aux familles statiques déjà supportées par le backend résident (périodique, canal à parois, boîte fermée, IO plein et segmenté) et rend la projection pré-transport active même à force volumique nulle. Les équations x6f/x6g/x7d/B1 ne changent pas.

**Notes.** Le patch est une généralisation de chemin/frontières, pas un nouveau modèle de projection. Le resampling n'est pas élargi et les domaines mobiles/immersed-solid restent exclus.

**Relations :**
- `BUILDS_ON` → `x7e` — Qualification combinée pression gaz x6g + restauration de densité x7d
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7F_Q6_G_F_MULTIBC.md`
- `ASSOCIATED_WITH` — `scripts/check_0493x7f_q6_g_f_multibc.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7f_q6_g_f_multibc_validation.sh`

### `x7f-fix2` — Correctif de garde wall-simple pour canal mixte

- **Clé unique :** `0493x7f-fix2`
- **ID canonique :** `0493x7f-fix2`
- **Nature / domaine :** `FIX` / `Q6_GF`
- **Statut :** Correctif actif du périmètre x7f
- **Confiance :** `A`

Corrige la garde du chemin résident wall-simple afin qu'un canal périodique-x avec faces solides/specular en y soit accepté sans exiger artificiellement wallVP. La règle de collision/réflexion elle-même n'est pas modifiée.

**Notes.** Le patch x7f-fix1 séparé ne corrige que l'initialisation LiveVis du runner sous set -u et reste volontairement non canonique. x7f-fix2 est au contraire une correction de garde du chemin de calcul résident.

**Relations :**
- `FIXES` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC
- `REFERENCES` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC

### `x7g` — Darcy-Brinkman placé avant la projection Q6-g-f

- **Clé unique :** `0493x7g`
- **ID canonique :** `0493x7g`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif sur le sous-ensemble Darcy/chi qualifié
- **Confiance :** `A`

Étend x7f au domaine fictif Darcy/chi résident en appliquant la relaxation déterministe de vitesse avant le solve Q6-g-f pré-transport, puis en supprimant l'ancien replay post-collision pour ce chemin afin d'éviter double application et recréation de divergence après projection.

**Notes.** Le kernel Darcy résident existant est réutilisé. Le premier périmètre qualifié impose un domaine fictif rempli, sans darcyInitialDeactivateBelowChi, afin que chi ne fabrique pas une fausse surface libre.

**Relations :**
- `BUILDS_ON` → `x7f-fix2` — Correctif de garde wall-simple pour canal mixte
- `REFERENCES` → `x7f` — Extension Q6-g-f aux familles statiques multi-BC

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7G_Q6_G_F_DARCY.md`
- `ASSOCIATED_WITH` — `scripts/check_0493x7g_q6_g_f_darcy.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7g_q6_g_f_darcy_validation.sh`

### `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f

- **Clé unique :** `0493x7h`
- **ID canonique :** `0493x7h`
- **Nature / domaine :** `INFRA` / `Q6_GF`
- **Statut :** Infrastructure de démonstration et régression
- **Confiance :** `A`

Introduit le chemin explicite src-q6-g-f dans les helpers/runners historiques et factorise le profil x4b+x6c+x6f+x6g si gaz+B1+x7d sans modifier les équations. Les démonstrations run_ok deviennent des comparateurs reproductibles entre SRC, Q6 historique et Q6-g-f.

**Notes.** Les run_ok restent les démonstrations historiques stabilisées. x7h ajoute le routage/comparaison et le dam-break run_ok; les campagnes nouvelles spécialisées restent des run_*.

**Relations :**
- `BUILDS_ON` → `x7g` — Darcy-Brinkman placé avant la projection Q6-g-f
- `REFERENCES` → `x4b` — Q6-g prestream_single_fused — fusion CUDA force + projection
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7H_RUN_OK_Q6_G_F_COMPARISON.md`

### `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f

- **Clé unique :** `0493x7i`
- **ID canonique :** `0493x7i`
- **Nature / domaine :** `BENCHMARK` / `Q6_GF`
- **Statut :** Benchmark diagnostique de référence; sans seuil PASS/FAIL arbitraire
- **Confiance :** `A`

Compare les trois chemins sur Taylor-Green forcé, Poiseuille, bend-pipe Darcy et same-face IO à partir de dumps particulaires et d'analyses hors ligne. La campagne mesure compressibilité structurée, profil/transport effectif et propagation de démarrage sans changer le solveur.

**Notes.** Le README qualifie explicitement la campagne de physique mais précise qu'elle est diagnostic-driven et non threshold-driven. BENCHMARK est donc conservé plutôt que QUALIFICATION binaire.

**Relations :**
- `BUILDS_ON` → `x7h` — Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7I_Q6_G_F_PHYSICAL_QUALIFICATION.md`
- `ASSOCIATED_WITH` — `matlab/analyze_0493x7i_q6_g_f_qualification.m`
- `ASSOCIATED_WITH` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x7i_q6_g_f_physical_qualification_x7q.sh`

### `x7j` — CG Q6-g-f entièrement CUDA résident

- **Clé unique :** `0493x7j`
- **ID canonique :** `0493x7j`
- **Nature / domaine :** `PERF` / `Q6_GF`
- **Statut :** Optimisation majeure du solve Q6-g-f; fallback hôte conservé
- **Confiance :** `A`
- **Date :** `2026-08-10`
- **Commit :** `8e11eefc50a7b16ff67aa57d5149f5e6ae7dae0f`

Supprime les réductions et synchronisations GPU-vers-host à chaque itération du CG masqué x6f en remplaçant la boucle hôte par un noyau coopératif résident couvrant la récurrence de Krylov complète; la physique, le RHS, le stencil et B1 restent inchangés.

**Notes.** Le sujet Git 0493x7j constitue une preuve explicite d'introduction distincte des commits ultérieurs de documentation. Le cas TG x7i avait isolé ~164 itérations comparables mais un coût de solve dominant dû aux synchronisations hôte.

**Relations :**
- `BUILDS_ON` → `x7i` — Benchmark physique multi-cas SRC / Q6 / Q6-g-f
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7J_Q6_G_F_RESIDENT_CG.md`

### `x7k` — Stripping des diagnostics Q6-g-f en production

- **Clé unique :** `0493x7k`
- **ID canonique :** `0493x7k`
- **Nature / domaine :** `PERF` / `Q6_GF`
- **Statut :** Optimisation de télémétrie active en production
- **Confiance :** `A`
- **Date :** `2026-08-10`
- **Commit :** `f12cfe7c65e4acffdfb4a7040dc291dfd3f1e908`

Conserve tous les diagnostics d'échec mais ne calcule les audits/réductions coûteux du chemin Q6-g-f qu'au premier pas et à la cadence summaryEvery. Aucun paramètre physique ni opérateur n'est modifié.

**Notes.** x7k et x7l sont introduits ensemble par le commit explicitement nommé 0493x7k-x7l mais possèdent chacun un README et un patch propres. Le candidat composite Git reste une provenance de commit, pas un jalon canonique composite.

**Relations :**
- `BUILDS_ON` → `x7j` — CG Q6-g-f entièrement CUDA résident

### `x7l` — Stripping de la télémétrie thermostat/espèces

- **Clé unique :** `0493x7l`
- **ID canonique :** `0493x7l`
- **Nature / domaine :** `PERF` / `Q6_GF`
- **Statut :** Optimisation de télémétrie active; thermostat physique inchangé
- **Confiance :** `A`
- **Date :** `2026-08-10`
- **Commit :** `f12cfe7c65e4acffdfb4a7040dc291dfd3f1e908`

Supprime des pas de production Q6-g-f les téléchargements et réductions de télémétrie thermostat/espèces, tout en conservant la séquence physique deposit/kinetic/scale/apply et les diagnostics à la cadence x7k.

**Notes.** Le suffixe fix1 du nom de patch archivé correspond à une correction de la réalisation du stripping x7l; le jalon historique identifié par README/commit reste x7l.

**Relations :**
- `BUILDS_ON` → `x7k` — Stripping des diagnostics Q6-g-f en production
- `REFERENCES` → `x7k` — Stripping des diagnostics Q6-g-f en production

### `x7m` — Garde topologique monophase par registre de phases

- **Clé unique :** `0493x7m`
- **ID canonique :** `0493x7m`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Étape initiale; complétée par x7m-fix1
- **Confiance :** `A`

Évite qu'une fluctuation alpha<0.5 soit interprétée comme interface physique dans un cas explicitement monophase : la présence d'une phase gaz enregistrée devient l'autorité qui active le stencil d'interface x6f. La première version conserve toutefois pressureMask=carrierMask en monophase.

**Notes.** Le same-face IO 300x300 avait créé une fausse interface avec carrier complet mais un pressureMask amputé. x7m sépare d'abord la notion de phase enregistrée de la fluctuation alpha; le problème des cellules temporairement vides subsiste jusqu'à fix1.

**Relations :**
- `BUILDS_ON` → `x7l` — Stripping de la télémétrie thermostat/espèces
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x7m-fix1` — Domaine de pression monophase persistant

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md`

### `x7m-fix1` — Domaine de pression monophase persistant

- **Clé unique :** `0493x7m-fix1`
- **ID canonique :** `0493x7m-fix1`
- **Nature / domaine :** `FIX` / `Q6_GF`
- **Statut :** Correctif structurel actif du chemin monophase
- **Confiance :** `A`

Corrige x7m en rendant le pressureMask monophase égal au domaine de calcul complet, indépendamment de l'occupation particulaire instantanée. Une cellule MPCD temporairement vide reste un inconnu de pression mais pas un support de vitesse inventé.

**Notes.** Le bend-pipe avait perdu deux cellules carrier après 613 pas, créant cinq faces tronquées et une composante pure Neumann incompatible. Le patch historique x7m-fix1 est une preuve primaire même sans candidat Git autonome; les cas deux-phases restent inchangés.

**Relations :**
- `FIXES` → `x7m` — Garde topologique monophase par registre de phases
- `REFERENCES` → `x7m` — Garde topologique monophase par registre de phases

### `x7n` — Calibrateur de fluide sélectionnable par chemin et diagnostic compression/bruit

- **Clé unique :** `0493x7n`
- **ID canonique :** `0493x7n`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic/calibrateur de chemin; précède les corrections x7d-v2 et la qualification x7q
- **Confiance :** `A`

Étend le calibrateur 0493w1 sans modifier celui-ci afin de caractériser explicitement src, src-q6 et src-q6-g-f, et ajoute les analyses hors ligne utilisées pour distinguer transport intrinsèque, fluctuations d'occupation et compression cohérente. Cette étape fournit le diagnostic qui motive la réparation ultérieure x7d-v2.

**Notes.** Le commit qui introduit README/runner/analyseurs x7n porte le sujet "defaut x7d compression/bruit identifié via Poiseuille+TG, Dambreak confirmé ok" : il atteste le diagnostic mais ne nomme pas x7n dans le sujet, donc il n'est pas forcé ici comme introduced_commit. Les fix1..fix4c de l'outillage x7n restent des sous-révisions du calibrateur, non des jalons physiques autonomes.

**Relations :**
- `BUILDS_ON` → `x7m-fix1` — Domaine de pression monophase persistant
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité
- `REFERENCES` → `x7d-v2` — Gate cohérent de compression pour la restauration de densité
- `REFERENCES` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `x7o` — Symétrisation par réflexion du Q6 independent_masked

- **Clé unique :** `0493x7o`
- **ID canonique :** `0493x7o`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif; corrige le biais est/nord du fullDomain independent_masked
- **Confiance :** `A`
- **Date :** `2026-08-11`
- **Commit :** `1d6eae3b0e6c8c698557207435a7893043f21042`

Supprime dans le chemin fullDomain le raccourci directionnel qui assimilait la valeur cellule à la face est/nord. Les vitesses de face deviennent des moyennes FV centrées équivariantes par réflexion et la correction cellule est reconstruite à partir des deux faces opposées, comme dans le chemin masqué.

**Notes.** Le changement vise la discrétisation monophase fullDomain. Les sémantiques de masque/interface des domaines partiels restent celles de x6f; les diagnostics sont alignés sur la même convention de faces centrées.

**Relations :**
- `BUILDS_ON` → `x7d-v2-signed1` — Restauration de densité signée à gates cohérents

### `x7p` — Symétrisation par réflexion du Q6 commun

- **Clé unique :** `0493x7p`
- **ID canonique :** `0493x7p`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif; enlève l'orientation backward-difference historique du Q6 commun
- **Confiance :** `A`
- **Date :** `2026-08-11`
- **Commit :** `1d6eae3b0e6c8c698557207435a7893043f21042`

Applique au chemin Q6 commun la convention FV centrée validée par x7o : une face intérieure porte la moyenne arithmétique des cellules adjacentes, les corrections sont d'abord construites sur les faces puis la correction cellule réellement appliquée est reconstruite par moyenne des faces opposées.

**Notes.** x7p est l'analogue common-Q6 de x7o. Il ne remplace pas la condition interfaciale x6f du chemin free_surface_masked.

**Relations :**
- `BUILDS_ON` → `x7o` — Symétrisation par réflexion du Q6 independent_masked
- `REFERENCES` → `x7o` — Symétrisation par réflexion du Q6 independent_masked

### `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

- **Clé unique :** `0493x7q`
- **ID canonique :** `0493x7q`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif automatiquement pour B1 + fullDomain + direction périodique; chemin partiel/dam-break historique inchangé
- **Confiance :** `A`
- **Date :** `2026-08-12`
- **Commit :** `9c76fbb64232065dfe082d0332310b7c9c070a9d`

Mesure la correction RT0 réellement échantillonnée aux positions des particules dans le chemin monophase fullDomain périodique, réduit son moment sur GPU puis retire dans un second passage résident le résidu uniforme k=0 laissé par l'estimation centrée cellule de x7d-v2-fix2.

**Notes.** Le terme affine RT0 contient un moment lié au barycentre particulaire instantané, qui ne s'annule pas exactement pour un échantillon MPCD fini. x7q ferme ce résidu au niveau où il est réellement créé sans appliquer la correction globale legacy aux espèces compressibles.

**Relations :**
- `BUILDS_ON` → `x7o` — Symétrisation par réflexion du Q6 independent_masked
- `FIXES` → `x7d-v2-fix2` — Première fermeture du moment périodique B1 au niveau cellule
- `REFERENCES` → `x7d-v2-fix2` — Première fermeture du moment périodique B1 au niveau cellule
- `REFERENCES` → `x7p` — Symétrisation par réflexion du Q6 commun

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7Y_X7Q_RUNTIME_ABLATION.md`
- `ASSOCIATED_WITH` — `doc/src_mpcd_env_flags_inventory_consolidated_0493x7q_q6_g_f.csv`
- `ASSOCIATED_WITH` — `doc/src_mpcd_params_inventory_consolidated_0493x7q_q6_g_f.csv`
- `ASSOCIATED_WITH` — `scripts/run_0493x7i_q6_g_f_physical_qualification_x7q.sh`

### `x8a` — Diagnostic exact du moment Darcy

- **Clé unique :** `0493x8a`
- **ID canonique :** `0493x8a`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic opt-in; OFF en production
- **Confiance :** `A`
- **Date :** `2026-08-14`
- **Commit :** `3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f`

Instrumente de façon opt-in le kick Darcy déterministe afin de sommer exactement l'impulsion particulaire appliquée et de fermer le bilan DeltaP = I_body + I_Darcy + I_nonDarcyResidual sur les comparaisons SRC/Q6/Q6-g-f.

**Notes.** Le gate runtime ne change aucun paramètre physique. Pour forcingMode=mean, DeltaP_cell=-M_cell*lambda*(u_cell-u_s), avec le lambda float réellement consommé par le kernel.

**Relations :**
- `BUILDS_ON` → `x7q` — Fermeture exacte du moment périodique au niveau particulaire B1/RT0

### `x8b` — Attribution temporelle Darcy / résidu non-Darcy

- **Clé unique :** `0493x8b`
- **ID canonique :** `0493x8b`
- **Nature / domaine :** `ANALYZER` / `Q6_GF`
- **Statut :** Analyseur hors ligne; aucune modification du solveur
- **Confiance :** `A`
- **Date :** `2026-08-14`
- **Commit :** `3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f`

Analyse hors ligne les runs x8a à chaque intervalle commun et compare Q6-g-f moins Q6 puis Q6 moins SRC, en séparant excès de perte Darcy exacte et résidu non-Darcy sans attribuer prématurément ce dernier à un opérateur particulier.

**Notes.** Les temps d'apparition sont définis par fractions du propre excès final avec persistance, pas par un seuil absolu arbitraire.

**Relations :**
- `BUILDS_ON` → `x8a` — Diagnostic exact du moment Darcy
- `REFERENCES` → `x8a` — Diagnostic exact du moment Darcy

### `x8c` — Localisation temporaire du moment par étapes

- **Clé unique :** `0493x8c`
- **ID canonique :** `0493x8c`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Instrumentation temporaire retirée après campagne; preuve historique conservée
- **Confiance :** `A`
- **Date :** `2026-08-14`
- **Commit :** `3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f`

Installe temporairement un audit de moment aux huit étapes du pas afin de localiser le résidu x8b entre Q6, stream/parois, boundary, collision, thermostat et Darcy, tout en conservant x8a comme autorité du bilan cumulatif.

**Notes.** Le README qualifie explicitement x8c de disposable; le commit 423b1c2dc4e0 atteste ensuite son retrait. La suppression du code de diagnostic ne supprime pas le jalon historique.

**Relations :**
- `BUILDS_ON` → `x8b` — Attribution temporelle Darcy / résidu non-Darcy
- `REFERENCES` → `x8a` — Diagnostic exact du moment Darcy
- `REFERENCES` → `x8b` — Attribution temporelle Darcy / résidu non-Darcy

### `x8d` — Qualification indépendante Q6-g-f par Poiseuille et Brinkman

- **Clé unique :** `0493x8d`
- **ID canonique :** `0493x8d`
- **Nature / domaine :** `QUALIFICATION` / `Q6_GF`
- **Statut :** Qualification analytique du chemin Q6-g-f; aucun changement C++/CUDA
- **Confiance :** `A`
- **Date :** `2026-08-15`
- **Commit :** `d0f4856e03d82098d5a5a1cedcdd4f89957fa98d`

Qualifie Q6-g-f sans prendre SRC/Q6 comme référence : canal à parois physiques contre Poiseuille analytique et canal périodique avec slab chi contre la solution de Brinkman résolue, avec viscosité, forme, slip et longueur de pénétration mesurés.

**Notes.** Le cas chi choisit ell_B=4a afin de qualifier d'abord l'équation de Brinkman résolue avant le régime de pénalisation raide.

**Relations :**
- `BUILDS_ON` → `x8c` — Localisation temporaire du moment par étapes

### `x8e` — Recalibration viscosité Q6-g-f et raideur Darcy

- **Clé unique :** `0493x8e`
- **ID canonique :** `0493x8e`
- **Nature / domaine :** `CALIBRATOR` / `Q6_GF`
- **Statut :** Calibration Q6-g-f et carte de raideur Darcy; aucun changement du solveur
- **Confiance :** `A`
- **Date :** `2026-08-15`
- **Commit :** `d0f4856e03d82098d5a5a1cedcdd4f89957fa98d`

Recalibre le microfluide Q6-g-f x8d par un ensemble Taylor-Green multi-seeds via le calibrateur x7n, puis utilise la viscosité fraîche pour balayer ell_B/a=4,2,1,0.5 et documenter séparément l'endpoint raide alpha=4000 sous-résolu.

**Notes.** alpha=4000 est un endpoint de mur pénalisé et ne doit pas être présenté comme une couche de pénétration Brinkman résolue.

**Relations :**
- `BUILDS_ON` → `x8d` — Qualification indépendante Q6-g-f par Poiseuille et Brinkman
- `REFERENCES` → `x7n` — Calibrateur de fluide sélectionnable par chemin et diagnostic compression/bruit
- `REFERENCES` → `x8d` — Qualification indépendante Q6-g-f par Poiseuille et Brinkman

### `x8f` — Premier candidat von Karman Q6-g-f à inlet/outlet ouverts

- **Clé unique :** `0493x8f`
- **ID canonique :** `0493x8f`
- **Nature / domaine :** `BENCHMARK` / `OPEN_BOUNDARY`
- **Statut :** Premier candidat VK ouvert; runner-only, ensuite prolongé/raffiné
- **Confiance :** `A`
- **Date :** `2026-08-15`
- **Commit :** `d0f4856e03d82098d5a5a1cedcdd4f89957fa98d`

Construit un premier benchmark cylindre confiné avec le microfluide x8e gelé, inlet gauche contrôlé, outlet Neumann passif, parois no-slip et cylindre Brinkman, sans force volumique ni keep-mean-flow, afin d'observer l'établissement d'un sillage antisymétrique.

**Notes.** Le README initial dimensionne Re≈65 sur H=5D, Lx=10D, cylindre à 3D; des éditions locales ont ensuite allongé le domaine. Le jalon reste le premier benchmark ouvert x8f, pas une nouvelle physique C++/CUDA.

**Relations :**
- `BUILDS_ON` → `x8e` — Recalibration viscosité Q6-g-f et raideur Darcy
- `REFERENCES` → `x8d` — Qualification indépendante Q6-g-f par Poiseuille et Brinkman
- `REFERENCES` → `x8e` — Recalibration viscosité Q6-g-f et raideur Darcy

### `x8g` — Qualification full-face et bilan de masse du VK

- **Clé unique :** `0493x8g`
- **ID canonique :** `0493x8g`
- **Nature / domaine :** `QUALIFICATION` / `OPEN_BOUNDARY`
- **Statut :** Qualification full-face/mass-balance du candidat VK; runner-only
- **Confiance :** `A`
- **Date :** `2026-08-15`
- **Commit :** `d0f4856e03d82098d5a5a1cedcdd4f89957fa98d`

Décline le benchmark x8f sur la vraie famille io_fullface avec inlet/outlet plein cadre et balanced_flux afin d'isoler la fermeture de masse du chemin ouvert Q6-g-f avant les corrections segmentées ultérieures.

**Notes.** Le runner annonce explicitement une qualification true-fullface mass-balance à U=0.18 et conserve le même microfluide, les parois physiques et le cylindre Brinkman.

**Relations :**
- `BUILDS_ON` → `x8f` — Premier candidat von Karman Q6-g-f à inlet/outlet ouverts
- `REFERENCES` → `x8f` — Premier candidat von Karman Q6-g-f à inlet/outlet ouverts

### `x8h` — Restart hydrodynamique pour les longs runs VK

- **Clé unique :** `0493x8h`
- **ID canonique :** `0493x8h`
- **Nature / domaine :** `INFRA` / `OPEN_BOUNDARY`
- **Statut :** Infrastructure de continuation hydrodynamique; RNG non bitwise continu
- **Confiance :** `A`
- **Date :** `2026-08-15`
- **Commit :** `d0f4856e03d82098d5a5a1cedcdd4f89957fa98d`

Génère un runner de continuation à partir du x8f courant, valide état/params/chi/grille/dt, conserve l'origine globale des pas et redémarre depuis un dump sans régénérer les particules.

**Notes.** Le compteur local et le RNG redémarrent : le README précise qu'il s'agit d'un restart hydrodynamique, pas d'une continuation bitwise de la trajectoire stochastique.

**Relations :**
- `BUILDS_ON` → `x8f` — Premier candidat von Karman Q6-g-f à inlet/outlet ouverts
- `REFERENCES` → `x8f` — Premier candidat von Karman Q6-g-f à inlet/outlet ouverts

### `x8i` — Analyse du sillage VK établi par POD et sondes

- **Clé unique :** `0493x8i`
- **ID canonique :** `0493x8i`
- **Nature / domaine :** `ANALYZER` / `OPEN_BOUNDARY`
- **Statut :** Analyseur du sillage établi; aucune modification du solveur
- **Confiance :** `A`
- **Date :** `2026-08-15`
- **Commit :** `d0f4856e03d82098d5a5a1cedcdd4f89957fa98d`

Caractérise l'état établi issu des continuations x8h : stationnarité amont, amplitude de brisure de symétrie, paire POD, fréquence/Strouhal par rotation de phase, fit harmonique indépendant aux sondes, progression de phase et champs moyennés en phase.

**Notes.** Cette fonction était attribuée à tort à x8j dans le référentiel initial. L'analyseur x8i est explicitement conçu pour les enregistrements de restart x8h.

**Relations :**
- `BUILDS_ON` → `x8h` — Restart hydrodynamique pour les longs runs VK
- `REFERENCES` → `x8h` — Restart hydrodynamique pour les longs runs VK

### `x8j` — Nondimensionnalisation VK et comparaison bibliographique

- **Clé unique :** `0493x8j`
- **ID canonique :** `0493x8j`
- **Nature / domaine :** `ANALYZER` / `OPEN_BOUNDARY`
- **Statut :** Analyse bibliographique/nondimensionnelle; enrichie plus tard par les diagnostics de flux x8n
- **Confiance :** `A`
- **Date :** `2026-08-15`
- **Commit :** `d0f4856e03d82098d5a5a1cedcdd4f89957fa98d`

Convertit les mesures du sillage établi x8i dans les conventions propres à Zovatto-Pedrizzetti et Sahin-Owens, compare période/Strouhal et nombres de Reynolds sans mélanger leurs échelles de référence, et documente le conditionnement amont du cas.

**Notes.** Le premier rôle de x8j est la comparaison nondimensionnelle issue de x8i. Le support ultérieur des fichiers x8n apparaît dans des révisions postérieures et ne doit pas être pris pour une dépendance d'introduction.

**Relations :**
- `BUILDS_ON` → `x8i` — Analyse du sillage VK établi par POD et sondes
- `REFERENCES` → `x8i` — Analyse du sillage VK établi par POD et sondes
- `REFERENCES` → `x8n` — Diagnostic de conservation amont du débit et du flux massique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `matlab/analyze_vk_nondim_0493x8j.m`

### `x8k` — Inlet segmenté à profil de Poiseuille local

- **Clé unique :** `0493x8k`
- **ID canonique :** `0493x8k`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif; sémantique de profil local retenue dans le benchmark Zovatto
- **Confiance :** `A`

Définit pour chaque segment une coordonnée tangentielle locale eta=(s-sMin)/(sMax-sMin) et impose u_n=4 Umax eta(1-eta) de façon cohérente dans l'injection particulaire et la cible Q6-g-f; la population hard_cell_density reste uniforme.

**Notes.** Le runner x8k utilise volontairement un segment partiel [0.20,0.80] pour rendre la localité observable. Son outlet UOUT=Umean n'est qu'un pont temporaire de bilan de flux et n'est pas la fermeture Neumann finale.

**Relations :**
- `BUILDS_ON` → `x8j` — Nondimensionnalisation VK et comparaison bibliographique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x8k_segmented_local_poiseuille.sh`

### `x8l` — Première extrapolation Neumann passive de la vitesse de sortie

- **Clé unique :** `0493x8l`
- **ID canonique :** `0493x8l`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Étape intermédiaire conservée : extrapolation de vitesse retenue comme base par x8r, mais sémantique de projection x8l seule supersédée
- **Confiance :** `A`

Pour un outlet droit segmenté en mode neumann sur le chemin Q6-g-f, remplace la cible nominale UOUT par la vitesse normale de la cellule de bord afin d'imposer au prédicteur une extrapolation discrète à gradient normal nul. Cette étape ne fournit pas encore la condition de pression correcte, réparée ensuite par x8r.

**Notes.** x8l établit u*_out=u*_cell. Utiliser ensuite cette même valeur comme cible de projection crée un ratchet de vitesse; x8r conserve l'extrapolation prédicteur mais remplace la condition elliptique par phi_out=0.

**Relations :**
- `BUILDS_ON` → `x8k` — Inlet segmenté à profil de Poiseuille local
- `REFERENCES` → `x8r` — Outlet de pression Neumann Q6-g-f

### `x8m` — Benchmark de production Zovatto-Pedrizzetti Re_H=280

- **Clé unique :** `0493x8m`
- **ID canonique :** `0493x8m`
- **Nature / domaine :** `BENCHMARK` / `OPEN_BOUNDARY`
- **Statut :** Benchmark de production/restart Zovatto; première lignée sous x8l, ensuite réalignée sur la fermeture x8t
- **Confiance :** `A`

Matérialise le cas cylindre confiné Q6-g-f dimensionné sur Zovatto-Pedrizzetti : profil de Poiseuille local pleine hauteur, H/D=5, Re_H cible 280, enregistrement des champs et restart. La lignée x8m passe du domaine de développement réduit au domaine bibliographique 15D amont + 40D aval; son outlet initial est x8l et sera réaligné sur x8t par x8u.

**Notes.** Le même label x8m couvre la lignée du cas de production, y compris le passage du domaine réduit de développement au domaine bibliographique complet. x8u n'est pas fusionné ici : il constitue l'alignement ultérieur du runner restartable sur les BC finales.

**Relations :**
- `BUILDS_ON` → `x8l` — Première extrapolation Neumann passive de la vitesse de sortie
- `REFERENCES` → `x8l` — Première extrapolation Neumann passive de la vitesse de sortie
- `REFERENCES` → `x8t` — Cible de relaxation de densité sans mode moyen à outlet pression
- `REFERENCES` → `x8u` — Réalignement du runner Zovatto sur la fermeture x8t

### `x8n` — Diagnostic de conservation amont du débit et du flux massique

- **Clé unique :** `0493x8n`
- **ID canonique :** `0493x8n`
- **Nature / domaine :** `ANALYZER` / `OPEN_BOUNDARY`
- **Statut :** Diagnostic hors ligne du conditionnement et de la conservation amont; aucune modification du solveur
- **Confiance :** `A`

Analyse hors ligne les enregistrements rho/ux du benchmark x8m et reconstruit par section Ub, Qv, rhoBar, Mrho, Jrho et Urho afin de distinguer accommodation de l'inlet, variation de densité et véritable dérive du flux massique. Aucun état physique n'est modifié.

**Notes.** Jrho est un flux macroscopique reconstruit depuis les champs coarse-grainés du recorder, pas un audit particulaire microscopique. Les rapports entre sections restent le test pertinent de cohérence spatiale.

**Relations :**
- `BUILDS_ON` → `x8m` — Benchmark de production Zovatto-Pedrizzetti Re_H=280
- `REFERENCES` → `x8m` — Benchmark de production Zovatto-Pedrizzetti Re_H=280

### `x8q` — Continuation cinétique locale de l'outlet Neumann

- **Clé unique :** `0493x8q`
- **ID canonique :** `0493x8q`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif pour outlet Neumann; forme finale local-bath après les sous-révisions x8q-fix1..fix4
- **Confiance :** `A`

Complète la sortie Neumann au niveau particulaire : les sortants sont supprimés et la demi-distribution entrante est reconstruite dans la forme finale x8q-fix4 par un bain maxwellien local issu des moments pré-stream des deux couches intérieures, avec échantillonnage pondéré par le flux normal.

**Notes.** La première implémentation x8q miroir/copie puis le sampler particule-à-particule de fix3 étaient des étapes internes. fix4 supprime la rétroaction auto-excitante et définit la fermeture cinétique retenue; les suffixes fix ne sont pas promus comme jalons autonomes.

**Relations :**
- `BUILDS_ON` → `x8l` — Première extrapolation Neumann passive de la vitesse de sortie

**Artefacts associés :**
- `ASSOCIATED_WITH` — `matlab/inj_rho_x8q_strict_cont_400.avi`
- `ASSOCIATED_WITH` — `scripts/check_0493x8q_neumann_smoke.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x8q_neumann_smoke.sh`

### `x8r` — Outlet de pression Neumann Q6-g-f

- **Clé unique :** `0493x8r`
- **ID canonique :** `0493x8r`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif; sémantique pression passive du mode openBoundaryOutletMode=neumann
- **Confiance :** `A`

Conserve u*_out=u*_cell comme extrapolation de vitesse prédicteur, mais cesse de la réimposer comme cible physique : la projection impose phi_out=0 à la face ouverte et laisse la correction normale finale être déterminée par la continuité.

**Notes.** x8r corrige le ratchet de vitesse de x8l tout en conservant son extrapolation de base. L'inlet reste prescrit et le bain cinétique x8q reste inchangé.

**Relations :**
- `BUILDS_ON` → `x8q` — Continuation cinétique locale de l'outlet Neumann
- `FIXES` → `x8l` — Première extrapolation Neumann passive de la vitesse de sortie

### `x8s` — Déflation exacte des modes longitudinaux lents du CG

- **Clé unique :** `0493x8s`
- **ID canonique :** `0493x8s`
- **Nature / domaine :** `PERF` / `OPEN_BOUNDARY`
- **Statut :** Actif uniquement dans la géométrie x8r pleine hauteur applicable; physique inchangée
- **Confiance :** `A`

Pour le domaine rectangulaire complet avec condition de correction de pression Neumann côté inlet et outlet droit x8r phi=0, résout analytiquement les trois modes longitudinaux de pression les plus lents à l'initialisation du CG puis démarre sur un résidu orthogonal, sans modifier l'équation ni la tolérance.

**Notes.** Sur 1200x400, le CG résident x7j et le fallback host atteignaient le même résidu légèrement supérieur à 1e-5 après 2500 itérations; x8s traite le conditionnement, pas la physique de sortie.

**Relations :**
- `BUILDS_ON` → `x8r` — Outlet de pression Neumann Q6-g-f
- `REFERENCES` → `x8r` — Outlet de pression Neumann Q6-g-f

### `x8t` — Cible de relaxation de densité sans mode moyen à outlet pression

- **Clé unique :** `0493x8t`
- **ID canonique :** `0493x8t`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif dans le couplage fullDomain + x8r + relaxation densité; autres topologies inchangées
- **Confiance :** `A`

Lorsque la relaxation de densité x7d signée, le domaine de pression complet et l'outlet de pression x8r sont simultanément actifs, retire seulement la moyenne spatiale de la cible de divergence de densité avant la projection afin d'éviter une source volumique globale non intentionnelle.

**Notes.** Le mode constant était éliminé par compatibilité dans l'ancien problème purement Neumann mais devient solvable avec l'outlet de pression x8r. x8t conserve toute la redistribution locale signée et soustrait uniquement <d_rho>.

**Relations :**
- `BUILDS_ON` → `x8s` — Déflation exacte des modes longitudinaux lents du CG
- `REFERENCES` → `x7d` — Constante de temps physique de restauration de densité
- `REFERENCES` → `x7d-v2-signed1` — Restauration de densité signée à gates cohérents
- `REFERENCES` → `x8r` — Outlet de pression Neumann Q6-g-f

### `x8u` — Réalignement du runner Zovatto sur la fermeture x8t

- **Clé unique :** `0493x8u`
- **ID canonique :** `0493x8u`
- **Nature / domaine :** `INFRA` / `OPEN_BOUNDARY`
- **Statut :** Réintégration production de la fermeture x8t dans la lignée x8m; clôture documentaire du cycle x8
- **Confiance :** `A`

Met à jour le runner restartable x8m pour utiliser explicitement la fermeture Neumann cinétique-pression validée x8q-x8t, autoriser RUN_MODES et activer par défaut le bruit thermique de l'inlet. Aucun C++/CUDA ni opérateur physique n'est introduit.

**Notes.** Updater runner-only. Il remplace les métadonnées passive_x8l par kinetic_pressure_x8t et passe inletThermalNoise de 0 à une valeur paramétrable par défaut 1.0.

**Relations :**
- `BUILDS_ON` → `x8t` — Cible de relaxation de densité sans mode moyen à outlet pression
- `REFERENCES` → `x8m` — Benchmark de production Zovatto-Pedrizzetti Re_H=280
- `REFERENCES` → `x8t` — Cible de relaxation de densité sans mode moyen à outlet pression

### `x9a` — Premier scaffold passif de courbure résident

- **Clé unique :** `0493x9a`
- **ID canonique :** `0493x9a`
- **Nature / domaine :** `DIAGNOSTIC` / `SURFACE_TENSION`
- **Statut :** Scaffold passif historique; géométrie seulement, sans tension superficielle active
- **Confiance :** `A`

Construit à partir du champ physique alpha x6c une normale sortante et une courbure cellulaires résidentes, puis audite la courbure aux crossings alpha=0.5, sans sigma, sans modification de phiGamma/RHS/B1 et sans kick particulaire.

**Notes.** x9a représente le coût et le contrat géométrique initial de la future capillarité tout en garantissant un no-op physique.

**Relations :**
- `BUILDS_ON` → `x6c` — Infrastructure résidente du champ de phase alpha
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha

### `x9b` — Courbure passive binomiale + Scharr et LiveVis résident

- **Clé unique :** `0493x9b`
- **ID canonique :** `0493x9b`
- **Nature / domaine :** `DIAGNOSTIC` / `SURFACE_TENSION`
- **Statut :** Estimateur passif p1 conservé comme baseline; aucune physique capillaire active
- **Confiance :** `A`

Ajoute un champ alphaK réservé à la courbure : une passe binomiale 3x3 sur alpha_x6c, gradient Scharr, normale sortante puis divergence Scharr. L'interface physique reste celle de x6c alpha=0.5; le champ est visualisable directement depuis CUDA.

**Notes.** Le candidat Hessien direct n'est pas retenu car il amplifie le bruit du champ alpha quantifié. x9b-audit2 reste une sous-révision diagnostique et non un jalon autonome.

**Relations :**
- `BUILDS_ON` → `x9a` — Premier scaffold passif de courbure résident
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha

### `x9c` — Qualification du support de lissage de courbure

- **Clé unique :** `0493x9c`
- **ID canonique :** `0493x9c`
- **Nature / domaine :** `QUALIFICATION` / `SURFACE_TENSION`
- **Statut :** Qualification passive; sélectionne p3 pour la courbure de production, sans déplacer l'interface x6c
- **Confiance :** `A`

Compare passivement, avec le même opérateur Scharr, une, deux et trois passes binomiales 3x3 du champ alphaK sur une matrice gamma/rayon. La production retient ensuite p3, soit trois passes, comme compromis de courbure utilisé par x9d.

**Notes.** Le sweep ne modifie ni alpha physique ni phiGamma et n'impose pas de seuil PASS universel; il établit le compromis bruit/biais et la résolution de courbure.

**Relations :**
- `BUILDS_ON` → `x9b` — Courbure passive binomiale + Scharr et LiveVis résident
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha
- `REFERENCES` → `x9d` — Premier saut de Laplace actif dans Q6-g-f

### `x9d` — Premier saut de Laplace actif dans Q6-g-f

- **Clé unique :** `0493x9d`
- **ID canonique :** `0493x9d`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Coeur actif de la capillarité bulk; sigma=0 est un no-op exact
- **Confiance :** `A`

Ajoute surfaceTensionSigma et utilise la courbure p3 qualifiée par x9c pour imposer aux crossings physiques x6f phiGamma_cap=(dt/rhoA_ref)*sigma*kappaGamma, composé avec la pression extérieure x6g. Aucun terme CSF volumique ni kick capillaire particulaire n'est ajouté.

**Notes.** Le champ alpha_x6c et la position alpha=0.5 restent inchangés; seul le potentiel de Dirichlet interfacial reçoit le saut de Laplace. En 2D, la cible circulaire est sigma/R.

**Relations :**
- `BUILDS_ON` → `x9c` — Qualification du support de lissage de courbure
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `REFERENCES` → `x9c` — Qualification du support de lissage de courbure

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X9D_ACTIVE_LAPLACE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9d_static_drop.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9d_static_drop.sh`

### `x9e` — Qualification diagnostique de goutte statique

- **Clé unique :** `0493x9e`
- **ID canonique :** `0493x9e`
- **Nature / domaine :** `DIAGNOSTIC` / `SURFACE_TENSION`
- **Statut :** Diagnostic/qualification au-dessus de x9d; physique inchangée
- **Confiance :** `A`

Ajoute à cadence de résumé des réductions CUDA strictement observationnelles : aire/Reff, pression Q6 cohérente avec la jauge x6g, saut de pression, sigma/Reff, courbure d'interface, résultante capillaire et vitesses liquides/spurious currents.

**Notes.** La pression rapportée est la pression de projection Q6 dans la même jauge que x6g/x9d, pas une pression thermodynamique absolue reconstruite indépendamment.

**Relations :**
- `BUILDS_ON` → `x9d` — Premier saut de Laplace actif dans Q6-g-f
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `REFERENCES` → `x9d` — Premier saut de Laplace actif dans Q6-g-f

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X9E_STATIC_DROP_DIAGNOSTICS.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9e_static_drop.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9e_static_drop.sh`

### `x9f` — Diagnostic de bande interfaciale vraie et relaxation elliptique

- **Clé unique :** `0493x9f`
- **ID canonique :** `0493x9f`
- **Nature / domaine :** `DIAGNOSTIC` / `SURFACE_TENSION`
- **Statut :** Diagnostic de forme/relaxation au-dessus de x9e; aucune modification de la capillarité
- **Confiance :** `A`

Remplace la bande diagnostique alpha 0.1-0.9 par le critère discret de crossing alpha=0.5 et suit COM particulaire, tenseur de moments, rayons principaux, ellipticité et rayons des crossings pour qualifier la relaxation capillaire d'une ellipse vers une goutte circulaire.

**Notes.** Corrige l'ancienne description trop étroite « quadrupole signé » : les observables primaires sont notamment les rayons de moments et le COM réel, avec extrema de crossings comme diagnostics secondaires.

**Relations :**
- `BUILDS_ON` → `x9e` — Qualification diagnostique de goutte statique
- `REFERENCES` → `x9e` — Qualification diagnostique de goutte statique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X9F_ELLIPSE_DIAGNOSTICS.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9f_ellipse_relaxation.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9f_ellipse_relaxation.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x9f_ellipse_relaxation_sweep.sh`

### `x9g` — Généralisation de l'interface aux paires de phases A/B

- **Clé unique :** `0493x9g`
- **ID canonique :** `0493x9g`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Actif; abstraction de paire sans prétendre fournir un solveur immiscible symétrique général
- **Confiance :** `A`
- **Date :** `2026-08-17`
- **Commit :** `240c2e6e0f267f9314aab1634799629ce07f66ab`

Remplace dans la chaîne de production x6c/x6f/x6g/x9d l'hypothèse Liquid/Gas codée en dur par deux sélecteurs A/B. A est le côté alpha-high projeté et fournit masse/référence; B est le côté extérieur et peut sélectionner famille, type explicite ou vacuum. Le chemin historique liquid/gas reste byte-for-byte équivalent dans la qualification.

**Notes.** B=wall est accepté par la grammaire mais volontairement rejeté dans x9g faute de provider géométrique; x9h active ensuite ce cas. Les contraintes x7b/x7c et B1 mono-projeté ne sont pas généralisées ici.

**Relations :**
- `BUILDS_ON` → `x9f` — Diagnostic de bande interfaciale vraie et relaxation elliptique
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5
- `REFERENCES` → `x6g` — Condition de pression gazeuse sur l'interface physique
- `REFERENCES` → `x9d` — Premier saut de Laplace actif dans Q6-g-f

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9g_phase_pair_equivalence.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9g_phase_pair_equivalence.sh`

### `x9h` — Provider géométrique résident de paroi

- **Clé unique :** `0493x9h`
- **ID canonique :** `0493x9h`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Géométrie-only qualifiée; capillarité/mouillage avec B=wall encore interdits à cette étape
- **Confiance :** `A`
- **Date :** `2026-08-17`
- **Commit :** `3c78e280e85b7f220c8b932cad0da04857edfe57`

Active B=wall comme troisième objet géométrique indépendant des phases particulaires : combine parois de domaine et, sur opt-in wallVP, géométrie chi avec S=1-chi; fournit fraction solide et normale murale résidentes sans modifier alpha libre ni imposer encore angle de contact ou saut capillaire liquide/solide.

**Notes.** La normale de mur emploie la même famille Scharr que x9b/x9c. Les BC Q6 de paroi restent autoritaires; x9h ne convertit pas le mur en côté Dirichlet x6f et prépare seulement les étapes de contact-angle x9i+.

**Relations :**
- `BUILDS_ON` → `x9g` — Généralisation de l'interface aux paires de phases A/B

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9h_wall_geometry_provider.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9h_wall_geometry_provider.sh`

### `x9i` — Première fermeture d'angle de contact par normale imposée

- **Clé unique :** `0493x9i`
- **ID canonique :** `0493x9i`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Prototype historique : angle local exact mais biais de div(n)/courbure; conservé comme baseline derrière un gate de test
- **Confiance :** `A`

Introduit phaseInterfaceContactAngleDegrees, mesuré à travers la phase A, et impose dans la bande de contact nAB.nWall=-cos(theta) en remplaçant localement la normale p3. alpha_x6c et le crossing physique x6f restent inchangés.

**Notes.** -1 désactive la fermeture. Le mur reste un troisième objet géométrique fourni par x9h et ne devient pas phase B. La courbure de contact n'était qu'informative à cette étape.

**Relations :**
- `BUILDS_ON` → `x9h` — Provider géométrique résident de paroi
- `REFERENCES` → `x6c` — Infrastructure résidente du champ de phase alpha
- `REFERENCES` → `x6f` — Stencil résident de pression sur l'interface physique alpha=0.5

### `x9j` — Fermeture d'angle par ghost-alpha de courbure

- **Clé unique :** `0493x9j`
- **ID canonique :** `0493x9j`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Prototype historique supplanté : améliore certains angles mais ne préserve pas suffisamment la géométrie multi-couche
- **Confiance :** `A`

Remplace la discontinuité de normale x9i par des échantillons alpha virtuels derrière une paroi statique pendant les trois passes p3 et les dérivées Scharr; la condition de Young est portée par le champ réservé à la courbure.

**Notes.** Le chemin hard-normal x9i reste reproductible sous MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I. x9j ne déplace jamais l'interface physique alpha=0.5.

**Relations :**
- `BUILDS_ON` → `x9i` — Première fermeture d'angle de contact par normale imposée
- `REFERENCES` → `x9i` — Première fermeture d'angle de contact par normale imposée

### `x9k` — Ghost-alpha par miroir cisaillé

- **Clé unique :** `0493x9k`
- **ID canonique :** `0493x9k`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Prototype historique supplanté : angle robuste mais une transformation affine ne préserve pas un cercle, donc biais de courbure angle-dépendant
- **Confiance :** `A`

Prolonge x9j à toutes les profondeurs ghost par réflexion du point à travers le mur puis décalage tangentiel proportionnel à cot(theta), avant interpolation du vrai champ alphaK. À 90 degrés la loi se réduit exactement au miroir ordinaire.

**Notes.** Domaine expérimental strict 0<theta<180; aucune nouvelle clé persistante. alpha_x6c, crossing x6f, sigma, phiGamma, CG et B1 restent inchangés.

**Relations :**
- `BUILDS_ON` → `x9j` — Fermeture d'angle par ghost-alpha de courbure
- `REFERENCES` → `x9j` — Fermeture d'angle par ghost-alpha de courbure

### `x9l` — Reconstruction de normale au mur-face

- **Clé unique :** `0493x9l`
- **ID canonique :** `0493x9l`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Expérience négative hors voisinage de 90 degrés; gardée comme comparaison et supplantée par x9m
- **Confiance :** `A`

Laisse alpha physique et alphaK p3 inchangés, impose la normale de Young au mur physique et reconstruit par rotation les normales du premier centre fluide et du premier ghost à partir d'une normale p3 plus intérieure, avant div(n).

**Notes.** Parois statiques seulement; gate expérimental MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L. Le sweep géométrique ne suffisait pas à rendre la courbure robuste sur toute la plage angulaire.

**Relations :**
- `BUILDS_ON` → `x9k` — Ghost-alpha par miroir cisaillé
- `SUPERSEDED_BY` → `x9m` — Fermeture statique de mouillage par ancre hors support

### `x9m` — Fermeture statique de mouillage par ancre hors support

- **Clé unique :** `0493x9m`
- **ID canonique :** `0493x9m`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Fermeture statique préférée du cycle x9; robuste géométriquement, mais dynamique de ligne triple non universellement fermée
- **Confiance :** `A`

Impose la normale de Young au mur puis évalue la courbure de contact à partir de la première normale p3 hors du support contaminé par paroi (couche j=4, centre 4.5h) et de la corde jusqu'au crossing physique : kappa=2 sin(DeltaPhi/2)/L. Ni alpha ni le champ normal p3 ne sont écrasés.

**Notes.** Qualifiée statiquement sur 30..150 degrés, rayons, interfaces planes/elliptiques et phase de grille. Parois statiques seulement; chi/wallVP et 0/180 degrés exclus. x9p révèle une dynamique quantitative encore imparfaite.

**Relations :**
- `BUILDS_ON` → `x9l` — Reconstruction de normale au mur-face
- `FIXES` → `x9l` — Reconstruction de normale au mur-face

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9m_contact_angle_offsupport.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x9m_offsupport_geometry.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9m_contact_angle_offsupport.sh`

### `x9n` — Qualification géométrique étendue de x9m

- **Clé unique :** `0493x9n`
- **ID canonique :** `0493x9n`
- **Nature / domaine :** `QUALIFICATION` / `SURFACE_TENSION`
- **Statut :** Qualification scripts-only de la robustesse géométrique statique x9m
- **Confiance :** `A`

Teste sans changement de solveur la fermeture x9m sur contacts plans kappa=0, scaling circulaire 1/R sur plusieurs rayons et ellipses à courbure locale variable afin d'écarter un simple ajustement au premier cap circulaire.

**Notes.** 22 cas one-step par défaut. Le chemin physique testé reste exactement x9m; aucune recompilation n'est requise.

**Relations :**
- `BUILDS_ON` → `x9m` — Fermeture statique de mouillage par ancre hors support
- `REFERENCES` → `x9m` — Fermeture statique de mouillage par ancre hors support

### `x9o` — Qualification de phase sous-maille tangentielle de x9m

- **Clé unique :** `0493x9o`
- **ID canonique :** `0493x9o`
- **Nature / domaine :** `QUALIFICATION` / `SURFACE_TENSION`
- **Statut :** Qualification scripts-only; quantifie la sensibilité résiduelle de x9m à la phase sous-maille
- **Confiance :** `A`

Translate tangentiellement de 0, 0.25h, 0.5h et 0.75h les deux géométries x9n les plus sensibles afin de mesurer le biais de phase de grille sans déplacer le mur physique.

**Notes.** Aucun changement C++/CUDA. Le critère porte sur la moyenne des quatre phases, leur demi-étendue et l'erreur absolue basse courbure.

**Relations :**
- `BUILDS_ON` → `x9n` — Qualification géométrique étendue de x9m
- `REFERENCES` → `x9m` — Fermeture statique de mouillage par ancre hors support
- `REFERENCES` → `x9n` — Qualification géométrique étendue de x9m

### `x9p` — Qualification dynamique de goutte sessile x9m

- **Clé unique :** `0493x9p`
- **ID canonique :** `0493x9p`
- **Nature / domaine :** `QUALIFICATION` / `SURFACE_TENSION`
- **Statut :** Résultat dynamique partiel : sens mouillage/démouillage correct, mais équilibre comprimé vers 90 degrés et courbure de ligne triple encore bruitée
- **Confiance :** `A`

Fait évoluer des calottes 60/90/120 degrés et des transitions 90 vers 60/120; reconstruit l'angle global physique indépendamment par COM et moments afin de vérifier sens de mouillage, conservation et approche de la cible.

**Notes.** Qualification-only, sans physique nouvelle. Elle établit la limite importante de x9m : bonne fermeture statique mais pas encore loi dynamique de ligne de contact universelle.

**Relations :**
- `BUILDS_ON` → `x9m` — Fermeture statique de mouillage par ancre hors support

### `x9q` — Test de potentialité jet gravitaire / pincement / impact

- **Clé unique :** `0493x9q`
- **ID canonique :** `0493x9q`
- **Nature / domaine :** `BENCHMARK` / `SURFACE_TENSION`
- **Statut :** Benchmark exploratoire sans seuil physique dur; démontre des changements de topologie et expose la faiblesse de courbure sous-résolue traitée par x9r
- **Confiance :** `A`

Runner-only : injecte un jet liquide par un segment supérieur dans gaz ou vide, sous gravité, pour provoquer langue pendante, col/pincement, chute et impact sur la paroi avec la chaîne capillaire x9.

**Notes.** Le cas est explicitement de potentialité, pas une calibration de temps de breakup, taille de goutte ou Weber critique. Aucun source solveur n'est modifié par x9q.

**Relations :**
- `BUILDS_ON` → `x9m` — Fermeture statique de mouillage par ancre hors support
- `REFERENCES` → `x9d` — Premier saut de Laplace actif dans Q6-g-f
- `REFERENCES` → `x9p` — Qualification dynamique de goutte sessile x9m
- `REFERENCES` → `x9r` — Cutoff de résolution du saut capillaire

### `x9r` — Cutoff de résolution du saut capillaire

- **Clé unique :** `0493x9r`
- **ID canonique :** `0493x9r`
- **Nature / domaine :** `FIX` / `SURFACE_TENSION`
- **Statut :** Correctif actif de courbure sous-résolue; seuil à choisir selon résolution/campagne, non constante physique universelle
- **Confiance :** `A`

Ajoute surfaceTensionMinRadiusCells avec 0 comme no-op exact. Pour N_R>0, borne uniquement la courbure interpolée au crossing utilisée dans sigma*kappa à |kappa|<=1/(N_R min(dx,dy)); alpha, crossing, champ p3 brut et LiveVis restent inchangés.

**Notes.** Motivé par les éjections balistiques du jet lorsque le rayon implicite tombe sous la maille. Le choix historique de développement N_R=3 coupe les singularités locales puis devient transparent au bulk; des campagnes ultérieures emploient aussi 4.

**Relations :**
- `BUILDS_ON` → `x9d` — Premier saut de Laplace actif dans Q6-g-f
- `REFERENCES` → `x9q` — Test de potentialité jet gravitaire / pincement / impact

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9r_limiter.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9r_dripping_jet_cutoff.sh`

### `x9s` — Benchmark paramétrable d'impact et splash

- **Clé unique :** `0493x9s`
- **ID canonique :** `0493x9s`
- **Nature / domaine :** `BENCHMARK` / `SURFACE_TENSION`
- **Statut :** Démonstration/qualification morphologique qualitative; pas une mesure convergée de Weber critique
- **Confiance :** `A`

Construit une goutte initiale paramétrable impactant soit une paroi sèche soit une flaque, avec la même physique bulk/capillaire, afin d'observer étalement, lamelle, rim, splash et interaction liquide-liquide lors de changements de topologie.

**Notes.** Le runner x9s sert ensuite de socle à la série cinétique x9t-x9z et aux campagnes x10-x12. TARGET=wall|puddle ne change pas le backend, seulement l'état initial/cible.

**Relations :**
- `BUILDS_ON` → `x9r` — Cutoff de résolution du saut capillaire

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/generate_0493x9s_splash_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9s_splash.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x9s_splash_puddle.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x9s_splash_wall.sh`

### `x9t` — Première rétention cinétique liquide-vide conservative

- **Clé unique :** `0493x9t`
- **ID canonique :** `0493x9t`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Prototype actif de rétention cinétique; première étape du pont x9 vers la fermeture de surface libre x10
- **Confiance :** `A`

Ajoute une fermeture interne pour les particules de phase A traversant l'interface vers le vide : sélection selon phaseInterfaceKineticReflectionFraction, transformation élastique conservative par groupes candidat/receveur et transmission/évaporation optionnelle.

**Notes.** Le contrôle mathématique vérifie conservation exacte P/K de la transformation à deux groupes. Le runner de qualification utilise une goutte liquide-vide haute kBT où le chemin pré-x9t évaporait visiblement.

**Relations :**
- `BUILDS_ON` → `x9s` — Benchmark paramétrable d'impact et splash

### `x9u` — Extension de la réflexion aux sorties de support

- **Clé unique :** `0493x9u`
- **ID canonique :** `0493x9u`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Étape active intermédiaire; couverture support-edge améliorée mais le choix de bain sera corrigé par x9w
- **Confiance :** `A`

Étend x9t aux sorties de support en distinguant crossings historiques alpha=0.5 et support-exit, et recherche un bain de recul intérieur jusqu'à deux cellules avec bilan exact de quantité de mouvement et énergie.

**Notes.** L'audit partitionne crossings, profondeur du bain 0/1/2, transmissions, réflexions et échecs; r=1 exige une application complète dans le domaine qualifié.

**Relations :**
- `BUILDS_ON` → `x9t` — Première rétention cinétique liquide-vide conservative
- `REFERENCES` → `x9t` — Première rétention cinétique liquide-vide conservative
- `REFERENCES` → `x9w` — Bain de recul strictement bulk

### `x9v` — Diagnostic des voies de fuite de la fermeture x9u

- **Clé unique :** `0493x9v`
- **ID canonique :** `0493x9v`
- **Nature / domaine :** `DIAGNOSTIC` / `FREE_SURFACE_KINETICS`
- **Statut :** Diagnostic passif; aucune nouvelle passe particulaire ni modification de physique
- **Confiance :** `A`

Exécute exactement la physique x9u et instrumente à cadence de résumé les halos, échecs de recherche de bain, bains non bulk, réflexions non appliquées et particules encore sortantes après réflexion.

**Notes.** La campagne identifie notamment qu'un bain de recul peut appartenir au halo occupé tout en restant du côté alpha<0.5, ce qui motive x9w.

**Relations :**
- `BUILDS_ON` → `x9u` — Extension de la réflexion aux sorties de support
- `REFERENCES` → `x9u` — Extension de la réflexion aux sorties de support

### `x9w` — Bain de recul strictement bulk

- **Clé unique :** `0493x9w`
- **ID canonique :** `0493x9w`
- **Nature / domaine :** `FIX` / `FREE_SURFACE_KINETICS`
- **Statut :** Correctif actif de sélection du bain; recherche bornée à deux cellules et conservation P/K maintenue
- **Confiance :** `A`

Corrige x9u après le diagnostic x9v : un bain cinétique receveur doit appartenir au bulk liquide physique alpha>=0.5; un halo occupé n'est plus autorisé à se bootstrapper comme support cohésif.

**Notes.** L'invariant x9w impose supportExitBathAlphaLTHalf=0. Il ne rajoute pas de passe particulaire de production.

**Relations :**
- `BUILDS_ON` → `x9v` — Diagnostic des voies de fuite de la fermeture x9u
- `FIXES` → `x9u` — Extension de la réflexion aux sorties de support
- `REFERENCES` → `x9u` — Extension de la réflexion aux sorties de support
- `REFERENCES` → `x9v` — Diagnostic des voies de fuite de la fermeture x9u

### `x9x` — Réflexion au crossing physique prédit

- **Clé unique :** `0493x9x`
- **ID canonique :** `0493x9x`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Étape active intermédiaire : déclenchement géométrique au crossing physique, sans nouvelle passe globale
- **Confiance :** `A`

Remplace le seul critère de cellule/support par la détection du crossing réel entre la position courante et x+v*dt dans alpha, avec gate d'advection relative (v-u_bulk).n>0 et correction de position au temps de crossing.

**Notes.** Une garde shell d'une cellule subsiste; le contrôle déterministe vérifie l'identité de placement crossing-time.

**Relations :**
- `BUILDS_ON` → `x9w` — Bain de recul strictement bulk

### `x9y` — Côté alpha pointwise et crossing par bissection bornée

- **Clé unique :** `0493x9y`
- **ID canonique :** `0493x9y`
- **Nature / domaine :** `FIX` / `FREE_SURFACE_KINETICS`
- **Statut :** Correctif géométrique actif de x9x; supprime l'aliasing centre-cellule sans buffer ou passe globale supplémentaire
- **Confiance :** `A`

Corrige x9x en évaluant le côté intérieur/extérieur au point de départ plutôt qu'au centre de cellule, puis localise les vrais crossings avec quatre bissections dans la passe d'application et conserve le dernier point connu intérieur.

**Notes.** Le contrôle mathématique borne l'erreur de fraction de crossing à 1/16 tout en garantissant que le dernier point retenu reste intérieur.

**Relations :**
- `BUILDS_ON` → `x9x` — Réflexion au crossing physique prédit
- `FIXES` → `x9x` — Réflexion au crossing physique prédit
- `REFERENCES` → `x9x` — Réflexion au crossing physique prédit

### `x9z` — Réflexion individuelle des donneurs et compensation affine du bain

- **Clé unique :** `0493x9z`
- **ID canonique :** `0493x9z`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Dernière étape x9 du mécanisme de rétention; loi individuelle explicitement réutilisée ensuite par x10a
- **Confiance :** `A`

Individualise la mécanique x9y : chaque particule traversante utilise sa propre normale et est réfléchie spéculairement relativement au même bain; une correction affine collective des receveurs restaure exactement quantité de mouvement et énergie.

**Notes.** Trois passes particulaires historiques seulement, plus une réaction O(Ncell); aucun merge/resampling de nettoyage. L'audit exige que chaque donneur appliqué soit individuellement rentrant et que P/K soient conservés.

**Relations :**
- `BUILDS_ON` → `x9y` — Côté alpha pointwise et crossing par bissection bornée
- `FIXES` → `x9y` — Côté alpha pointwise et crossing par bissection bornée
- `REFERENCES` → `x10a` — Géométrie de crossing et seal du endpoint réfléchi
- `REFERENCES` → `x9y` — Côté alpha pointwise et crossing par bissection bornée

### `0414` — Extension quadriface des open boundaries segmentées

- **Clé unique :** `20260907-0414-segmented-xy`
- **ID canonique :** `20260907-0414-segmented-xy`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** QUALIFIED
- **Confiance :** `A`
- **Date :** `2026-09-07`
- **Commit :** `e2fe1ca29042c2391cd5b6ee7f9eb7fe9a2065a8`

Généralise les entrées/sorties segmentées aux axes x et y sur le chemin CUDA résident; crossing multi-axes chronologique, x8r quadriface, x8t généralisé, x8s séparable 1-D/2-D, gardes de coins/réservoirs et diagnostic low-face corrigé.

**Notes.** Qualification Q1-Q7 et ablation x8s 2-D consolidées. | V4.24 Git reconciliation: surf commit e2fe1ca introduces the qualified segmented x/y CUDA-resident implementation.

**Relations :**
- `EXTENDS` → `x8k` — Inlet segmenté à profil de Poiseuille local
- `EXTENDS` → `x8r` — Outlet de pression Neumann Q6-g-f
- `EXTENDS` → `x8s` — Déflation exacte des modes longitudinaux lents du CG
- `EXTENDS` → `x8t` — Cible de relaxation de densité sans mode moyen à outlet pression
- `REFERENCES` → `x8r` — Outlet de pression Neumann Q6-g-f
- `REFERENCES` → `x8s` — Déflation exacte des modes longitudinaux lents du CG
- `REFERENCES` → `x8t` — Cible de relaxation de densité sans mode moyen à outlet pression

**Artefacts associés :**
- `QUALIFIES` — `scripts/run_0414_segmented_xy_neumann_qualification.sh`

### `0490A` — Registre des espèces

- **Clé unique :** `history:0490a`
- **ID canonique :** `history:0490a`
- **Nature / domaine :** `INFRA` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `cb8a4cbf877449ec0b744bde4b8b5e427b304f81`

Introduit le registre multi-espèces et son échafaudage de diagnostics, base nécessaire aux traitements par espèce ultérieurs.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490B` — Dépôt cellule–espèce

- **Clé unique :** `history:0490b`
- **ID canonique :** `history:0490b`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `545fc6232939afda5e9746d7ff13491d4ff8024a`

Ajoute le dépôt des populations par cellule et par espèce afin de disposer des grandeurs locales nécessaires au resampling multi-espèces.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490C` — Resampling conservatif par espèce

- **Clé unique :** `history:0490c`
- **ID canonique :** `history:0490c`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `58029bd588813ff797c96f73c23267b011bd1ec5`

Introduit le resampling multi-espèces avec conservation explicite des bilans associés aux espèces.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490D` — Fermeture de masse sensible à la phase

- **Clé unique :** `history:0490d`
- **ID canonique :** `history:0490d`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `31666789d28d3a0be5df23705eb340bb249b3253`

Rend la fermeture de masse du resampling consciente de la phase afin de préserver les bilans dans les cellules multi-espèces.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490E` — Garde de population par espèce

- **Clé unique :** `history:0490e`
- **ID canonique :** `history:0490e`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `4601ad492be5f56f083916a70e2a2b85a6f4f593`

Ajoute une garde de population par espèce pour empêcher les états locaux non admissibles lors des opérations de resampling.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490F` — Refill d'espèces mixtes

- **Clé unique :** `history:0490f`
- **ID canonique :** `history:0490f`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `6d9c83f0df4f2cb3cf410acd58fc5b123b25e63b`

Étend le refill aux cellules contenant plusieurs espèces tout en conservant l'identité des populations.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490G` — Transferts donneur–receveur par espèce

- **Clé unique :** `history:0490g`
- **ID canonique :** `history:0490g`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `d30281e7a17c8868ee9206d45c7c57fea7d1f430`

Introduit les transferts donneur–receveur spécifiques aux espèces dans la chaîne de resampling.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490H` — Dépôt cellule–espèce CUDA

- **Clé unique :** `history:0490h`
- **ID canonique :** `history:0490h`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `12c471b1e292b4ffb5c517ac2d4127b2801b82bd`

Porte sur CUDA le dépôt cellule–espèce requis par la chaîne multi-espèces.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490I` — Fermeture de masse multi-espèces CUDA

- **Clé unique :** `history:0490i`
- **ID canonique :** `history:0490i`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-22`
- **Commit :** `1c3f10b537319b5eaccde6a3becb4ab991584051`

Porte sur CUDA la fermeture de masse par espèce de la chaîne de resampling.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490J` — Garde de population multi-espèces CUDA

- **Clé unique :** `history:0490j`
- **ID canonique :** `history:0490j`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-23`
- **Commit :** `5295fc791617dab7188ef98b4c5b27afeb812d75`

Porte sur CUDA la garde de population par espèce.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490K` — Plan de transferts multi-espèces CUDA

- **Clé unique :** `history:0490k`
- **ID canonique :** `history:0490k`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-23`
- **Commit :** `3004c6f98ca74f5e586a8ca52c2832384266f925`

Construit côté CUDA le plan de transferts donneur–receveur utilisé par le resampling multi-espèces.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490L` — Validation du resampling résident multi-espèces

- **Clé unique :** `history:0490l`
- **ID canonique :** `history:0490l`
- **Nature / domaine :** `QUALIFICATION` / `MULTISPECIES_RESAMPLING`
- **Statut :** Qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-23`
- **Commit :** `d0c2de1fbc7a86a1e48704b97c7553d3f492dab9`

Valide l'enchaînement CUDA résident des opérations de resampling multi-espèces avant activation du chemin rapide.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490M` — Chemin rapide résident multi-espèces

- **Clé unique :** `history:0490m`
- **ID canonique :** `history:0490m`
- **Nature / domaine :** `PERF` / `MULTISPECIES_RESAMPLING`
- **Statut :** Optimisation historique
- **Confiance :** `A`
- **Date :** `2026-07-23`
- **Commit :** `3d7ce88b78939ce07060c07986455ba9d4926fd8`

Introduit le fast path CUDA résident pour le resampling multi-espèces afin de réduire les passages par le CPU.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490M-fix2` — Fermeture conservative multi-espèces

- **Clé unique :** `history:0490m-fix2`
- **ID canonique :** `history:0490m-fix2`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correctif historique
- **Confiance :** `A`
- **Date :** `2026-07-23`
- **Commit :** `3d7ce88b78939ce07060c07986455ba9d4926fd8`

Correctif de fermeture conservative du chemin résident multi-espèces, appliqué après le jalon 0490M.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

**Relations :**
- `FIXES` → `0490M` — Chemin rapide résident multi-espèces

### `0490N` — Maintenance résidente multi-espèces

- **Clé unique :** `history:0490n`
- **ID canonique :** `history:0490n`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-23`
- **Commit :** `ab945606f836cc9e95a0f93ec019bd5b984b43cf`

Ajoute les opérations de maintenance résidente nécessaires à la continuité du resampling multi-espèces sur GPU.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0490N-fix1` — Télémétrie résidente par espèce

- **Clé unique :** `history:0490n-fix1`
- **ID canonique :** `history:0490n-fix1`
- **Nature / domaine :** `DIAGNOSTIC` / `MULTISPECIES_RESAMPLING`
- **Statut :** Diagnostic historique
- **Confiance :** `A`
- **Date :** `2026-07-23`
- **Commit :** `db9e0f45f9d0771a2d6dcaa01364d70fb44a2f66`

Ajoute la télémétrie de contrôle des populations et bilans par espèce sur le chemin résident.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

**Relations :**
- `FIXES` → `0490N` — Maintenance résidente multi-espèces

### `0490N-fix2` — Matérialisation des transferts multiples

- **Clé unique :** `history:0490n-fix2`
- **ID canonique :** `history:0490n-fix2`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correctif historique
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `e735f82f86f8a6787f6e48d1cbf2c8d37c79835b`

Correctif de matérialisation de plusieurs transferts par cellule dans la maintenance résidente multi-espèces.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

**Relations :**
- `FIXES` → `0490N` — Maintenance résidente multi-espèces

### `0490P` — Politique cellule sur device / zéro CPU

- **Clé unique :** `history:0490p`
- **ID canonique :** `history:0490p`
- **Nature / domaine :** `PERF` / `MULTISPECIES_RESAMPLING`
- **Statut :** Architecture historique
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `36abd23c9d53667d07cc3a2bda9e612de9c9fd8a`

Finalise la politique de cellule côté device afin que la chaîne de décision du resampling résident ne dépende plus d'une décision CPU.

**Notes.** Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.

### `0491A` — Contrat Q6 sensible à l'espèce

- **Clé unique :** `history:0491a`
- **ID canonique :** `history:0491a`
- **Nature / domaine :** `INFRA` / `SPECIES_Q6`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `a30faac79bc613b410b39d8c8698eabf32285d0b`

Formalise la distribution de correction Q6 par espèce et fournit un référentiel CPU analytique pour vérifier pondérations, conservation barycentrique et modes de repli.

**Notes.** Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l'ancrage numérique est non ambigu.

**Relations :**
- `BUILDS_ON` → `0490P` — Politique cellule sur device / zéro CPU

### `0491B` — Dépôt partagé et shadow CUDA species-Q6

- **Clé unique :** `history:0491b`
- **ID canonique :** `history:0491b`
- **Nature / domaine :** `CODE` / `SPECIES_Q6`
- **Statut :** Jalon historique attesté par documentation technique
- **Confiance :** `B`

Calcule sur GPU les poids et résidus species-Q6 à partir du dépôt cellule-espèce 0490H, en mode shadow sans application dynamique, afin de comparer le calcul CUDA à la référence CPU 0491A.

**Notes.** V4.4 : jalon restauré à partir des archives techniques 0491 et du rapport rétrospectif 0493w1. Aucun SHA n'est forcé en l'absence de candidat Git numérique sûr.

**Relations :**
- `EXTENDS` → `0491A` — Contrat Q6 sensible à l'espèce

### `0491C` — Application CUDA opt-in du Q6 par espèce

- **Clé unique :** `history:0491c`
- **ID canonique :** `history:0491c`
- **Nature / domaine :** `CODE` / `SPECIES_Q6`
- **Statut :** Jalon historique attesté par documentation technique
- **Confiance :** `B`

Introduit l'application pondérée par type dans le chemin Q6 CUDA résident, en remplaçant uniquement l'application particulaire de la correction tout en conservant le dépôt barycentrique, le solveur, les conditions limites et les diagnostics historiques.

**Notes.** V4.4 : jalon restauré à partir des archives techniques 0491 et du rapport rétrospectif 0493w1. Aucun SHA n'est forcé en l'absence de candidat Git numérique sûr.

**Relations :**
- `EXTENDS` → `0491B` — Dépôt partagé et shadow CUDA species-Q6

### `0491D` — Matrice des chemins species-Q6

- **Clé unique :** `history:0491d`
- **ID canonique :** `history:0491d`
- **Nature / domaine :** `QUALIFICATION` / `SPECIES_Q6`
- **Statut :** Qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `a30faac79bc613b410b39d8c8698eabf32285d0b`

Qualifie l'activation du Q6 sensible à l'espèce sur les chemins src, src-resampling, src-q6 et src-q6-resampling avec contrôle des résidus et de la configuration résidente.

**Notes.** Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l'ancrage numérique est non ambigu.

**Relations :**
- `QUALIFIES` → `0491C` — Application CUDA opt-in du Q6 par espèce

### `0491E` — Audit strict du Q6 résident par espèce

- **Clé unique :** `history:0491e`
- **ID canonique :** `history:0491e`
- **Nature / domaine :** `QUALIFICATION` / `SPECIES_Q6`
- **Statut :** Qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `a30faac79bc613b410b39d8c8698eabf32285d0b`

Vérifie le contrat strictement résident du species-Q6 : exécution device-resident, absence de tableaux cellule-espèce hôte, de transfert de poids H2D, de téléchargement complet d'état et de fallback CPU.

**Notes.** Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l'ancrage numérique est non ambigu.

**Relations :**
- `QUALIFIES` → `0491C` — Application CUDA opt-in du Q6 par espèce

### `0491F` — Validation énergie et thermostat du species-Q6

- **Clé unique :** `history:0491f`
- **ID canonique :** `history:0491f`
- **Nature / domaine :** `QUALIFICATION` / `SPECIES_Q6`
- **Statut :** Qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `a30faac79bc613b410b39d8c8698eabf32285d0b`

Compare les modes Q6 commun et pondéré avec et sans thermostat, en contrôlant résidu Q6, conservation de masse, dérive de vitesse moyenne et comportement thermique.

**Notes.** Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l'ancrage numérique est non ambigu.

**Relations :**
- `QUALIFIES` → `0491C` — Application CUDA opt-in du Q6 par espèce

### `0491G` — Qualification frontières ouvertes et Darcy du species-Q6

- **Clé unique :** `history:0491g`
- **ID canonique :** `history:0491g`
- **Nature / domaine :** `QUALIFICATION` / `SPECIES_Q6`
- **Statut :** Qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `a30faac79bc613b410b39d8c8698eabf32285d0b`

Vérifie la compatibilité du chemin Q6 par espèce avec les familles de frontières ouvertes et Darcy-Brinkman tout en maintenant les garanties de résidence GPU et l'absence de fallback CPU.

**Notes.** Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l'ancrage numérique est non ambigu.

**Relations :**
- `QUALIFIES` → `0491C` — Application CUDA opt-in du Q6 par espèce

### `0491H` — Campagne consolidée de validation species-Q6

- **Clé unique :** `history:0491h`
- **ID canonique :** `history:0491h`
- **Nature / domaine :** `QUALIFICATION` / `SPECIES_Q6`
- **Statut :** Qualification historique consolidée
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `a30faac79bc613b410b39d8c8698eabf32285d0b`

Consolide les validations de chemins, résidence stricte, énergie, frontières/Darcy, cas personnalisés et runs longs, avec contrôles de masse par espèce, résidu Q6, allocations et coûts par nombre d'espèces.

**Notes.** Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l'ancrage numérique est non ambigu.

**Relations :**
- `CONSOLIDATES` → `0491D` — Matrice des chemins species-Q6
- `CONSOLIDATES` → `0491E` — Audit strict du Q6 résident par espèce
- `CONSOLIDATES` → `0491F` — Validation énergie et thermostat du species-Q6
- `CONSOLIDATES` → `0491G` — Qualification frontières ouvertes et Darcy du species-Q6

### `0491H-fix1` — Correctif final et qualification approfondie species-Q6

- **Clé unique :** `history:0491h-fix1`
- **ID canonique :** `history:0491h-fix1`
- **Nature / domaine :** `FIX` / `SPECIES_Q6`
- **Statut :** Correctif historique qualifié
- **Confiance :** `A`
- **Date :** `2026-07-24`
- **Commit :** `2fb9c30bde70017f10b2f30ec6682d1d6c794f71`

Consolide le correctif final du chemin Q6 sensible aux espèces par une qualification approfondie : longueurs exactes, équivalence d'état, thermostat, interface, espèce trace, runs fermés longs et politique cellule device issue de 0490P.

**Notes.** Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l'ancrage numérique est non ambigu.

**Relations :**
- `FIXES` → `0491H` — Campagne consolidée de validation species-Q6

### `0492` — Refresh et contrat des run_ok

- **Clé unique :** `history:0492`
- **ID canonique :** `history:0492`
- **Nature / domaine :** `INFRA` / `RUN_OK_INFRA`
- **Statut :** Infrastructure runner historique qualifiée
- **Confiance :** `A`
- **Date :** `2026-07-25`
- **Commit :** `aa0a4a0a42f3370f920ae2e1fa1bcb4939ec9140`

Consolide les runners run_ok autour d'une base commune, d'un preflight homogène et du contrat LiveVis, tout en intégrant la chaîne multi-espèces résidente issue de 0490/0491. Les sous-révisions internes 0492a et 0492b portent respectivement la résolution du mode résident et les contrôles sémantiques des injections multi-espèces.

**Notes.** Curation historique de l'umbrella 0492. Les marqueurs 0492a/0492b restent des sous-révisions techniques et ne sont pas promus comme jalons canoniques autonomes.

**Relations :**
- `BUILDS_ON` → `0490P` — Politique cellule sur device / zéro CPU
- `BUILDS_ON` → `0491H-fix1` — Correctif final et qualification approfondie species-Q6

### `0493A` — Routage universel du resampling multi-espèces résident

- **Clé unique :** `history:0493a`
- **ID canonique :** `history:0493a`
- **Nature / domaine :** `INFRA` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-25`
- **Commit :** `aa0a4a0a42f3370f920ae2e1fa1bcb4939ec9140`

Étend la chaîne résidente 0490M/N/P à toutes les familles de frontières supportées, supprime le routage topology-only et garde Q6, Darcy, thermostat et règles de split/merge physiquement inchangés.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `BUILDS_ON` → `0490P` — Politique cellule sur device / zéro CPU
- `BUILDS_ON` → `0492` — Refresh et contrat des run_ok

### `0493B` — Resampling CUDA résident activable par espèce

- **Clé unique :** `history:0493b`
- **ID canonique :** `history:0493b`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-25`
- **Commit :** `7da2eec236570f31f51814e186cbed30227273e4`

Ajoute une politique de mutation par espèce tout en conservant toutes les espèces dans SRC, Q6, Darcy, frontières et dépôts barycentriques; la production reste zéro-CPU pour les décisions cellule/espèce.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `EXTENDS` → `0493A` — Routage universel du resampling multi-espèces résident

### `0493C` — Qualification du resampling multi-espèces résident

- **Clé unique :** `history:0493c`
- **ID canonique :** `history:0493c`
- **Nature / domaine :** `QUALIFICATION` / `MULTISPECIES_RESAMPLING`
- **Statut :** Qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-25`
- **Commit :** `95eda1899e8b88be4287aa894cbfb4ddb01b0cbf`

Qualifie le chemin résident sur une matrice périodique, frontières segmentées et Darcy/chi, avec activité effective, intégrité du pool, conservation de masse par espèce et absence de mutation des espèces désactivées.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `QUALIFIES` → `0493B` — Resampling CUDA résident activable par espèce

### `0493C-fix3` — Alignement du population guard medium sur gamma

- **Clé unique :** `history:0493c-fix3`
- **ID canonique :** `history:0493c-fix3`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correctif historique attesté par Git
- **Confiance :** `A`
- **Date :** `2026-07-25`
- **Commit :** `1a705cb78eb175d743da0429fd5ab163e7eedd87`

Corrige la qualification medium de 0493C afin que les seuils de population restent cohérents avec gamma et ne créent pas un faux régime de garde.

**Notes.** Jalon sans README dédié survivant; conservé car explicitement attesté par le code et/ou le graphe Git. Aucun jalon manquant n'est synthétisé.

**Relations :**
- `FIXES` → `0493C` — Qualification du resampling multi-espèces résident

### `0493D` — Sélection parallèle déterministe des transferts résidents

- **Clé unique :** `history:0493d`
- **ID canonique :** `history:0493d`
- **Nature / domaine :** `PERF` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon d'optimisation attesté par le code
- **Confiance :** `B`

Remplace la recherche sérielle plan×particules par une sélection parallèle par groupes indépendants donneur/type, tout en reconstruisant l'ordre global historique des opérations.

**Notes.** Jalon sans README dédié survivant; conservé car explicitement attesté par le code et/ou le graphe Git. Aucun jalon manquant n'est synthétisé.

**Relations :**
- `OPTIMIZES` → `0493B` — Resampling CUDA résident activable par espèce

### `0493D-fix1` — Rejeu déterministe du state-update après sélection parallèle

- **Clé unique :** `history:0493d-fix1`
- **ID canonique :** `history:0493d-fix1`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correctif historique attesté par Git
- **Confiance :** `A`
- **Date :** `2026-07-26`
- **Commit :** `95f408ab1a215cccdc0255b9b5f1a69027eaa681`

Conserve la sélection parallèle de 0493D mais rejoue mutations et réductions diagnostiques dans l'ordre historique pour préserver exactement l'arithmétique et la déterminisme du chemin 0490M.

**Notes.** Jalon sans README dédié survivant; conservé car explicitement attesté par le code et/ou le graphe Git. Aucun jalon manquant n'est synthétisé.

**Relations :**
- `FIXES` → `0493D` — Sélection parallèle déterministe des transferts résidents

### `0493E` — Qualification physique mono-espèce du resampling

- **Clé unique :** `history:0493e`
- **ID canonique :** `history:0493e`
- **Nature / domaine :** `QUALIFICATION` / `MULTISPECIES_RESAMPLING`
- **Statut :** Qualification physique historique
- **Confiance :** `A`
- **Date :** `2026-07-26`
- **Commit :** `7c5e63290ff477de6edb1ccafdbc28a3119fa66b`

Teste le resampling résident mono-espèce sur un état contrôlé avec conservation masse/impulsion/énergie, activité split/merge et invariants de pool.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `QUALIFIES` → `0493D-fix1` — Rejeu déterministe du state-update après sélection parallèle

### `0493F` — Qualification physique à deux espèces du resampling

- **Clé unique :** `history:0493f`
- **ID canonique :** `history:0493f`
- **Nature / domaine :** `QUALIFICATION` / `MULTISPECIES_RESAMPLING`
- **Statut :** Qualification physique historique
- **Confiance :** `A`
- **Date :** `2026-07-26`
- **Commit :** `7c5e63290ff477de6edb1ccafdbc28a3119fa66b`

Étend la qualification physique à deux espèces et aux activations sélectives, afin de contrôler séparément conservation globale et conservation par espèce pendant les mutations résidentes.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `QUALIFIES` → `0493D-fix1` — Rejeu déterministe du state-update après sélection parallèle

### `0493F-fix2` — Cas deux-espèces physiquement neutre

- **Clé unique :** `history:0493f-fix2`
- **ID canonique :** `history:0493f-fix2`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correctif de qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-26`
- **Commit :** `7c5e63290ff477de6edb1ccafdbc28a3119fa66b`

Remplace le checkerboard initial par un état où les champs de masse, impulsion et énergie par espèce sont uniformes malgré les variations de population, afin que le smoke mesure la mutation numérique sans forçage physique parasite.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `FIXES` → `0493F` — Qualification physique à deux espèces du resampling

### `0493G` — Restauration locale des moments par espèce

- **Clé unique :** `history:0493g`
- **ID canonique :** `history:0493g`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correction physique historique
- **Confiance :** `A`
- **Date :** `2026-07-26`
- **Commit :** `7c5e63290ff477de6edb1ccafdbc28a3119fa66b`

Restaure indépendamment les moments thermodynamiques de chaque espèce mutable autour de son propre barycentre; évite l'échange artificiel de quantité de mouvement et d'énergie créé par la restauration sur barycentre de mélange.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `FIXES` → `0493F-fix2` — Cas deux-espèces physiquement neutre

### `0493H` — Diagnostic physique par onde de cisaillement périodique

- **Clé unique :** `history:0493h`
- **ID canonique :** `history:0493h`
- **Nature / domaine :** `QUALIFICATION` / `MULTISPECIES_RESAMPLING`
- **Statut :** Diagnostic physique historique
- **Confiance :** `A`
- **Date :** `2026-07-26`
- **Commit :** `6ee2e45825efd7fdf13b04898c89876be8a82932`

Compare SRC et SRC+resampling sur une onde de cisaillement périodique. Le jalon vérifie décroissance/viscosité et intégrité mais met aussi en évidence les dérives de masse, impulsion et énergie du chemin resampling avant les fermetures I/J.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `QUALIFIES` → `0493G` — Restauration locale des moments par espèce

### `0493I` — Fermeture conservative mono-espèce sur le chemin résident

- **Clé unique :** `history:0493i`
- **ID canonique :** `history:0493i`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correctif physique attesté par le code
- **Confiance :** `B`

Étend la balance conservative masse/impulsion de 0490I au cas d'une seule espèce enregistrée; supprime la dérive d'impulsion introduite par l'ancien branchement mass-only lorsque speciesCount=1.

**Notes.** Jalon sans README dédié survivant; conservé car explicitement attesté par le code et/ou le graphe Git. Aucun jalon manquant n'est synthétisé.

**Relations :**
- `FIXES` → `0493H` — Diagnostic physique par onde de cisaillement périodique

### `0493J` — Fermeture conservative de l'énergie cinétique par espèce

- **Clé unique :** `history:0493j`
- **ID canonique :** `history:0493j`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-26`
- **Commit :** `6ee2e45825efd7fdf13b04898c89876be8a82932`

Ajoute à la fermeture résidente la conservation de l'énergie cinétique relative par espèce, avec diagnostics de faisabilité et résidu; cette fermeture devient un invariant contrôlé dans les qualifications de transport ultérieures.

**Notes.** Jalon historique 0493 documenté par README et/ou qualification dédiée.

**Relations :**
- `EXTENDS` → `0493I` — Fermeture conservative mono-espèce sur le chemin résident

### `0493O0` — Références SRC seules avant réparation locale du support

- **Clé unique :** `history:0493o0`
- **ID canonique :** `history:0493o0`
- **Nature / domaine :** `BENCHMARK` / `MULTISPECIES_RESAMPLING`
- **Statut :** Référence historique pré-réparation
- **Confiance :** `A`
- **Date :** `2026-07-27`
- **Commit :** `eac470a5cca38583a77cfd7d63fa24576fef3af5`

Établit deux références SRC-only sans Q6 ni resampling mutant : Taylor--Green périodique et cas segmented inlet/outlet avec obstacle Darcy/chi. Les diagnostics de support restent passifs afin de mesurer le problème avant toute réparation.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `BUILDS_ON` → `0493J` — Fermeture conservative de l'énergie cinétique par espèce

### `0493O1` — Population effective cible : split local piloté par Neff

- **Clé unique :** `history:0493o1`
- **ID canonique :** `history:0493o1`
- **Nature / domaine :** `CODE` / `MULTISPECIES_RESAMPLING`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-28`
- **Commit :** `d57a68bb6fed3b9996b2e08eeef8ddb1c218d667`

Introduit le mode résident split-only piloté par Neff=(sum m)^2/sum(m^2) pour chaque paire cellule/espèce active. Une paire pauvre est réparée vers NTarget par scission déterministe des fragments les plus lourds, avec conservation locale masse, impulsion et énergie cinétique.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `BUILDS_ON` → `0493O0` — Références SRC seules avant réparation locale du support

### `0493O1-fix2` — Autorité CUDA du split-only local

- **Clé unique :** `history:0493o1-fix2`
- **ID canonique :** `history:0493o1-fix2`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Correctif de sûreté résident attesté par le code
- **Confiance :** `A`
- **Date :** `2026-07-28`
- **Commit :** `d57a68bb6fed3b9996b2e08eeef8ddb1c218d667`

Rend le guard CUDA split-only autoritaire et interdit le repli vers l'ancien population guard CPU. Ce repli pouvait appliquer des merges malgré extraction=false et créer des trous dans l'active prefix avant resynchronisation.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `FIXES` → `0493O1` — Population effective cible : split local piloté par Neff

### `0493O2-fix1` — Runner TG mono/dual-espèces pour la réparation de support

- **Clé unique :** `history:0493o2-fix1`
- **ID canonique :** `history:0493o2-fix1`
- **Nature / domaine :** `FIX` / `MULTISPECIES_RESAMPLING`
- **Statut :** Sous-jalon historique explicitement attesté
- **Confiance :** `A`
- **Date :** `2026-07-28`
- **Commit :** `d57a68bb6fed3b9996b2e08eeef8ddb1c218d667`

Étend le runner TG de O1 à un mode dual-espèces contrôlé : seul le tableau des types est réécrit en répartition locale équilibrée, tandis que positions, vitesses, masses et rôles restent identiques à l'état TG de référence. Aucun jalon O2 de base n'est reconstruit.

**Notes.** Le label survivant est explicitement 0493O2-fix1; aucun 0493O2 autonome n'est créé sans preuve.

**Relations :**
- `EXTENDS` → `0493O1-fix2` — Autorité CUDA du split-only local

### `0493O3` — Early-exit résident lorsqu'aucune paire cellule/espèce n'est pauvre

- **Clé unique :** `history:0493o3`
- **ID canonique :** `history:0493o3`
- **Nature / domaine :** `PERF` / `MULTISPECIES_RESAMPLING`
- **Statut :** Optimisation résidente historique
- **Confiance :** `A`
- **Date :** `2026-07-28`
- **Commit :** `d57a68bb6fed3b9996b2e08eeef8ddb1c218d667`

Ajoute une détection anticipée des paires pauvres. Si aucune réparation n'est requise, le chemin évite préparation cinétique, collecte de candidats, planification, mutation et contrôles post-mutation, tout en exposant des chronométrages dédiés.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `OPTIMIZES` → `0493O1-fix2` — Autorité CUDA du split-only local

### `0493O4` — Qualification de la réparation de support en segmented-Darcy

- **Clé unique :** `history:0493o4`
- **ID canonique :** `history:0493o4`
- **Nature / domaine :** `QUALIFICATION` / `MULTISPECIES_RESAMPLING`
- **Statut :** Qualification historique
- **Confiance :** `A`
- **Date :** `2026-07-28`
- **Commit :** `b65b44b295370ab797d6a44b79972d20d5bd8f82`

Restaure une comparaison appariée baseline/réparation sur le cas segmented inlet/outlet + Darcy/chi, avec registre d'espèces strict, split-only activable, empty-refill/mass-guard/thermal-renormalization désactivés et paramètres identiques hors réparation.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `QUALIFIES` → `0493O3` — Early-exit résident lorsqu'aucune paire cellule/espèce n'est pauvre

### `0493W0` — Audit du régime cinétique du cas segmented-Darcy

- **Clé unique :** `history:0493w0`
- **ID canonique :** `history:0493w0`
- **Nature / domaine :** `BENCHMARK` / `SRC_CALIBRATION`
- **Statut :** Diagnostic historique du régime cinétique
- **Confiance :** `A`
- **Date :** `2026-07-28`
- **Commit :** `fcd24d9724e0299bf309b92dd94116b4b85d0ee0`

Balaye le régime SRC-only du cas cylindre/Darcy pour déterminer si lip d'entrée et wake appauvri proviennent d'un régime mésoscopique extrême avant d'attribuer ces effets à un défaut de support. Q6 et réparations mutantes restent désactivés.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `BUILDS_ON` → `0493O4` — Qualification de la réparation de support en segmented-Darcy

### `0493W1` — Calibrateur constitutif du fluide SRC

- **Clé unique :** `history:0493w1`
- **ID canonique :** `history:0493w1`
- **Nature / domaine :** `CALIBRATOR` / `SRC_CALIBRATION`
- **Statut :** Calibrateur historique
- **Confiance :** `A`
- **Date :** `2026-07-28`
- **Commit :** `fcd24d9724e0299bf309b92dd94116b4b85d0ee0`

Caractérise le fluide SRC homogène par Taylor--Green pour la viscosité, réponse longitudinale pour la célérité acoustique et MSD pour l'autodiffusion; en déduit notamment Sc et, lorsque les échelles sont fournies, Re/Ma/Pe.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `CALIBRATES` → `0493W0` — Audit du régime cinétique du cas segmented-Darcy

### `0493W2` — Référence segmented-Darcy sur fluide SRC calibré

- **Clé unique :** `history:0493w2`
- **ID canonique :** `history:0493w2`
- **Nature / domaine :** `BENCHMARK` / `SRC_CALIBRATION`
- **Statut :** Référence physique calibrée
- **Confiance :** `A`
- **Date :** `2026-07-30`
- **Commit :** `16ba34f537bf142b4f875ba0c5d99c6b55fefc73`

Rejoue le cylindre avec entrée/sortie segmentées et Darcy/chi en conservant la taille de cellule et les propriétés mesurées en W1. Le cas devient une référence physique dimensionnée, avec support repair, resampling, refill et reconditionnement désactivés.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `BUILDS_ON` → `0493W1` — Calibrateur constitutif du fluide SRC

### `0493W3` — Correction de l'injection sur cellule partielle d'une entrée segmentée

- **Clé unique :** `history:0493w3`
- **ID canonique :** `history:0493w3`
- **Nature / domaine :** `FIX` / `BOUNDARY`
- **Statut :** Correctif historique attesté par Git
- **Confiance :** `A`
- **Date :** `2026-07-30`
- **Commit :** `9355b6be19ec9442201e4d8d3a5eb58a0d955495`

Corrige le traitement des cellules partielles au bord d'une aperture d'entrée segmentée afin que l'injection prescrite reste cohérente avec la fraction effectivement ouverte. Le jalon est conservé par son commit Git explicite.

**Notes.** Jalon conservé par un commit Git explicitement nommé; aucun artefact numéroté survivant n'est requis.

**Relations :**
- `FIXES` → `0493W2` — Référence segmented-Darcy sur fluide SRC calibré

### `0493W4` — Runner d'injection multi-espèces normalisé par famille de phase

- **Clé unique :** `history:0493w4`
- **ID canonique :** `history:0493w4`
- **Nature / domaine :** `RUNNER` / `MULTISPECIES_RUNNER`
- **Statut :** Jalon de runner attesté par le code et les inventaires
- **Confiance :** `B`

Normalise les runners d'injection autour des familles liquid/gas plutôt que des seuls identifiants de type : forces Q6 et fermeture de masse déclarées, rapport de masses, domaine empty/full, diagnostics species et contrat de post-check deviennent explicites et indépendants du numéro de type.

**Notes.** Jalon conservé par sémantique numérotée dans le runner/code et inventaires; confiance canonique B en l'absence de commit/README dédié.

**Relations :**
- `BUILDS_ON` → `0492` — Refresh et contrat des run_ok
- `BUILDS_ON` → `0493W3` — Correction de l'injection sur cellule partielle d'une entrée segmentée

### `0493W5` — Q6 multi-espèces independent_masked — étape périodique

- **Clé unique :** `history:0493w5`
- **ID canonique :** `history:0493w5`
- **Nature / domaine :** `CODE` / `SPECIES_Q6`
- **Statut :** Jalon historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-30`
- **Commit :** `b389834cef3926adb2d1db68ff25b2227757dd16`

Introduit speciesQ6Mode=independent_masked : chaque espèce de force Q6 positive construit son propre support à partir de l'occupation mass/referenceCellMass et reçoit son propre solveur masqué; une espèce de force nulle ne reçoit structurellement aucune correction Q6 directe. L'étape initiale est périodique.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `BUILDS_ON` → `0493W4` — Runner d'injection multi-espèces normalisé par famille de phase
- `EXTENDS` → `0491C` — Application CUDA opt-in du Q6 par espèce

### `0493W6` — Diagnostic de divergence après application du Q6 masqué

- **Clé unique :** `history:0493w6`
- **ID canonique :** `history:0493w6`
- **Nature / domaine :** `DIAGNOSTIC` / `SPECIES_Q6`
- **Statut :** Diagnostic historique documenté
- **Confiance :** `A`
- **Date :** `2026-07-30`
- **Commit :** `b389834cef3926adb2d1db68ff25b2227757dd16`

Distingue la divergence du flux de face auxiliaire projeté de celle du champ cellulaire redéposé après correction particulaire. Ce diagnostic révèle notamment le mismatch face-vers-cellule aux bords internes d'un support partiellement masqué sans modifier l'opérateur.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `DIAGNOSES` → `0493W5` — Q6 multi-espèces independent_masked — étape périodique

### `0493W7` — Q6 independent_masked sur toutes les familles de frontières résidentes

- **Clé unique :** `history:0493w7`
- **ID canonique :** `history:0493w7`
- **Nature / domaine :** `CODE` / `SPECIES_Q6`
- **Statut :** Jalon historique documenté et qualifié
- **Confiance :** `A`
- **Date :** `2026-07-30`
- **Commit :** `b389834cef3926adb2d1db68ff25b2227757dd16`

Étend le solveur Q6 indépendant par espèce aux topologies déjà acceptées par le backend résident : périodique, canal à parois, entrée/sortie pleine face, apertures segmentées et Darcy-Brinkman, sans réintroduire correction barycentrique ni fallback common.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `BUILDS_ON` → `0493W6` — Diagnostic de divergence après application du Q6 masqué
- `EXTENDS` → `0493W5` — Q6 multi-espèces independent_masked — étape périodique

### `0493W8` — Équivalence Taylor--Green mono / dual-identique du Q6 independent_masked

- **Clé unique :** `history:0493w8`
- **ID canonique :** `history:0493w8`
- **Nature / domaine :** `QUALIFICATION` / `SPECIES_Q6`
- **Statut :** Qualification historique consolidée
- **Confiance :** `A`
- **Date :** `2026-07-30`
- **Commit :** `caa5b6b632fdff297658e7a989b78452a55d6b87`

Qualifie la neutralité du registre et du découpage en types, la non-régression du solveur independent_masked en support plein face au Q6 mono historique, et le transport TG de deux labels indépendamment projetés représentant le même fluide.

**Notes.** Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.

**Relations :**
- `QUALIFIES` → `0493W7` — Q6 independent_masked sur toutes les familles de frontières résidentes

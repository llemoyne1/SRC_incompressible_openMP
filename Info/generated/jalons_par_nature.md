# Jalons par nature

## ABLATION

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x7a/x7b` | Kick viriel de densité | Q6_GF | Rejeté dans Q6-g-f; mutuellement exclusif avec x7d |
| `x9i-x9l` | Prototypes angle de contact | SURFACE_TENSION | Ablations/supplantés |
| `x10j` | Réflexion spéculaire labo | FREE_SURFACE_KINETICS | Ablation rejetée: bloque fortement le dripping |
| `x10k` | Réflexion spéculaire repère interface | FREE_SURFACE_KINETICS | Ablation rejetée |
| `x10m` | Paroi implicite mobile / scratch | FREE_SURFACE_KINETICS | Ablation/infrastructure |
| `x10r` | Vitesses endpoints full-vector | FREE_SURFACE_KINETICS | Ablation rejetée: dripping dégradé |
| `x10s` | Cinématique normale au segment | FREE_SURFACE_KINETICS | Ablation rejetée/OFF |
| `x10t` | Cinématique tangentielle rigide | FREE_SURFACE_KINETICS | Ablation rejetée; impulse parasite aggravée |
| `x13o` | Swap normal-only | TRANSPORT_SURFACE | OFF production |
| `x13t` | Refroidissement progressif unifié | TRANSPORT_SURFACE | Rejetée comme chemin général |
| `x13u/x13v` | Rétention one-for-one sous x13t | TRANSPORT_SURFACE | Expérimental/rejeté |
| `x13w` | Escape -> inactive -> reseed | TRANSPORT_SURFACE | Rejeté: contraction artificielle du support |
| `x14n` | Ablation fermeture gaz OFF | LIQUID_GAS | Ablation |
| `x14o` | Ablation pression gaz constante | LIQUID_GAS | Ablation |
| `x14y` | Ablation sans soustraction p_g | LIQUID_GAS | Rejeté: double comptage pression équilibre |
| `x14z` | Fermeture géométrique p_ref | LIQUID_GAS | Rejeté comme cause du défaut n=1 |

## ANALYZER

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x8j` | Analyse VK POD + sondes | OPEN_BOUNDARY | Tooling/qualification, pas une physique |
| `x14r` | Analyse volume accessible | LIQUID_GAS | Diagnostic conduisant à x14s |

## BENCHMARK

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x7i` | Qualification multi-conditions-limites | Q6_GF | Benchmark de référence |
| `x9r` | Cutoff de petite courbure résolue | SURFACE_TENSION | Actif selon benchmark; paramètre de résolution |
| `x9s` | Impact/splash paramétrable | SURFACE_TENSION | Démonstration/qualification qualitative |
| `x12b/x12c` | Construction benchmark JFM | FREE_SURFACE_KINETICS | Tooling historique |
| `x12d` | Benchmark JFM 524 | FREE_SURFACE_KINETICS | Benchmark applicatif; similitude Re encore limitée |
| `x13k` | Goutte oscillante n=2 | TRANSPORT_SURFACE | Qualifié historique |
| `x13l` | Goutte oscillante n=3 | TRANSPORT_SURFACE | Qualifié historique |
| `x13m` | Goutte oscillante n=4 | TRANSPORT_SURFACE | Qualifié historique |
| `x13n` | Taylor-Culick 2D | TRANSPORT_SURFACE | Limite dynamique connue; référence G_TC ~0.795 au rollback |
| `x13r/x13s` | Refroidissements locaux directs | TRANSPORT_SURFACE | Rejetées |
| `x13x` | Rétention probabiliste | TRANSPORT_SURFACE | Aucun compromis robuste |
| `x13z` | Changements de grille | TRANSPORT_SURFACE | Non suffisant pour validation |
| `x14j` | Goutte deux températures | LIQUID_GAS | Benchmark d'intégration |
| `x14t` | Piston pression thermodynamique | LIQUID_GAS | Qualification composante thermodynamique |
| `x14u` | Gaz incident normal | LIQUID_GAS | Diagnostic conduisant à x14v |
| `x14w` | Couette biphasique | LIQUID_GAS | PASS-like sur contrainte tangentielle |
| `x14x` | Goutte oscillante diphasique n=2 | LIQUID_GAS | Qualification intégrée/tooling |
| `x14ag` | Traînée avec inlet/outlet | LIQUID_GAS | Abandonné |
| `x14ah` | Traînée périodique-x | LIQUID_GAS | Benchmark intégré |
| `x14aj` | Goutte oscillante n=3 avec gaz | LIQUID_GAS | REVIEW: fréquence ~12% lente dans campagne actuelle |
| `x14ak` | Taylor-Culick diphasique - fluide x14 | LIQUID_GAS | REVIEW; ne pas utiliser pour isoler effet gaz |
| `x14al` | Taylor-Culick apparié au point x13h | LIQUID_GAS | Contrôle liquide reproduit; branche gaz à relire car EOS global kBT avait été mal aligné dans le premier runner |

## CALIBRATOR

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x12cal` | Calibrateur dynamique capillaire | FREE_SURFACE_KINETICS | Qualification dynamique |
| `x12yl` | Calibrateur mécanique de sigma | FREE_SURFACE_KINETICS | Qualification mécanique historique |
| `x13d` | Longue longueur d'onde / acoustique | TRANSPORT_SURFACE | Calibration |

## CODE

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `SRC/MPCD` | Collision particulaire SRC/MPCD | CORE | Socle actif |
| `Q6` | Projection quasi-incompressible | CORE | Socle actif selon RUN_MODE |
| `Q9` | Relaxation basse fréquence du flux de masse | CORE | Historique / séparée du chemin Q6-g-f actuel |
| `Q6-g` | Q6 force-aware | CORE | Introduit par x3, base de Q6-g-f |
| `Q6-g-f` | Q6 force-aware + interface + face-particule + densité | CORE | Chaîne de projection de référence |
| `x1` | Jalon ancien non individualisé dans le rapport consolidé | CORE | À retrouver dans l'historique Git si nécessaire |
| `x2` | Test Q6 liquide seul / gravité | CORE | Historique; mène à x3 |
| `x3` | Q6-g force-aware - preuve de concept | Q6_GF | Supplanté par x4a/x4b |
| `x4a` | prestream_single | Q6_GF | Supplanté par x4b |
| `x4b` | prestream_single_fused | Q6_GF | Séquençage de référence Q6-g-f |
| `x5a` | free_surface_masked initial | Q6_GF | Étape historique |
| `x5b` | Gaz explicite compressible | Q6_GF | Base du couplage gaz |
| `x6c` | Alpha physique résident | Q6_GF | Actif, base géométrique Q6/capillarité |
| `x6d` | Distance sous-maille 1/theta | Q6_GF | Supplanté par x6f |
| `x6f` | Stencil physique d'interface | Q6_GF | Actif |
| `x6g` | Pression gazeuse interfaciale | Q6_GF | Actif quand gaz explicite |
| `x6h-A` | Reconstruction faces basses | Q6_GF | Actif dans Q6-g-f |
| `x6h-B1` | Reconstruction face-particule RT0 | Q6_GF | Actif dans Q6-g-f |
| `x7d` | Relaxation de densité dans le RHS | Q6_GF | Actif; tau_rho=0.25 dans profil qualifié |
| `x7f` | Extension multi-topologies | Q6_GF | Actif |
| `x7g` | Darcy avant projection | Q6_GF | Actif selon mode Darcy |
| `x7m` | Correction topologie monophase | Q6_GF | Actif automatiquement |
| `x7o` | Symétrisation Q6 indépendant | Q6_GF | Actif |
| `x7p` | Symétrisation Q6 commun | Q6_GF | Actif |
| `x7q` | Fermeture exacte du moment périodique | Q6_GF | Actif automatiquement seulement dans son domaine; pas sur dam-break partiel |
| `x8k` | Inlet segmenté Poiseuille local | OPEN_BOUNDARY | Actif |
| `x8q` | Continuation cinétique outlet | OPEN_BOUNDARY | Actif pour outlet Neumann |
| `x8r` | Outlet pression Neumann | OPEN_BOUNDARY | Actif |
| `x8t` | Relaxation densité sans mode moyen | OPEN_BOUNDARY | Actif dans cas applicable |
| `x9a-x9c` | Choix de la géométrie de courbure | SURFACE_TENSION | Étapes de sélection; p3 retenu |
| `x9d` | Activation du saut de Laplace | SURFACE_TENSION | Actif; coeur de la tension superficielle |
| `x9g` | Sélecteurs de phases A/B | SURFACE_TENSION | Actif |
| `x9h` | Géométrie de paroi pour mouillage | SURFACE_TENSION | Actif dans mouillage |
| `x9m` | Fermeture statique de mouillage | SURFACE_TENSION | Bonne statique; dynamique ligne triple non fermée |
| `x10a-x10e` | Premières barrières / seals / réactions | FREE_SURFACE_KINETICS | Historique, supplanté |
| `x10f-x10g` | Réaction conservative globale | FREE_SURFACE_KINETICS | Code conservé sans call-site actif |
| `x10o` | Paroi thermique / enveloppe locale | FREE_SURFACE_KINETICS | Socle actif de la fermeture liquide x12 |
| `x10p/x10q` | Résolution recouvrements initiaux | FREE_SURFACE_KINETICS | Actif |
| `x10cic` | Alpha cinétique CIC dédié | FREE_SURFACE_KINETICS | Actif; orchestration encore liée à Q6 |
| `x10biq / Q2` | Reconstruction biquadratique tensorielle | FREE_SURFACE_KINETICS | Actif |
| `x10u` | Relocalisation one-for-one | FREE_SURFACE_KINETICS | Actif dans chaîne liquide qualifiée |
| `x10v` | Swap local full-vector | FREE_SURFACE_KINETICS | Actif; peut ajouter dispersion/dissipation interfaciale |
| `x10w` | Limiter thermique pairwise | FREE_SURFACE_KINETICS | Implémenté mais OFF; exclusif avec x12a |
| `x12a` | Refroidissement thermique local petites structures | FREE_SURFACE_KINETICS | Actif dans chaîne liquide qualifiée |
| `x13e` | Sweep Mach | TRANSPORT_SURFACE | Calibration |
| `x13g` | Reproductibilité statistique GPU | TRANSPORT_SURFACE | Règle méthodologique |
| `x14a-x14j` | Thermostat séparé par espèce | LIQUID_GAS | Architecture x14 |
| `x14d` | Collision commune + thermostats séparés | LIQUID_GAS | Actif dans x14 |
| `x14k` | Géométrie cinétique bilatérale | LIQUID_GAS | Opt-in; change le modèle d'interface |
| `x14l` | Réflexion spéculaire du gaz | LIQUID_GAS | Qualifié pour imperméabilité normale dans cas tests |
| `x14m` | Assemblage bilatéral + compatibilité x12a | LIQUID_GAS | Architecture intégrée |
| `x14s` | EOS gaz volume accessible | LIQUID_GAS | Actif dans x14 récent |
| `x14v` | Kick cinétique excédentaire | LIQUID_GAS | Actif dans chaîne x14 candidate |
| `x14aa` | Traction thermodynamique absolue sur faces x6g | LIQUID_GAS | Non retenu: dégrade la géométrie locale de forme |
| `x14ab` | p_ref sur x10n + jauge sur faces x6g | LIQUID_GAS | Non retenu |
| `x14ac` | Projection globale minimum-L2 | LIQUID_GAS | Principe conservé, local supplanté par x14ad |
| `x14ad` | Traction locale cohérente avec faces x6g | LIQUID_GAS | Retenu pour interfaces courbes x14 |
| `x14ai` | Fermeture de résultante Q6 appliquée | LIQUID_GAS | Concept retenu mais version initiale supplantée |
| `x14ai-fix1` | Fermeture B1 exacte post-correction périodique | LIQUID_GAS | Seulement composante liquide fermée et isolée des frontières Q6 externes |
| `0414` | Extension quadriface des open boundaries segmentées | OPEN_BOUNDARY | QUALIFIED |

## DIAGNOSTIC

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x6a` | Diagnostic EOS gaz | Q6_GF | Diagnostic historique |
| `x6b` | Audit support vs interface | Q6_GF | Diagnostic historique |
| `x6e` | Audit topologique des crossings | Q6_GF | Diagnostic architectural |
| `x6h-B0` | Diagnostic post-application | Q6_GF | Diagnostic OFF production |
| `x7k/x7l` | Réduction de télémétrie | Q6_GF | Actif |
| `x9e` | Diagnostic pression goutte statique | SURFACE_TENSION | Diagnostic/qualification |
| `x9f` | Diagnostic quadrupole signé | SURFACE_TENSION | Diagnostic/qualification |
| `x10l` | Diagnostic pré-mur cinétique | FREE_SURFACE_KINETICS | Diagnostic passif |
| `x13b` | Cisaillement transverse pur | TRANSPORT_SURFACE | Diagnostic historique |
| `x13za-x13zc` | Dépendance de grille de l'interface | TRANSPORT_SURFACE | Diagnostic; révèle forte dépendance de kappa_active à forte sigma |
| `x14ae` | Diagnostic pertes scatter | LIQUID_GAS | Diagnostic; pertes nulles sur cas discriminant |
| `x14af` | Diagnostic bilan global | LIQUID_GAS | Diagnostic causal |
| `x14am` | Young-Laplace diphasique multi-rayons | LIQUID_GAS | REVIEW/non décisif à sigma=10000: kappa_active et pression sont déjà connus comme métrologie bruyante/non monotone dans ce régime |

## FIX

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x7f-fix2` | Garde wall-simple | Q6_GF | Correctif actif |
| `x13w-fix3` | Correctif reseed | TRANSPORT_SURFACE | Toujours invalidée physiquement |
| `x14g` | Cellules exactes post-stream/grid-shift | LIQUID_GAS | Correctif d'intégration actif |

## INFRA

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `Q6 multi-espèces` | Projection sélective par espèce | CORE | Socle multi-espèces |
| `x7h` | Factorisation run_ok | Q6_GF | Infrastructure runner |
| `x10n` | Polyligne continue marching-squares | FREE_SURFACE_KINETICS | Infrastructure active |
| `x11a` | Validation Young-Laplace | FREE_SURFACE_KINETICS | Tooling de qualification |
| `x11b` | Dispersion onde capillaire | FREE_SURFACE_KINETICS | Tooling de qualification |
| `x13j` | Young-Laplace x13h smoke | TRANSPORT_SURFACE | Tooling |

## PERF

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x7j` | CG coopératif CUDA résident | Q6_GF | Actif; optimisation majeure coût |
| `x8s` | Déflation des modes lents du CG | OPEN_BOUNDARY | Actif dans cas applicable |
| `x13a` | Pré-balayage analytique transport | TRANSPORT_SURFACE | Tooling/calibration |
| `x13f` | Optimisation (angle, lambda/h) | TRANSPORT_SURFACE | Calibration |

## QUALIFICATION

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `Resampling` | Contrôle du support particulaire | CORE | Module séparé, OFF dans les qualifications surface libre récentes |
| `x5a2` | Dam-break vide | Q6_GF | Historique / discriminant |
| `x7e` | Qualification x6g+x7d | Q6_GF | Qualification historique |
| `x13c` | Choix de gamma | TRANSPORT_SURFACE | Calibration |
| `x13h-A` | Acoustique point final lambda/h=0.72 | TRANSPORT_SURFACE | Qualification constitutive |
| `x13h-B` | Viscosité vs densité / localité | TRANSPORT_SURFACE | Qualification constitutive |
| `x13h-C` | Domaine Mach final | TRANSPORT_SURFACE | Qualification constitutive |
| `x13h` | Point liquide de référence | TRANSPORT_SURFACE | Référence liquide qualifiée 31/08/2026 |
| `x13zd` | Validation croisée décisive | TRANSPORT_SURFACE | Invalide ces fermetures; motive rollback au tag qualifié |

## RUNNER

| ID | Nom | Domaine | Statut |
|---|---|---|---|
| `x10h-x10i` | Critère relatif et réaction par blocs | FREE_SURFACE_KINETICS | Legacy; bypassé par x10o dans runners récents |

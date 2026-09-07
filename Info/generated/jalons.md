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
| `x1` | CODE | CORE | Jalon ancien non individualisé dans le rapport consolidé | À retrouver dans l'historique Git si nécessaire |
| `x2` | CODE | CORE | Test Q6 liquide seul / gravité | Historique; mène à x3 |

## x3-x7 : Q6-g / Q6-g-f, dam-break et fermeture incompressible

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x3` | CODE | Q6_GF | Q6-g force-aware - preuve de concept | Supplanté par x4a/x4b |
| `x4a` | CODE | Q6_GF | prestream_single | Supplanté par x4b |
| `x4b` | CODE | Q6_GF | prestream_single_fused | Séquençage de référence Q6-g-f |
| `x5a` | CODE | Q6_GF | free_surface_masked initial | Étape historique |
| `x5a2` | QUALIFICATION | Q6_GF | Dam-break vide | Historique / discriminant |
| `x5b` | CODE | Q6_GF | Gaz explicite compressible | Base du couplage gaz |
| `x6a` | DIAGNOSTIC | Q6_GF | Diagnostic EOS gaz | Diagnostic historique |
| `x6b` | DIAGNOSTIC | Q6_GF | Audit support vs interface | Diagnostic historique |
| `x6c` | CODE | Q6_GF | Alpha physique résident | Actif, base géométrique Q6/capillarité |
| `x6d` | CODE | Q6_GF | Distance sous-maille 1/theta | Supplanté par x6f |
| `x6e` | DIAGNOSTIC | Q6_GF | Audit topologique des crossings | Diagnostic architectural |
| `x6f` | CODE | Q6_GF | Stencil physique d'interface | Actif |
| `x6g` | CODE | Q6_GF | Pression gazeuse interfaciale | Actif quand gaz explicite |
| `x6h-A` | CODE | Q6_GF | Reconstruction faces basses | Actif dans Q6-g-f |
| `x6h-B0` | DIAGNOSTIC | Q6_GF | Diagnostic post-application | Diagnostic OFF production |
| `x6h-B1` | CODE | Q6_GF | Reconstruction face-particule RT0 | Actif dans Q6-g-f |
| `x7a/x7b` | ABLATION | Q6_GF | Kick viriel de densité | Rejeté dans Q6-g-f; mutuellement exclusif avec x7d |
| `x7d` | CODE | Q6_GF | Relaxation de densité dans le RHS | Actif; tau_rho=0.25 dans profil qualifié |
| `x7e` | QUALIFICATION | Q6_GF | Qualification x6g+x7d | Qualification historique |
| `x7f` | CODE | Q6_GF | Extension multi-topologies | Actif |
| `x7f-fix2` | FIX | Q6_GF | Garde wall-simple | Correctif actif |
| `x7g` | CODE | Q6_GF | Darcy avant projection | Actif selon mode Darcy |
| `x7h` | INFRA | Q6_GF | Factorisation run_ok | Infrastructure runner |
| `x7i` | BENCHMARK | Q6_GF | Qualification multi-conditions-limites | Benchmark de référence |
| `x7j` | PERF | Q6_GF | CG coopératif CUDA résident | Actif; optimisation majeure coût |
| `x7k/x7l` | DIAGNOSTIC | Q6_GF | Réduction de télémétrie | Actif |
| `x7m` | CODE | Q6_GF | Correction topologie monophase | Actif automatiquement |
| `x7o` | CODE | Q6_GF | Symétrisation Q6 indépendant | Actif |
| `x7p` | CODE | Q6_GF | Symétrisation Q6 commun | Actif |
| `x7q` | CODE | Q6_GF | Fermeture exacte du moment périodique | Actif automatiquement seulement dans son domaine; pas sur dam-break partiel |

## x8 : conditions limites ouvertes et benchmark von Karman

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x8k` | CODE | OPEN_BOUNDARY | Inlet segmenté Poiseuille local | Actif |
| `x8q` | CODE | OPEN_BOUNDARY | Continuation cinétique outlet | Actif pour outlet Neumann |
| `x8r` | CODE | OPEN_BOUNDARY | Outlet pression Neumann | Actif |
| `x8s` | PERF | OPEN_BOUNDARY | Déflation des modes lents du CG | Actif dans cas applicable |
| `x8t` | CODE | OPEN_BOUNDARY | Relaxation densité sans mode moyen | Actif dans cas applicable |
| `x8j` | ANALYZER | OPEN_BOUNDARY | Analyse VK POD + sondes | Tooling/qualification, pas une physique |

## x9 : tension superficielle, courbure et mouillage

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x9a-x9c` | CODE | SURFACE_TENSION | Choix de la géométrie de courbure | Étapes de sélection; p3 retenu |
| `x9d` | CODE | SURFACE_TENSION | Activation du saut de Laplace | Actif; coeur de la tension superficielle |
| `x9e` | DIAGNOSTIC | SURFACE_TENSION | Diagnostic pression goutte statique | Diagnostic/qualification |
| `x9f` | DIAGNOSTIC | SURFACE_TENSION | Diagnostic quadrupole signé | Diagnostic/qualification |
| `x9g` | CODE | SURFACE_TENSION | Sélecteurs de phases A/B | Actif |
| `x9h` | CODE | SURFACE_TENSION | Géométrie de paroi pour mouillage | Actif dans mouillage |
| `x9i-x9l` | ABLATION | SURFACE_TENSION | Prototypes angle de contact | Ablations/supplantés |
| `x9m` | CODE | SURFACE_TENSION | Fermeture statique de mouillage | Bonne statique; dynamique ligne triple non fermée |
| `x9r` | BENCHMARK | SURFACE_TENSION | Cutoff de petite courbure résolue | Actif selon benchmark; paramètre de résolution |
| `x9s` | BENCHMARK | SURFACE_TENSION | Impact/splash paramétrable | Démonstration/qualification qualitative |

## x10-x12 : fermeture cinétique de surface libre

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x10a-x10e` | CODE | FREE_SURFACE_KINETICS | Premières barrières / seals / réactions | Historique, supplanté |
| `x10f-x10g` | CODE | FREE_SURFACE_KINETICS | Réaction conservative globale | Code conservé sans call-site actif |
| `x10h-x10i` | RUNNER | FREE_SURFACE_KINETICS | Critère relatif et réaction par blocs | Legacy; bypassé par x10o dans runners récents |
| `x10j` | ABLATION | FREE_SURFACE_KINETICS | Réflexion spéculaire labo | Ablation rejetée: bloque fortement le dripping |
| `x10k` | ABLATION | FREE_SURFACE_KINETICS | Réflexion spéculaire repère interface | Ablation rejetée |
| `x10l` | DIAGNOSTIC | FREE_SURFACE_KINETICS | Diagnostic pré-mur cinétique | Diagnostic passif |
| `x10m` | ABLATION | FREE_SURFACE_KINETICS | Paroi implicite mobile / scratch | Ablation/infrastructure |
| `x10n` | INFRA | FREE_SURFACE_KINETICS | Polyligne continue marching-squares | Infrastructure active |
| `x10o` | CODE | FREE_SURFACE_KINETICS | Paroi thermique / enveloppe locale | Socle actif de la fermeture liquide x12 |
| `x10p/x10q` | CODE | FREE_SURFACE_KINETICS | Résolution recouvrements initiaux | Actif |
| `x10cic` | CODE | FREE_SURFACE_KINETICS | Alpha cinétique CIC dédié | Actif; orchestration encore liée à Q6 |
| `x10biq / Q2` | CODE | FREE_SURFACE_KINETICS | Reconstruction biquadratique tensorielle | Actif |
| `x10r` | ABLATION | FREE_SURFACE_KINETICS | Vitesses endpoints full-vector | Ablation rejetée: dripping dégradé |
| `x10s` | ABLATION | FREE_SURFACE_KINETICS | Cinématique normale au segment | Ablation rejetée/OFF |
| `x10t` | ABLATION | FREE_SURFACE_KINETICS | Cinématique tangentielle rigide | Ablation rejetée; impulse parasite aggravée |
| `x10u` | CODE | FREE_SURFACE_KINETICS | Relocalisation one-for-one | Actif dans chaîne liquide qualifiée |
| `x10v` | CODE | FREE_SURFACE_KINETICS | Swap local full-vector | Actif; peut ajouter dispersion/dissipation interfaciale |
| `x10w` | CODE | FREE_SURFACE_KINETICS | Limiter thermique pairwise | Implémenté mais OFF; exclusif avec x12a |
| `x11a` | INFRA | FREE_SURFACE_KINETICS | Validation Young-Laplace | Tooling de qualification |
| `x11b` | INFRA | FREE_SURFACE_KINETICS | Dispersion onde capillaire | Tooling de qualification |
| `x12a` | CODE | FREE_SURFACE_KINETICS | Refroidissement thermique local petites structures | Actif dans chaîne liquide qualifiée |
| `x12b/x12c` | BENCHMARK | FREE_SURFACE_KINETICS | Construction benchmark JFM | Tooling historique |
| `x12d` | BENCHMARK | FREE_SURFACE_KINETICS | Benchmark JFM 524 | Benchmark applicatif; similitude Re encore limitée |
| `x12cal` | CALIBRATOR | FREE_SURFACE_KINETICS | Calibrateur dynamique capillaire | Qualification dynamique |
| `x12yl` | CALIBRATOR | FREE_SURFACE_KINETICS | Calibrateur mécanique de sigma | Qualification mécanique historique |

## x13 : propriétés de transport, fluide de référence et campagne Taylor-Culick

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x13a` | PERF | TRANSPORT_SURFACE | Pré-balayage analytique transport | Tooling/calibration |
| `x13b` | DIAGNOSTIC | TRANSPORT_SURFACE | Cisaillement transverse pur | Diagnostic historique |
| `x13c` | QUALIFICATION | TRANSPORT_SURFACE | Choix de gamma | Calibration |
| `x13d` | CALIBRATOR | TRANSPORT_SURFACE | Longue longueur d'onde / acoustique | Calibration |
| `x13e` | CODE | TRANSPORT_SURFACE | Sweep Mach | Calibration |
| `x13f` | PERF | TRANSPORT_SURFACE | Optimisation (angle, lambda/h) | Calibration |
| `x13g` | CODE | TRANSPORT_SURFACE | Reproductibilité statistique GPU | Règle méthodologique |
| `x13h-A` | QUALIFICATION | TRANSPORT_SURFACE | Acoustique point final lambda/h=0.72 | Qualification constitutive |
| `x13h-B` | QUALIFICATION | TRANSPORT_SURFACE | Viscosité vs densité / localité | Qualification constitutive |
| `x13h-C` | QUALIFICATION | TRANSPORT_SURFACE | Domaine Mach final | Qualification constitutive |
| `x13h` | QUALIFICATION | TRANSPORT_SURFACE | Point liquide de référence | Référence liquide qualifiée 31/08/2026 |
| `x13j` | INFRA | TRANSPORT_SURFACE | Young-Laplace x13h smoke | Tooling |
| `x13k` | BENCHMARK | TRANSPORT_SURFACE | Goutte oscillante n=2 | Qualifié historique |
| `x13l` | BENCHMARK | TRANSPORT_SURFACE | Goutte oscillante n=3 | Qualifié historique |
| `x13m` | BENCHMARK | TRANSPORT_SURFACE | Goutte oscillante n=4 | Qualifié historique |
| `x13n` | BENCHMARK | TRANSPORT_SURFACE | Taylor-Culick 2D | Limite dynamique connue; référence G_TC ~0.795 au rollback |
| `x13o` | ABLATION | TRANSPORT_SURFACE | Swap normal-only | OFF production |
| `x13r/x13s` | BENCHMARK | TRANSPORT_SURFACE | Refroidissements locaux directs | Rejetées |
| `x13t` | ABLATION | TRANSPORT_SURFACE | Refroidissement progressif unifié | Rejetée comme chemin général |
| `x13u/x13v` | ABLATION | TRANSPORT_SURFACE | Rétention one-for-one sous x13t | Expérimental/rejeté |
| `x13w` | ABLATION | TRANSPORT_SURFACE | Escape -> inactive -> reseed | Rejeté: contraction artificielle du support |
| `x13w-fix3` | FIX | TRANSPORT_SURFACE | Correctif reseed | Toujours invalidée physiquement |
| `x13x` | BENCHMARK | TRANSPORT_SURFACE | Rétention probabiliste | Aucun compromis robuste |
| `x13z` | BENCHMARK | TRANSPORT_SURFACE | Changements de grille | Non suffisant pour validation |
| `x13za-x13zc` | DIAGNOSTIC | TRANSPORT_SURFACE | Dépendance de grille de l'interface | Diagnostic; révèle forte dépendance de kappa_active à forte sigma |
| `x13zd` | QUALIFICATION | TRANSPORT_SURFACE | Validation croisée décisive | Invalide ces fermetures; motive rollback au tag qualifié |

## x14 : phase gaz explicite et transfert liquide-gaz

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `x14a-x14j` | CODE | LIQUID_GAS | Thermostat séparé par espèce | Architecture x14 |
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

## Post-x14 / conditions limites ouvertes

| ID | Nature | Domaine | Nom | Statut / portée |
|---|---|---|---|---|
| `0414` | CODE | OPEN_BOUNDARY | Extension quadriface des open boundaries segmentées | QUALIFIED |

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

**Relations :**
- `REFERENCES` → `x3` — Q6-g force-aware - preuve de concept

### `Q6-g-f` — Q6 force-aware + interface + face-particule + densité

- **Clé unique :** `reference:Q6-g-f`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** Chaîne de projection de référence
- **Confiance :** `B`

Chaîne: vitesse tentative forcée, interface physique alpha=0.5, condition de pression, reconstruction face-particule B1/RT0 et relaxation lente de densité dans le même solveur CG.

### `x1` — Jalon ancien non individualisé dans le rapport consolidé

- **Clé unique :** `0493x1`
- **ID canonique :** `0493x1`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** À retrouver dans l'historique Git si nécessaire
- **Confiance :** `C`

Le rapport consolidé actuel ne donne pas une définition séparée et fiable de x1.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X1_CLOSED_BOX_CUDA_RESIDENT.md`
- `ASSOCIATED_WITH` — `scripts/run_0493x1_closed_box_smoke.sh`

### `x2` — Test Q6 liquide seul / gravité

- **Clé unique :** `0493x2`
- **ID canonique :** `0493x2`
- **Nature / domaine :** `CODE` / `CORE`
- **Statut :** Historique; mène à x3
- **Confiance :** `B`

Campagne liquide seul qui a montré que le kick gravitaire appliqué avant une projection trop tardive pouvait court-circuiter l'objectif de Q6.

**Relations :**
- `LEADS_TO` → `x3` — Q6-g force-aware - preuve de concept

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x2_liquid_only_q6.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x2_liquid_only_q6_common.sh`

### `x3` — Q6-g force-aware - preuve de concept

- **Clé unique :** `0493x3`
- **ID canonique :** `0493x3`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Supplanté par x4a/x4b
- **Confiance :** `B`

Projette une vitesse tentative incluant la force avant streaming; première version avec double projection pour démontrer la cause de la sédimentation parasite.

**Relations :**
- `REFERENCES` → `x4b` — prestream_single_fused
- `SUPERSEDED_BY` → `x4a` — prestream_single

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X3_Q6_FORCE_PRESTREAM_TEST.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x3_q6_force_projection_tg.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x3_liquid_only_q6_force_prestream.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x3_q6_force_projection_tg.sh`

### `x4a` — prestream_single

- **Clé unique :** `0493x4a`
- **ID canonique :** `0493x4a`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Supplanté par x4b
- **Confiance :** `B`

Une seule projection avant transport; évite le double solve tout en supprimant la dérive gravitaire.

**Relations :**
- `SUPERSEDED_BY` → `x4b` — prestream_single_fused

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X4A_Q6_FORCE_SINGLE_SOLVE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x4a_q6_force_single_tg.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x4a_liquid_only_q6_force_single.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x4a_q6_force_single_tg.sh`

### `x4b` — prestream_single_fused

- **Clé unique :** `0493x4b`
- **ID canonique :** `0493x4b`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Séquençage de référence Q6-g-f
- **Confiance :** `B`

Fusionne dépôt de v+a dt, projection Q6, puis application force+Q6 sans passage particulaire dédié au kick.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X4B_Q6_FORCE_CUDA_FUSION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x4b_q6_force_fusion_tg.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x4b_liquid_only_q6_force_fused.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x4b_q6_force_fusion_tg.sh`

### `x5a` — free_surface_masked initial

- **Clé unique :** `0493x5a`
- **ID canonique :** `0493x5a`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Étape historique
- **Confiance :** `B`

Masque Q6 du liquide partiellement rempli; bord du support traité comme pression de jauge nulle à demi-maille.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x5a_partial_liquid.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x5a_nonregression.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x5a_partial_liquid_free_surface.sh`

### `x5a2` — Dam-break vide

- **Clé unique :** `0493x5a2`
- **ID canonique :** `0493x5a2`
- **Nature / domaine :** `QUALIFICATION` / `Q6_GF`
- **Statut :** Historique / discriminant
- **Confiance :** `B`

Validation du masque surface libre sur dam-break sans gaz; robuste avant impact mais révèle que bord du support != interface physique.

### `x5b` — Gaz explicite compressible

- **Clé unique :** `0493x5b`
- **ID canonique :** `0493x5b`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Base du couplage gaz
- **Confiance :** `B`

Ajoute une espèce gaz q6Strength=0 qui collisionne avec le liquide sans être projetée incompressible.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X5B_LIQUID_GAS_FREE_SURFACE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x5b_liquid_gas_free_surface.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x5b_nonregression.sh`

### `x6a` — Diagnostic EOS gaz

- **Clé unique :** `0493x6a`
- **ID canonique :** `0493x6a`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic historique
- **Confiance :** `B`

Reconstruit une pression gazeuse EOS sans modifier la physique afin d'auditer le futur couplage de pression.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6A_Q6_PHASE_PRESSURE_DIAGNOSTIC.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6a_phase_pressure.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6a_phase_pressure_diagnostic.sh`

### `x6b` — Audit support vs interface

- **Clé unique :** `0493x6b`
- **ID canonique :** `0493x6b`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic historique
- **Confiance :** `B`

Compare seuil de support Q6 et isovaleur physique alpha=0.5.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6B_PHASE_GEOMETRY_DIAGNOSTIC.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6b_phase_geometry.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6b_phase_geometry_diagnostic.sh`

### `x6c` — Alpha physique résident

- **Clé unique :** `0493x6c`
- **ID canonique :** `0493x6c`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif, base géométrique Q6/capillarité
- **Confiance :** `B`

Construit sur GPU un champ alpha du liquide, filtré par stencil cinq points, distinct du simple carrier Q6.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6C_PHASE_GEOMETRY_RESIDENT.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6c_phase_geometry_resident.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6c_phase_geometry_resident.sh`

### `x6d` — Distance sous-maille 1/theta

- **Clé unique :** `0493x6d`
- **ID canonique :** `0493x6d`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Supplanté par x6f
- **Confiance :** `B`

Utilise la position locale de l'isovaleur pour corriger la distance de frontière au lieu du facteur demi-maille.

**Relations :**
- `SUPERSEDED_BY` → `x6f` — Stencil physique d'interface

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6D_GUARDED_CUTFACE_ZERO_PRESSURE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6d_cutface_geometry.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6d_cutface_geometry_zero_pressure.sh`

### `x6e` — Audit topologique des crossings

- **Clé unique :** `0493x6e`
- **ID canonique :** `0493x6e`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic architectural
- **Confiance :** `B`

Montre que l'interface alpha=0.5 traverse souvent des paires de cellules qui sont encore toutes deux dans le carrier numérique.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6E_PHASE_INTERFACE_TOPOLOGY.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6e_phase_interface_topology.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6e_phase_interface_topology.sh`

### `x6f` — Stencil physique d'interface

- **Clé unique :** `0493x6f`
- **ID canonique :** `0493x6f`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif
- **Confiance :** `B`

Sépare pressureMask et carrierMask; prépare les coefficients de face sur les crossings alpha=0.5 et la distance sous-maille theta.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X6F_PHASE_INTERFACE_STENCIL.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x6f_phase_interface_stencil.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x6f_phase_interface_stencil.sh`

### `x6g` — Pression gazeuse interfaciale

- **Clé unique :** `0493x6g`
- **ID canonique :** `0493x6g`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif quand gaz explicite
- **Confiance :** `B`

Fournit p_g sur les faces d'interface et impose p_L|Gamma=p_g dans le Dirichlet Q6; plus tard composé avec sigma*kappa.

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

### `x6h-A` — Reconstruction faces basses

- **Clé unique :** `0493x6h-a`
- **ID canonique :** `0493x6h-a`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif dans Q6-g-f
- **Confiance :** `B`

Reconstruit les corrections ouest/sud sur frontières physiques basses absentes du stockage east/north.

### `x6h-B0` — Diagnostic post-application

- **Clé unique :** `0493x6h-b0`
- **ID canonique :** `0493x6h-b0`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Diagnostic OFF production
- **Confiance :** `B`

Sépare bulk/interface/paroi/zones mixtes pour localiser la divergence après application aux particules.

### `x6h-B1` — Reconstruction face-particule RT0

- **Clé unique :** `0493x6h-b1`
- **ID canonique :** `0493x6h-b1`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif dans Q6-g-f
- **Confiance :** `B`

Remplace une correction constante par cellule par une reconstruction affine entre corrections de faces, cohérente avec la divergence FV projetée.

### `x7a/x7b` — Kick viriel de densité

- **Clé unique :** `reference:x7a/x7b`
- **Nature / domaine :** `ABLATION` / `Q6_GF`
- **Statut :** Rejeté dans Q6-g-f; mutuellement exclusif avec x7d
- **Confiance :** `B`

Tentatives de restauration de densité par kick post-projection de type ressort/viriel.

**Relations :**
- `REFERENCES` → `x7d` — Relaxation de densité dans le RHS

### `x7d` — Relaxation de densité dans le RHS

- **Clé unique :** `0493x7d`
- **ID canonique :** `0493x7d`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif; tau_rho=0.25 dans profil qualifié
- **Confiance :** `B`

Ajoute (f-1)/tau_rho dans le second membre Q6 pour restaurer lentement la densité sans resampling ni kick post-projection.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7D_DENSITY_RELAXATION_TIME_GRID_REFINEMENT.md`
- `ASSOCIATED_WITH` — `doc/README_0493X7E_X6G_X7D_COMBINATION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7d_density_rhs_grid_refinement.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7d_signed_traction_scan.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7e_x6g_x7d_combination.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7d_density_rhs_grid_refinement.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x7e_x6g_x7d_validation.sh`

### `x7e` — Qualification x6g+x7d

- **Clé unique :** `0493x7e`
- **ID canonique :** `0493x7e`
- **Nature / domaine :** `QUALIFICATION` / `Q6_GF`
- **Statut :** Qualification historique
- **Confiance :** `B`

Valide la coexistence pression gaz + relaxation de densité dans le même RHS, y compris runs longs/coarse-fine.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7E_X6G_X7D_COMBINATION.md`
- `ASSOCIATED_WITH` — `doc/src_mpcd_env_flags_inventory_consolidated_0493x7e_q6_g_f.csv`
- `ASSOCIATED_WITH` — `doc/src_mpcd_params_inventory_consolidated_0493x7e_q6_g_f.csv`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x7e_x6g_x7d_combination.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7e_x6g_x7d_validation.sh`

### `x7f` — Extension multi-topologies

- **Clé unique :** `0493x7f`
- **ID canonique :** `0493x7f`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif
- **Confiance :** `B`

Étend Q6-g-f aux topologies statiques supportées: périodique, canal, boîte fermée, inlet/outlet, segments.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7F_Q6_G_F_MULTIBC.md`
- `ASSOCIATED_WITH` — `scripts/check_0493x7f_q6_g_f_multibc.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7f_q6_g_f_multibc_validation.sh`

### `x7f-fix2` — Garde wall-simple

- **Clé unique :** `0493x7f-fix2`
- **ID canonique :** `0493x7f-fix2`
- **Nature / domaine :** `FIX` / `Q6_GF`
- **Statut :** Correctif actif
- **Confiance :** `B`

Autorise une face specular simple sans imposer artificiellement wallVP.

**Relations :**
- `FIXES` → `x7f` — Extension multi-topologies

### `x7g` — Darcy avant projection

- **Clé unique :** `0493x7g`
- **ID canonique :** `0493x7g`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif selon mode Darcy
- **Confiance :** `B`

Place le kick Darcy-Brinkman dans la vitesse tentative avant Q6-g-f, sans le rejouer après collision.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7G_Q6_G_F_DARCY.md`
- `ASSOCIATED_WITH` — `scripts/check_0493x7g_q6_g_f_darcy.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x7g_q6_g_f_darcy_validation.sh`

### `x7h` — Factorisation run_ok

- **Clé unique :** `0493x7h`
- **ID canonique :** `0493x7h`
- **Nature / domaine :** `INFRA` / `Q6_GF`
- **Statut :** Infrastructure runner
- **Confiance :** `B`

Rassemble dans les runners le profil src-q6-g-f: x4b, B1, x6f, registre espèces et relaxation densité.

**Relations :**
- `REFERENCES` → `x4b` — prestream_single_fused
- `REFERENCES` → `x6f` — Stencil physique d'interface

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7H_RUN_OK_Q6_G_F_COMPARISON.md`

### `x7i` — Qualification multi-conditions-limites

- **Clé unique :** `0493x7i`
- **ID canonique :** `0493x7i`
- **Nature / domaine :** `BENCHMARK` / `Q6_GF`
- **Statut :** Benchmark de référence
- **Confiance :** `B`

Campagne commune Taylor-Green, Poiseuille, bend-pipe Darcy et same-face IO pour comparer SRC/Q6/Q6-g-f.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7I_Q6_G_F_PHYSICAL_QUALIFICATION.md`
- `ASSOCIATED_WITH` — `matlab/analyze_0493x7i_q6_g_f_qualification.m`
- `ASSOCIATED_WITH` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x7i_q6_g_f_physical_qualification_x7q.sh`

### `x7j` — CG coopératif CUDA résident

- **Clé unique :** `0493x7j`
- **ID canonique :** `0493x7j`
- **Nature / domaine :** `PERF` / `Q6_GF`
- **Statut :** Actif; optimisation majeure coût
- **Confiance :** `B`

Remplace les réductions/synchronisations host à chaque itération par un unique CG coopératif entièrement GPU.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7J_Q6_G_F_RESIDENT_CG.md`

### `x7k/x7l` — Réduction de télémétrie

- **Clé unique :** `reference:x7k/x7l`
- **Nature / domaine :** `DIAGNOSTIC` / `Q6_GF`
- **Statut :** Actif
- **Confiance :** `B`

Calcule audits Q6-g-f et réductions host thermostat uniquement au premier pas / cadence summary, sans changer la physique.

### `x7m` — Correction topologie monophase

- **Clé unique :** `0493x7m`
- **ID canonique :** `0493x7m`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif automatiquement
- **Confiance :** `B`

Empêche une fluctuation alpha<0.5 de créer une fausse interface interne dans un fluide monophase complet.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md`

### `x7o` — Symétrisation Q6 indépendant

- **Clé unique :** `0493x7o`
- **ID canonique :** `0493x7o`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif
- **Confiance :** `B`

Supprime le biais est/nord dans la reconstruction des faces pour le domaine complet independent_masked.

### `x7p` — Symétrisation Q6 commun

- **Clé unique :** `0493x7p`
- **ID canonique :** `0493x7p`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif
- **Confiance :** `B`

Applique la même convention symétrique au Q6 commun.

### `x7q` — Fermeture exacte du moment périodique

- **Clé unique :** `0493x7q`
- **ID canonique :** `0493x7q`
- **Nature / domaine :** `CODE` / `Q6_GF`
- **Statut :** Actif automatiquement seulement dans son domaine; pas sur dam-break partiel
- **Confiance :** `B`

Mesure le moment B1/RT0 réellement appliqué aux particules et enlève le résidu uniforme k=0 dans les directions périodiques fullDomain.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X7Y_X7Q_RUNTIME_ABLATION.md`
- `ASSOCIATED_WITH` — `doc/src_mpcd_env_flags_inventory_consolidated_0493x7q_q6_g_f.csv`
- `ASSOCIATED_WITH` — `doc/src_mpcd_params_inventory_consolidated_0493x7q_q6_g_f.csv`
- `ASSOCIATED_WITH` — `scripts/run_0493x7i_q6_g_f_physical_qualification_x7q.sh`

### `x8k` — Inlet segmenté Poiseuille local

- **Clé unique :** `0493x8k`
- **ID canonique :** `0493x8k`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif
- **Confiance :** `B`

Définit une coordonnée locale au segment et impose u_n=4 Umax eta(1-eta) de façon cohérente à l'injection particulaire et à Q6.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x8k_segmented_local_poiseuille.sh`

### `x8q` — Continuation cinétique outlet

- **Clé unique :** `0493x8q`
- **ID canonique :** `0493x8q`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif pour outlet Neumann
- **Confiance :** `B`

Supprime les sortants et reconstruit la demi-distribution entrante depuis les moments de couches intérieures, pondérée par le flux normal.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/check_0493x8q_neumann_smoke.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x8q_neumann_smoke.sh`

### `x8r` — Outlet pression Neumann

- **Clé unique :** `0493x8r`
- **ID canonique :** `0493x8r`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif
- **Confiance :** `B`

Conserve gradient de vitesse normal nul pour la vitesse tentative mais impose phi_out=0 côté projection; ne réimpose plus UOUT comme cible physique.

### `x8s` — Déflation des modes lents du CG

- **Clé unique :** `0493x8s`
- **ID canonique :** `0493x8s`
- **Nature / domaine :** `PERF` / `OPEN_BOUNDARY`
- **Statut :** Actif dans cas applicable
- **Confiance :** `B`

Résout analytiquement les modes longitudinaux les plus lents à l'initialisation du CG pour améliorer le conditionnement du canal long.

### `x8t` — Relaxation densité sans mode moyen

- **Clé unique :** `0493x8t`
- **ID canonique :** `0493x8t`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** Actif dans cas applicable
- **Confiance :** `B`

Retire uniquement la moyenne spatiale de la cible de relaxation de densité quand outlet pression + fullDomain sont actifs.

### `x8j` — Analyse VK POD + sondes

- **Clé unique :** `0493x8j`
- **ID canonique :** `0493x8j`
- **Nature / domaine :** `ANALYZER` / `OPEN_BOUNDARY`
- **Statut :** Tooling/qualification, pas une physique
- **Confiance :** `B`

Analyseur de shedding: fréquence POD et probe, phase spatiale, période et comparaison bibliographique.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `matlab/analyze_vk_nondim_0493x8j.m`

### `x9a-x9c` — Choix de la géométrie de courbure

- **Clé unique :** `0493x9a-x9c`
- **ID canonique :** `0493x9a-x9c`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Étapes de sélection; p3 retenu
- **Confiance :** `B`

Compare les constructions de champ de courbure; production retient trois passes binomiales 3x3 + gradient/divergence de Scharr (p3).

### `x9d` — Activation du saut de Laplace

- **Clé unique :** `0493x9d`
- **ID canonique :** `0493x9d`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Actif; coeur de la tension superficielle
- **Confiance :** `B`

Ajoute sigma*kappa au potentiel de Dirichlet Q6-g-f; pas de force CSF ni kick particulaire direct.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X9D_ACTIVE_LAPLACE.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9d_static_drop.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9d_static_drop.sh`

### `x9e` — Diagnostic pression goutte statique

- **Clé unique :** `0493x9e`
- **ID canonique :** `0493x9e`
- **Nature / domaine :** `DIAGNOSTIC` / `SURFACE_TENSION`
- **Statut :** Diagnostic/qualification
- **Confiance :** `B`

Mesure le saut de pression reconstruit dans la solution Q6 et les grandeurs géométriques des gouttes.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X9E_STATIC_DROP_DIAGNOSTICS.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9e_static_drop.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9e_static_drop.sh`

### `x9f` — Diagnostic quadrupole signé

- **Clé unique :** `0493x9f`
- **ID canonique :** `0493x9f`
- **Nature / domaine :** `DIAGNOSTIC` / `SURFACE_TENSION`
- **Statut :** Diagnostic/qualification
- **Confiance :** `B`

Observable de forme pour suivre les modes d'oscillation des gouttes.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X9F_ELLIPSE_DIAGNOSTICS.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9f_ellipse_relaxation.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9f_ellipse_relaxation.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x9f_ellipse_relaxation_sweep.sh`

### `x9g` — Sélecteurs de phases A/B

- **Clé unique :** `0493x9g`
- **ID canonique :** `0493x9g`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Actif
- **Confiance :** `B`

Généralise les côtés de l'interface: family:liquid/gas, type:N, vacuum, wall, etc.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9g_phase_pair_equivalence.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9g_phase_pair_equivalence.sh`

### `x9h` — Géométrie de paroi pour mouillage

- **Clé unique :** `0493x9h`
- **ID canonique :** `0493x9h`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Actif dans mouillage
- **Confiance :** `B`

Traite wall comme troisième objet géométrique, distinct des deux phases capillaires.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9h_wall_geometry_provider.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9h_wall_geometry_provider.sh`

### `x9i-x9l` — Prototypes angle de contact

- **Clé unique :** `0493x9i-x9l`
- **ID canonique :** `0493x9i-x9l`
- **Nature / domaine :** `ABLATION` / `SURFACE_TENSION`
- **Statut :** Ablations/supplantés
- **Confiance :** `B`

Teste remplacement de normale, ghost alpha et reconstructions pariétales; révèle biais de courbure malgré angle local correct.

### `x9m` — Fermeture statique de mouillage

- **Clé unique :** `0493x9m`
- **ID canonique :** `0493x9m`
- **Nature / domaine :** `CODE` / `SURFACE_TENSION`
- **Statut :** Bonne statique; dynamique ligne triple non fermée
- **Confiance :** `B`

Construit la courbure de contact à partir d'une normale imposée au mur et d'une normale p3 hors support pariétal.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9m_contact_angle_offsupport.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x9m_offsupport_geometry.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9m_contact_angle_offsupport.sh`

### `x9r` — Cutoff de petite courbure résolue

- **Clé unique :** `0493x9r`
- **ID canonique :** `0493x9r`
- **Nature / domaine :** `BENCHMARK` / `SURFACE_TENSION`
- **Statut :** Actif selon benchmark; paramètre de résolution
- **Confiance :** `B`

Borne uniquement kappa utilisé dans sigma*kappa par un rayon minimal en cellules; ne modifie pas alpha ni le champ kappa brut.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x9r_limiter.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9r_dripping_jet_cutoff.sh`

### `x9s` — Impact/splash paramétrable

- **Clé unique :** `0493x9s`
- **ID canonique :** `0493x9s`
- **Nature / domaine :** `BENCHMARK` / `SURFACE_TENSION`
- **Statut :** Démonstration/qualification qualitative
- **Confiance :** `B`

Runners goutte -> paroi sèche ou flaque pour changements de topologie et splash.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/generate_0493x9s_splash_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x9s_splash.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x9s_splash_puddle.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x9s_splash_wall.sh`

### `x10a-x10e` — Premières barrières / seals / réactions

- **Clé unique :** `0493x10a-x10e`
- **ID canonique :** `0493x10a-x10e`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Historique, supplanté
- **Confiance :** `B`

Premières géométries de crossing et réactions locales pour empêcher les sorties de support.

### `x10f-x10g` — Réaction conservative globale

- **Clé unique :** `0493x10f-x10g`
- **ID canonique :** `0493x10f-x10g`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Code conservé sans call-site actif
- **Confiance :** `B`

Réduction globale des grandeurs de réaction pour éviter des receivers cellule par cellule.

### `x10h-x10i` — Critère relatif et réaction par blocs

- **Clé unique :** `0493x10h-x10i`
- **ID canonique :** `0493x10h-x10i`
- **Nature / domaine :** `RUNNER` / `FREE_SURFACE_KINETICS`
- **Statut :** Legacy; bypassé par x10o dans runners récents
- **Confiance :** `B`

Utilise (v-u_Gamma).n et une réaction mésoscopique; x10i sert de fallback hard r=1 legacy.

**Relations :**
- `REFERENCES` → `x10o` — Paroi thermique / enveloppe locale

### `x10j` — Réflexion spéculaire labo

- **Clé unique :** `0493x10j`
- **ID canonique :** `0493x10j`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée: bloque fortement le dripping
- **Confiance :** `B`

Réfléchit la vitesse dans le repère laboratoire.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10j_simple_specular.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10j_simple_specular_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10j_simple_specular_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10j_simple_specular_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10j_simple_specular_static_drop.sh`

### `x10k` — Réflexion spéculaire repère interface

- **Clé unique :** `0493x10k`
- **ID canonique :** `0493x10k`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée
- **Confiance :** `B`

Réflexion dans le repère local mobile de l'interface.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10k_local_frame_specular.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10k_local_frame_specular_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10k_local_frame_specular_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10k_local_frame_specular_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10k_local_frame_specular_static_drop.sh`

### `x10l` — Diagnostic pré-mur cinétique

- **Clé unique :** `0493x10l`
- **ID canonique :** `0493x10l`
- **Nature / domaine :** `DIAGNOSTIC` / `FREE_SURFACE_KINETICS`
- **Statut :** Diagnostic passif
- **Confiance :** `B`

Mesure l'état juste avant fermeture et montre que Q6/B1 garde un mouvement normal sortant avant le traitement cinétique.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10l_prewall_interface.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10l_prewall_interface_dual_diagnostic.sh`

### `x10m` — Paroi implicite mobile / scratch

- **Clé unique :** `0493x10m`
- **ID canonique :** `0493x10m`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation/infrastructure
- **Confiance :** `B`

Étape architecturale; buffers cellulaires ensuite réutilisés par x10v et autres briques.

**Relations :**
- `REFERENCES` → `x10v` — Swap local full-vector

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10m_moving_interface_wall.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10m_moving_interface_wall_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10m_moving_interface_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10m_moving_interface_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10m_moving_interface_static_drop.sh`

### `x10n` — Polyligne continue marching-squares

- **Clé unique :** `0493x10n`
- **ID canonique :** `0493x10n`
- **Nature / domaine :** `INFRA` / `FREE_SURFACE_KINETICS`
- **Statut :** Infrastructure active
- **Confiance :** `B`

Construit segments, normales et primitives continues réutilisées par x10o, Q2, x12a et plus tard x14.

**Relations :**
- `REFERENCES` → `x10o` — Paroi thermique / enveloppe locale
- `REFERENCES` → `x12a` — Refroidissement thermique local petites structures

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10n_continuous_interface.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10n_continuous_interface_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10n_continuous_interface_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10n_continuous_interface_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10n_continuous_interface_static_drop.sh`

### `x10o` — Paroi thermique / enveloppe locale

- **Clé unique :** `0493x10o`
- **ID canonique :** `0493x10o`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Socle actif de la fermeture liquide x12
- **Confiance :** `B`

Interface continue Q6 avec enveloppe thermique delta_th=min(C_T dt sqrt(kBT/m), delta_max).

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10o_q6_thermal_interface.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x10o_q6_thermal_interface_math.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dripping.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dripping_high.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dripping_restart.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_dual_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10o_q6_thermal_interface_static_drop.sh`

### `x10p/x10q` — Résolution recouvrements initiaux

- **Clé unique :** `reference:x10p/x10q`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif
- **Confiance :** `B`

Traite particules déjà du mauvais côté; recherche 3x3 puis fallback 7x7 rare si aucun segment trouvé.

### `x10cic` — Alpha cinétique CIC dédié

- **Clé unique :** `0493x10cic`
- **ID canonique :** `0493x10cic`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif; orchestration encore liée à Q6
- **Confiance :** `B`

Champ alpha réservé à la cinétique, distinct du x6c utilisé par Q6/capillarité.

**Relations :**
- `REFERENCES` → `x6c` — Alpha physique résident

### `x10biq / Q2` — Reconstruction biquadratique tensorielle

- **Clé unique :** `reference:x10biq / Q2`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif
- **Confiance :** `B`

Utilise les 9 valeurs CIC d'un patch 3x3 pour crossing et normale subcellulaires; pas de grille de coefficients supplémentaire.

### `x10r` — Vitesses endpoints full-vector

- **Clé unique :** `0493x10r`
- **ID canonique :** `0493x10r`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée: dripping dégradé
- **Confiance :** `B`

Améliore covariance galiléenne par vitesses vectorielles complètes aux endpoints.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10r_galilean_compare.py`

### `x10s` — Cinématique normale au segment

- **Clé unique :** `0493x10s`
- **ID canonique :** `0493x10s`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée/OFF
- **Confiance :** `B`

Projette la cinématique sur la normale du segment.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10s_galilean_compare.py`

### `x10t` — Cinématique tangentielle rigide

- **Clé unique :** `0493x10t`
- **ID canonique :** `0493x10t`
- **Nature / domaine :** `ABLATION` / `FREE_SURFACE_KINETICS`
- **Statut :** Ablation rejetée; impulse parasite aggravée
- **Confiance :** `B`

Ajoute une cinématique tangentielle rigide.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x10t_galilean_compare.py`

### `x10u` — Relocalisation one-for-one

- **Clé unique :** `0493x10u`
- **ID canonique :** `0493x10u`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif dans chaîne liquide qualifiée
- **Confiance :** `B`

Miroire uniquement la position d'une particule sortante; même slot, masse et vitesse, sans kick direct.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14k_bilateral_x10u_drop.sh`

### `x10v` — Swap local full-vector

- **Clé unique :** `0493x10v`
- **ID canonique :** `0493x10v`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif; peut ajouter dispersion/dissipation interfaciale
- **Confiance :** `B`

Échange le vecteur vitesse complet avec un partenaire liquide intérieur de même masse; conserve exactement P et K de la paire.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x13n_taylor_culick_sheet_2d_x10v_off.sh`

### `x10w` — Limiter thermique pairwise

- **Clé unique :** `0493x10w`
- **ID canonique :** `0493x10w`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Implémenté mais OFF; exclusif avec x12a
- **Confiance :** `B`

Réduction thermique locale avec redistribution pairwise conservative P/K.

**Relations :**
- `REFERENCES` → `x12a` — Refroidissement thermique local petites structures

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/collect_0493x10w_fix1_static_results.sh`
- `ASSOCIATED_WITH` — `scripts/collect_0493x10w_pairwise_static_results.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_dripping_ab_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_fix1_static_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_pairwise_static_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x10w_static_qualification.sh`

### `x11a` — Validation Young-Laplace

- **Clé unique :** `0493x11a`
- **ID canonique :** `0493x11a`
- **Nature / domaine :** `INFRA` / `FREE_SURFACE_KINETICS`
- **Statut :** Tooling de qualification
- **Confiance :** `B`

Suite de gouttes statiques multi-rayons/multi-sigma utilisant x9e pour comparer Delta p_Q6 à sigma/R_eff.

**Relations :**
- `REFERENCES` → `x9e` — Diagnostic pression goutte statique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11a_young_laplace.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11a_young_laplace_paired.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x11a_young_laplace_sigma0_baselines.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x11a_young_laplace_validation.sh`

### `x11b` — Dispersion onde capillaire

- **Clé unique :** `0493x11b`
- **ID canonique :** `0493x11b`
- **Nature / domaine :** `INFRA` / `FREE_SURFACE_KINETICS`
- **Statut :** Tooling de qualification
- **Confiance :** `B`

Suit une interface sinusoïdale et ajuste une oscillation amortie pour mesurer la dispersion capillaire.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11b_capillary_wave.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x11b_capillary_wave_earlyfit.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x11b_capillary_wave_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x11b_capillary_wave_validation.sh`

### `x12a` — Refroidissement thermique local petites structures

- **Clé unique :** `0493x12a`
- **ID canonique :** `0493x12a`
- **Nature / domaine :** `CODE` / `FREE_SURFACE_KINETICS`
- **Statut :** Actif dans chaîne liquide qualifiée
- **Confiance :** `B`

Réduit kBT effectif et enveloppe x10o quand l'épaisseur locale L_loc devient inférieure au rayon Rc ~25.3h.

**Relations :**
- `REFERENCES` → `x10o` — Paroi thermique / enveloppe locale

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x12a_local_thermal_cooling.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_local_thermal_cooling_validation.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_minradius_splash_overnight.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_minradius_splash_overnight_fix1.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_obstacle_splash_darcy_chi.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_obstacle_splash_darcy_chi_fix1.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12a_obstacle_splash_darcy_chi_fix1_mono.sh`

### `x12b/x12c` — Construction benchmark JFM

- **Clé unique :** `reference:x12b/x12c`
- **Nature / domaine :** `BENCHMARK` / `FREE_SURFACE_KINETICS`
- **Statut :** Tooling historique
- **Confiance :** `B`

Étapes de construction/réduction du domaine splash JFM sans nouvelle physique C++.

### `x12d` — Benchmark JFM 524

- **Clé unique :** `0493x12d`
- **ID canonique :** `0493x12d`
- **Nature / domaine :** `BENCHMARK` / `FREE_SURFACE_KINETICS`
- **Statut :** Benchmark applicatif; similitude Re encore limitée
- **Confiance :** `B`

Runner de mesure du splash/obstacle d'après Josserand-Lemoyne-Troeger-Zaleski.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12d_jfm524_overnight_campaign.sh`

### `x12cal` — Calibrateur dynamique capillaire

- **Clé unique :** `0493x12cal`
- **ID canonique :** `0493x12cal`
- **Nature / domaine :** `CALIBRATOR` / `FREE_SURFACE_KINETICS`
- **Statut :** Qualification dynamique
- **Confiance :** `B`

Mesure la dispersion/frequence des ondes et distingue sigma_dyn de la tension mécanique.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X12CAL_CAPILLARY_CALIBRATOR.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x12cal_capillary_calibrator.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x12cal_capillary_calibrator.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12cal_capillary_calibrator.sh`

### `x12yl` — Calibrateur mécanique de sigma

- **Clé unique :** `0493x12yl`
- **ID canonique :** `0493x12yl`
- **Nature / domaine :** `CALIBRATOR` / `FREE_SURFACE_KINETICS`
- **Statut :** Qualification mécanique historique
- **Confiance :** `B`

Gouttes statiques appariées pour extraire sigma_eff via Delta p_cap = sigma_eff <kappa>.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X12YL_YOUNG_LAPLACE_CALIBRATOR.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x12yl_young_laplace_calibrator.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x12yl_young_laplace_calibrator.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x12yl_young_laplace_calibrator.sh`

### `x13a` — Pré-balayage analytique transport

- **Clé unique :** `0493x13a`
- **ID canonique :** `0493x13a`
- **Nature / domaine :** `PERF` / `TRANSPORT_SURFACE`
- **Statut :** Tooling/calibration
- **Confiance :** `B`

Définit la portée intrinsèque des candidats SRC avant runs coûteux.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13a_A0_A6_design.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13A_SRC_HIGH_RE_PRESWEEP.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13a_src_high_re_presweep.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13a_src_high_re_presweep.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh`

### `x13b` — Cisaillement transverse pur

- **Clé unique :** `0493x13b`
- **ID canonique :** `0493x13b`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Diagnostic historique
- **Confiance :** `B`

Première métrologie de viscosité transverse; utile pour tendance/localité mais déclassée comme échelle absolue.

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

### `x13c` — Choix de gamma

- **Clé unique :** `0493x13c`
- **ID canonique :** `0493x13c`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Calibration
- **Confiance :** `B`

Qualifie l'occupation moyenne et conduit au choix économique gamma=8.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13c_default_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13C_TRANSPORT_QUALIFICATION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13c_C_longitudinal_statistics.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13c_H_gamma_multiseed.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13c_transport_qualification.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13c_C_longitudinal_statistics.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13c_H_gamma_multiseed.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13c_transport_qualification.sh`

### `x13d` — Longue longueur d'onde / acoustique

- **Clé unique :** `0493x13d`
- **ID canonique :** `0493x13d`
- **Nature / domaine :** `CALIBRATOR` / `TRANSPORT_SURFACE`
- **Statut :** Calibration
- **Confiance :** `B`

Ajoute grandes longueurs d'onde, corrige le calibrateur longitudinal amorti et qualifie un premier G08.

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

### `x13e` — Sweep Mach

- **Clé unique :** `0493x13e`
- **ID canonique :** `0493x13e`
- **Nature / domaine :** `CODE` / `TRANSPORT_SURFACE`
- **Statut :** Calibration
- **Confiance :** `B`

Explore la réponse non linéaire compressible et sépare domaine résolu et domaine constitutif sûr.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13e_default_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13E_COMPRESSIBLE_MACH_REACH.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13e_Ciso_mach_sweep.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13e_compressible_mach_reach.sh`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13e_longitudinal_velocity_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13e_Ciso_mach_sweep.sh`

### `x13f` — Optimisation (angle, lambda/h)

- **Clé unique :** `0493x13f`
- **ID canonique :** `0493x13f`
- **Nature / domaine :** `PERF` / `TRANSPORT_SURFACE`
- **Statut :** Calibration
- **Confiance :** `B`

Sweep local à gamma=8 pour réduire viscosité/coût tout en conservant propagation acceptable.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13f_S1_design_cost.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13F_G08_LOCAL_TRANSPORT_OPTIMIZATION.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13f_S1_G08_local_screen.py`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13f_S2_G08_local_qualification.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13f_G08_local_transport_optimization.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13f_S1_G08_local_screen.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13f_S2_G08_local_qualification.sh`

### `x13g` — Reproductibilité statistique GPU

- **Clé unique :** `0493x13g`
- **ID canonique :** `0493x13g`
- **Nature / domaine :** `CODE` / `TRANSPORT_SURFACE`
- **Statut :** Règle méthodologique
- **Confiance :** `B`

Montre qu'état initial + seed identiques ne donnent pas une trajectoire GPU bit-à-bit; impose analyses multi-graines.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/0493x13g_cost_plan.csv`
- `ASSOCIATED_WITH` — `doc/README_0493X13G_G08_REPRODUCIBILITY.md`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13g_H_reproducibility.py`
- `ASSOCIATED_WITH` — `scripts/check_0493x13g_H_reproducibility.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13g_H_reproducibility.sh`

### `x13h-A` — Acoustique point final lambda/h=0.72

- **Clé unique :** `0493x13h-a`
- **ID canonique :** `0493x13h-a`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification constitutive
- **Confiance :** `B`

Mesure c_s et viscosité longitudinale du fluide final avec amplitudes multiples et bootstrap.

### `x13h-B` — Viscosité vs densité / localité

- **Clé unique :** `0493x13h-b`
- **ID canonique :** `0493x13h-b`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification constitutive
- **Confiance :** `B`

Cartographie la dépendance à gamma et la frontière de localité; échelle absolue ensuite réauditée par Taylor-Green.

### `x13h-C` — Domaine Mach final

- **Clé unique :** `0493x13h-c`
- **ID canonique :** `0493x13h-c`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Qualification constitutive
- **Confiance :** `B`

Définit l'enveloppe de densité/Mach du fluide G08-0.72.

### `x13h` — Point liquide de référence

- **Clé unique :** `0493x13h`
- **ID canonique :** `0493x13h`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Référence liquide qualifiée 31/08/2026
- **Confiance :** `B`

Fluide économique gamma=8, angle 120 deg, lambda/h=0.72; utilisé pour qualification surface libre finale.

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

### `x13j` — Young-Laplace x13h smoke

- **Clé unique :** `0493x13j`
- **ID canonique :** `0493x13j`
- **Nature / domaine :** `INFRA` / `TRANSPORT_SURFACE`
- **Statut :** Tooling
- **Confiance :** `B`

Smoke/qualification mécanique du point x13h; un seul point n'est pas une qualification multi-rayons.

**Relations :**
- `REFERENCES` → `x13h` — Point liquide de référence

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13j_src_transport.py`
- `ASSOCIATED_WITH` — `scripts/calibrate_src_transport_0493x13j.sh`
- `ASSOCIATED_WITH` — `scripts/check_0493x13j_src_transport.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13j_young_laplace_x13h_s120.sh`

### `x13k` — Goutte oscillante n=2

- **Clé unique :** `0493x13k`
- **ID canonique :** `0493x13k`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Qualifié historique
- **Confiance :** `B`

Validation dynamique capillaire du mode azimutal n=2 sur fluide x13h.

**Relations :**
- `REFERENCES` → `x13h` — Point liquide de référence

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13k_oscillating_drop_2d.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/generate_0493x13k_oscillating_drop_2d.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13k_oscillating_drop_2d.py`
- `ASSOCIATED_WITH` — `scripts/generate_0493x13k_oscillating_drop_2d.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13k_oscillating_drop_2d_x13h.sh`

### `x13l` — Goutte oscillante n=3

- **Clé unique :** `0493x13l`
- **ID canonique :** `0493x13l`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Qualifié historique
- **Confiance :** `B`

Validation dynamique capillaire du mode n=3.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13l_oscillating_drop_n3_state.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13l_oscillating_drop_n3_state.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13l_oscillating_drop_n3_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13l_n3_multiseed10.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13l_oscillating_drop_n3_x13h.sh`

### `x13m` — Goutte oscillante n=4

- **Clé unique :** `0493x13m`
- **ID canonique :** `0493x13m`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Qualifié historique
- **Confiance :** `B`

Validation dynamique capillaire du mode n=4.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13m_oscillating_drop_n4_state.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x13m_oscillating_drop_n4_state.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x13m_oscillating_drop_n4_state.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x13m_n4_multiseed10.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x13m_oscillating_drop_n4_x13h.sh`

### `x13n` — Taylor-Culick 2D

- **Clé unique :** `0493x13n`
- **ID canonique :** `0493x13n`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Limite dynamique connue; référence G_TC ~0.795 au rollback
- **Confiance :** `B`

Benchmark de rétraction de nappe; révèle une vitesse trop faible malgré traction capillaire locale proche de 2 sigma.

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

### `x13o` — Swap normal-only

- **Clé unique :** `0493x13o`
- **ID canonique :** `0493x13o`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** OFF production
- **Confiance :** `B`

Ablation de x10v: échange seulement la composante normale locale et laisse tangentielle inchangée.

**Relations :**
- `REFERENCES` → `x10v` — Swap local full-vector

### `x13r/x13s` — Refroidissements locaux directs

- **Clé unique :** `reference:x13r/x13s`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Rejetées
- **Confiance :** `B`

Tentatives plus agressives de refroidissement interfacial pour accélérer Taylor-Culick.

### `x13t` — Refroidissement progressif unifié

- **Clé unique :** `0493x13t`
- **ID canonique :** `0493x13t`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Rejetée comme chemin général
- **Confiance :** `B`

Loi progressive de refroidissement/rétention fondée sur l'échelle locale.

### `x13u/x13v` — Rétention one-for-one sous x13t

- **Clé unique :** `reference:x13u/x13v`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Expérimental/rejeté
- **Confiance :** `B`

Sépare correction de position et swap pour tester la rétention des particules au rim.

### `x13w` — Escape -> inactive -> reseed

- **Clé unique :** `0493x13w`
- **ID canonique :** `0493x13w`
- **Nature / domaine :** `ABLATION` / `TRANSPORT_SURFACE`
- **Statut :** Rejeté: contraction artificielle du support
- **Confiance :** `B`

Transforme les sorties en slots inactifs puis réensemence localement côté liquide.

### `x13w-fix3` — Correctif reseed

- **Clé unique :** `0493x13w-fix3`
- **ID canonique :** `0493x13w-fix3`
- **Nature / domaine :** `FIX` / `TRANSPORT_SURFACE`
- **Statut :** Toujours invalidée physiquement
- **Confiance :** `B`

Version corrigée du choix géométrique de cellule de reseed utilisée dans la validation croisée finale.

**Relations :**
- `FIXES` → `x13w` — Escape -> inactive -> reseed

### `x13x` — Rétention probabiliste

- **Clé unique :** `0493x13x`
- **ID canonique :** `0493x13x`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Aucun compromis robuste
- **Confiance :** `B`

Balaye une fraction de rétention pour chercher compromis Taylor-Culick / dynamique de goutte.

### `x13z` — Changements de grille

- **Clé unique :** `0493x13z`
- **ID canonique :** `0493x13z`
- **Nature / domaine :** `BENCHMARK` / `TRANSPORT_SURFACE`
- **Statut :** Non suffisant pour validation
- **Confiance :** `B`

Explore raffinement de grille et gains Taylor-Culick.

### `x13za-x13zc` — Dépendance de grille de l'interface

- **Clé unique :** `0493x13za-x13zc`
- **ID canonique :** `0493x13za-x13zc`
- **Nature / domaine :** `DIAGNOSTIC` / `TRANSPORT_SURFACE`
- **Statut :** Diagnostic; révèle forte dépendance de kappa_active à forte sigma
- **Confiance :** `B`

Analyse rayon effectif, courbure et métriques Young-Laplace lors du raffinement.

### `x13zd` — Validation croisée décisive

- **Clé unique :** `0493x13zd`
- **ID canonique :** `0493x13zd`
- **Nature / domaine :** `QUALIFICATION` / `TRANSPORT_SURFACE`
- **Statut :** Invalide ces fermetures; motive rollback au tag qualifié
- **Confiance :** `B`

Teste x13t+x13w sur gouttes oscillantes; montre contraction de support et détruit la dynamique modale.

**Relations :**
- `REFERENCES` → `x13t` — Refroidissement progressif unifié
- `REFERENCES` → `x13w` — Escape -> inactive -> reseed

### `x14a-x14j` — Thermostat séparé par espèce

- **Clé unique :** `0493x14a-x14j`
- **ID canonique :** `0493x14a-x14j`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Architecture x14
- **Confiance :** `B`

Ajoute des cibles kBT propres aux espèces après collision SRC commune, sans séparer la collision du mélange.

### `x14d` — Collision commune + thermostats séparés

- **Clé unique :** `0493x14d`
- **ID canonique :** `0493x14d`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Actif dans x14
- **Confiance :** `B`

Conserve SRC commun au mélange; seule la remise à température est faite par type.

### `x14g` — Cellules exactes post-stream/grid-shift

- **Clé unique :** `0493x14g`
- **ID canonique :** `0493x14g`
- **Nature / domaine :** `FIX` / `LIQUID_GAS`
- **Statut :** Correctif d'intégration actif
- **Confiance :** `B`

Utilise les identifiants de cellule SRC persistants exacts pour thermostat par espèce.

### `x14j` — Goutte deux températures

- **Clé unique :** `0493x14j`
- **ID canonique :** `0493x14j`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** Benchmark d'intégration
- **Confiance :** `B`

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
- **Confiance :** `B`

Autorise le côté gaz à consommer la même géométrie de relocalisation x10 que le liquide, avec sens de phase inversé.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14k_bilateral_x10u_drop.sh`

### `x14l` — Réflexion spéculaire du gaz

- **Clé unique :** `0493x14l`
- **ID canonique :** `0493x14l`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Qualifié pour imperméabilité normale dans cas tests
- **Confiance :** `B`

Réfléchit la composante normale relative du gaz à l'interface mobile; tangentielle inchangée.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14l_gas_specular_drop.sh`

### `x14m` — Assemblage bilatéral + compatibilité x12a

- **Clé unique :** `0493x14m`
- **ID canonique :** `0493x14m`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Architecture intégrée
- **Confiance :** `B`

Combine liquide x10/x12, gaz x14l et thermostat séparé; x12a reste côté liquide uniquement.

**Relations :**
- `REFERENCES` → `x12a` — Refroidissement thermique local petites structures
- `REFERENCES` → `x14l` — Réflexion spéculaire du gaz

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14m_full_liquid_chain_gas_specular_drop.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14m_full_liquid_chain_gas_specular_drop_periodic.sh`

### `x14n` — Ablation fermeture gaz OFF

- **Clé unique :** `0493x14n`
- **ID canonique :** `0493x14n`
- **Nature / domaine :** `ABLATION` / `LIQUID_GAS`
- **Statut :** Ablation
- **Confiance :** `B`

Coupe la fermeture cinétique gazeuse pour séparer pression et imperméabilité.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14n_fix1_no_kinetic_reflection_drop.sh`
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14n_gas_closure_off_drop.sh`

### `x14o` — Ablation pression gaz constante

- **Clé unique :** `0493x14o`
- **ID canonique :** `0493x14o`
- **Nature / domaine :** `ABLATION` / `LIQUID_GAS`
- **Statut :** Ablation
- **Confiance :** `B`

Utilise une pression gazeuse constante choisie pour annuler la contribution de jauge.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/run_ok_0493x14o_x6g_constant_pressure_ablation_drop.sh`

### `x14r` — Analyse volume accessible

- **Clé unique :** `0493x14r`
- **ID canonique :** `0493x14r`
- **Nature / domaine :** `ANALYZER` / `LIQUID_GAS`
- **Statut :** Diagnostic conduisant à x14s
- **Confiance :** `B`

Analyse offline montrant que p=N kBT/A_cell sous-estime la pression si seule une fraction de cellule est accessible au gaz.

**Relations :**
- `REFERENCES` → `x14s` — EOS gaz volume accessible

**Artefacts associés :**
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14r_accessible_volume_ramp.py`

### `x14s` — EOS gaz volume accessible

- **Clé unique :** `0493x14s`
- **ID canonique :** `0493x14s`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Actif dans x14 récent
- **Confiance :** `B`

Corrige la pression gazeuse par la fraction de volume accessible dérivée de alpha Q6.

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
- **Confiance :** `B`

Benchmark plan qui qualifie la transmission moyenne de p_g par x6g/x14s sans terme impulsionnel direct.

**Relations :**
- `REFERENCES` → `x14s` — EOS gaz volume accessible
- `REFERENCES` → `x6g` — Pression gazeuse interfaciale

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
- **Confiance :** `B`

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
- **Confiance :** `B`

Transfère J_excess = J_raw - J_thermo au liquide afin d'ajouter le flux cinétique hors équilibre sans doubler la pression x6g.

**Relations :**
- `REFERENCES` → `x6g` — Pression gazeuse interfaciale

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
- **Confiance :** `B`

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
- **Confiance :** `B`

Runner intégré x6g+x9+x14l+x14v+chaîne liquide; banc pour forme, moment et fréquence.

**Relations :**
- `REFERENCES` → `x14l` — Réflexion spéculaire du gaz
- `REFERENCES` → `x14v` — Kick cinétique excédentaire
- `REFERENCES` → `x6g` — Pression gazeuse interfaciale

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
- **Confiance :** `B`

Transfère J_raw directement et supprime la soustraction thermodynamique.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14Y_X14V_PG_SUBTRACTION_ABLATION.md`

### `x14z` — Fermeture géométrique p_ref

- **Clé unique :** `0493x14z`
- **ID canonique :** `0493x14z`
- **Nature / domaine :** `ABLATION` / `LIQUID_GAS`
- **Statut :** Rejeté comme cause du défaut n=1
- **Confiance :** `B`

Corrige la résultante du seul p_ref uniforme sur la polyligne x10n.

**Relations :**
- `REFERENCES` → `x10n` — Polyligne continue marching-squares

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14Z_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE.md`

### `x14aa` — Traction thermodynamique absolue sur faces x6g

- **Clé unique :** `0493x14aa`
- **ID canonique :** `0493x14aa`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Non retenu: dégrade la géométrie locale de forme
- **Confiance :** `B`

Déplace toute la traction sur la géométrie de faces Q6.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AA_X6G_FACE_THERMO_TRACTION.md`

### `x14ab` — p_ref sur x10n + jauge sur faces x6g

- **Clé unique :** `0493x14ab`
- **ID canonique :** `0493x14ab`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Non retenu
- **Confiance :** `B`

Sépare référence et jauge mais garde traction variable sur normales axiales Q6.

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AB_HYBRID_GAUGE_THERMO_TRACTION.md`

### `x14ac` — Projection globale minimum-L2

- **Clé unique :** `0493x14ac`
- **ID canonique :** `0493x14ac`
- **Nature / domaine :** `CODE` / `LIQUID_GAS`
- **Statut :** Principe conservé, local supplanté par x14ad
- **Confiance :** `B`

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
- **Confiance :** `B`

Échantillonne la pression de jauge des faces représentées qui terminent chaque segment x10n, applique sur normale locale, puis corrige la résultante résiduelle.

**Relations :**
- `REFERENCES` → `x10n` — Polyligne continue marching-squares

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AD_LOCAL_X6G_FACE_GAUGE_PROJECTION.md`

### `x14ae` — Diagnostic pertes scatter

- **Clé unique :** `0493x14ae`
- **ID canonique :** `0493x14ae`
- **Nature / domaine :** `DIAGNOSTIC` / `LIQUID_GAS`
- **Statut :** Diagnostic; pertes nulles sur cas discriminant
- **Confiance :** `B`

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
- **Confiance :** `B`

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
- **Confiance :** `B`

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
- **Confiance :** `B`

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
- **Confiance :** `B`

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
- **Confiance :** `B`

Corrige la cible x14ai pour inclure la correction uniforme périodique B1; ferme le moment global au roundoff.

**Relations :**
- `FIXES` → `x14ai` — Fermeture de résultante Q6 appliquée
- `REFERENCES` → `x14ai` — Fermeture de résultante Q6 appliquée

### `x14aj` — Goutte oscillante n=3 avec gaz

- **Clé unique :** `0493x14aj`
- **ID canonique :** `0493x14aj`
- **Nature / domaine :** `BENCHMARK` / `LIQUID_GAS`
- **Statut :** REVIEW: fréquence ~12% lente dans campagne actuelle
- **Confiance :** `B`

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
- **Confiance :** `B`

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
- **Confiance :** `B`

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
- **Confiance :** `B`

Screening multi-rayons avec x9e sans baseline sigma=0 longue.

**Relations :**
- `REFERENCES` → `x9e` — Diagnostic pression goutte statique

**Artefacts associés :**
- `ASSOCIATED_WITH` — `doc/README_0493X14AM_YOUNG_LAPLACE_TWO_PHASE.md`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14am_young_laplace_two_phase.cpython-312.pyc`
- `ASSOCIATED_WITH` — `scripts/__pycache__/analyze_0493x14am_young_laplace_two_phase.cpython-313.pyc`
- `ASSOCIATED_WITH` — `scripts/analyze_0493x14am_young_laplace_two_phase.py`
- `ASSOCIATED_WITH` — `scripts/run_0493x14am_young_laplace_two_phase_multiradius.sh`
- `ASSOCIATED_WITH` — `scripts/run_0493x14am_young_laplace_two_phase_multiradius.sh.before_resolved_gas`

### `0414` — Extension quadriface des open boundaries segmentées

- **Clé unique :** `20260907-0414-segmented-xy`
- **ID canonique :** `20260907-0414-segmented-xy`
- **Nature / domaine :** `CODE` / `OPEN_BOUNDARY`
- **Statut :** QUALIFIED
- **Confiance :** `A`
- **Date :** `2026-09-07`

Généralise les entrées/sorties segmentées aux axes x et y sur le chemin CUDA résident; crossing multi-axes chronologique, x8r quadriface, x8t généralisé, x8s séparable 1-D/2-D, gardes de coins/réservoirs et diagnostic low-face corrigé.

**Notes.** Qualification Q1-Q7 et ablation x8s 2-D consolidées.

**Relations :**
- `EXTENDS` → `x8k` — Inlet segmenté Poiseuille local
- `EXTENDS` → `x8r` — Outlet pression Neumann
- `EXTENDS` → `x8s` — Déflation des modes lents du CG
- `EXTENDS` → `x8t` — Relaxation densité sans mode moyen
- `REFERENCES` → `x8r` — Outlet pression Neumann
- `REFERENCES` → `x8s` — Déflation des modes lents du CG
- `REFERENCES` → `x8t` — Relaxation densité sans mode moyen

**Artefacts associés :**
- `QUALIFIES` — `scripts/run_0414_segmented_xy_neumann_qualification.sh`

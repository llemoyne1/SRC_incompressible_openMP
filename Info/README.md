# Info — base de référence SRC_GPU-SURF

> **V4.27** — réintégration canonique de la lignée Neumann multiphasique après cherry-pick dans `surf`, restauration V4.22/V4.23 et documentation x9e→x9e-fix3.


`Info/` est le sous-système documentaire versionné du projet SRC_GPU-SURF. Il est volontairement séparé du code de calcul (`src/`, `include/`), des runners/analyseurs (`scripts/`, `matlab/`) et des outils temporaires (`tools/`).

Son objectif est de maintenir **une seule base relationnelle** reliant :

- les jalons/phases du développement (`x14ai`, `x8r`, 0414 courant, anciens jalons numériques, etc.) ;
- les paramètres `.kv`, champs C++ et alias de runners ;
- les variables d'environnement / flags ;
- les sources, runners, générateurs, analyseurs, calibrateurs et documentation ;
- les commits/tags/branches Git et les preuves documentaires ;
- l'audit d'ascendance et de patch-équivalence des branches par rapport à `surf` ;
- les candidats-jalons historiques avant leur promotion vers le référentiel canonique ;
- les relations entre tous ces objets.

## Arborescence

```text
Info/
├── README.md
├── reference_sources.json
├── .gitignore
├── .gitattributes
├── db/
│   ├── schema.sql
│   ├── src_reference.sqlite
│   └── src_reference_dump.sql
├── inputs/
│   ├── snapshots/
│   │   ├── referentiel_jalons_SRC_GPU_SURF_20260905.tex
│   │   ├── src_mpcd_params_inventory_snapshot_040926_x14ai.csv
│   │   └── src_mpcd_env_flags_inventory_snapshot_040926_x14ai.csv
│   └── historical/
│       ├── conception_q6_multiespeces_cuda_resident_0491.tex
│       └── rapport_mpcd_incompressible_complete_0493w1_calibration_q6_multiespeces.tex
├── curations/
│   ├── 0001_current_0414_segmented_xy.sql
│   ├── 0002_0490_multispecies_resampling.sql
│   ├── 0003_0491_species_q6.sql
│   ├── 0004_0492_run_ok_refresh.sql
│   └── 0005_0493_resident_species_physics.sql
├── scripts/
│   ├── build_src_reference.py
│   ├── publish_src_reference.py
│   └── query_src_reference.py
├── generated/
│   ├── README.md
│   ├── lexique_jalons.md
│   ├── jalons.md
│   ├── jalons_par_nature.md
│   ├── parametres.md
│   ├── flags.md
│   ├── cles_controle_sorties.md
│   ├── artefacts.md
│   ├── audit_candidats_git.md
│   └── csv/
└── docs/
    ├── ARCHITECTURE.md
    ├── BOOTSTRAP_AUDIT.md
    ├── GIT_AUDIT_V3.md
    ├── PUBLICATION_V4.md
    ├── GLOSSAIRE_SIGLES.md
    ├── CURATION_0490_V4_1.md
    ├── CURATION_0491_V4_2.md
    ├── CURATION_0492_V4_3.md
    └── CURATION_0493_V4_4.md
```

## Deux racines distinctes

Le système distingue explicitement :

- `repo_root` : racine du dépôt SRC_GPU-SURF, contenant `.git`, `src/`, `scripts/`, etc. ;
- `info_root` : `repo_root/Info`, contenant uniquement la base documentaire.

Le builder détecte `repo_root` par `git rev-parse --show-toplevel`. Dans une archive sans `.git`, il utilise le parent de `Info/` comme fallback. Les artefacts du code restent toujours enregistrés par chemins relatifs au dépôt (`src/...`, `scripts/...`) et **jamais** relativement à `Info/`.

`Info/` n'est pas inclus dans le scan standard des artefacts du solveur : la base ne s'indexe donc pas elle-même.

## Source de vérité et reconstruction

La base opérationnelle est `Info/db/src_reference.sqlite`. Elle est **reconstruite**, pas éditée à la main.

Les sources versionnées sont :

1. `Info/db/schema.sql` — source unique du schéma SQL ;
2. `Info/inputs/snapshots/` — inventaires/référentiels bruts actifs ;
3. `Info/inputs/historical/` — archives techniques historiques utilisées comme preuves de curation ;
4. `Info/reference_sources.json` — manifeste indiquant quels snapshots sont actifs ;
5. `Info/curations/*.sql` — compléments/corrections documentaires versionnés ;
6. le dépôt lui-même — arborescence du code et historique Git.

Les curations ne sont pas des migrations de schéma. Elles ajoutent ou corrigent de la connaissance documentaire sans modifier le builder. Les futures vraies migrations de schéma disposent d'une table séparée `schema_migrations`.

Le builder travaille dans `src_reference.sqlite.tmp`, vérifie `PRAGMA quick_check` et `PRAGMA foreign_key_check`, puis remplace la base atomiquement. Une erreur d'import ne laisse donc jamais une base partiellement mise à jour.

`src_reference_dump.sql` est produit en parallèle pour rendre les modifications de contenu inspectables dans Git. `src_reference.sqlite` est reconstructible et ignoré par Git ; le dump SQL et les publications textuelles sont versionnés.

## Reconstruction courante

Depuis n'importe quel répertoire :

```bash
python3 Info/scripts/build_src_reference.py
```

Ou explicitement :

```bash
python3 Info/scripts/build_src_reference.py --repo-root .
```

Le builder :

1. lit `Info/reference_sources.json` ;
2. charge le schéma depuis `Info/db/schema.sql` ;
3. importe le référentiel de jalons ;
4. importe les inventaires paramètres et flags dans les tables brutes ;
5. normalise les symboles et aliases ;
6. scanne `src/`, `include/`, `scripts/`, `matlab/`, `doc/`, `docs/`, `examples/`, `external_benchmarks/`, `tools/` ;
7. applique les curations SQL ;
8. construit les relations symboles ↔ fichiers, flags ↔ paramètres, symboles ↔ jalons et artefacts ↔ jalons ;
9. importe tous les commits, fichiers modifiés, tags et refs Git ;
10. audite chaque branche `origin/*` contre `origin/surf` avec `git rev-list` et `git cherry` ;
11. classe les commits comme `IN_MAINLINE`, `PATCH_EQUIVALENT_IN_MAINLINE` ou `UNIQUE_OUTSIDE_MAINLINE` ;
12. construit les candidats-jalons à partir des sujets de commits, tags, branches et chemins historiques ;
13. réconcilie les jalons numériques explicitement curés avec Git uniquement lorsqu'un seul candidat porte ce label ; les labels réutilisés restent ambigus ;
14. reconstruit l'index plein texte ;
15. génère les vues humaines `Info/generated/` et les exports CSV ;
16. valide l'intégrité puis remplace en lot la base, le dump et les publications avec rollback en cas d'échec.

Les chemins absolus de la machine ne sont pas écrits comme identité documentaire dans la base : `meta.repo_root='.'` et `meta.info_root='Info'` dans l'installation normale.

## Publication V4

`Info/generated/` contient les vues directement consultables dans Git/GitHub. Elles sont
**générées** et ne doivent jamais être éditées manuellement. Le document `jalons.md` ne
publie que la table canonique `milestones`; les candidats historiques restent séparés
dans `audit_candidats_git.md` jusqu'à curation explicite.

Les paramètres sont publiés depuis les symboles normalisés : une fiche regroupe le concept
canonique, ses clés `.kv`, champs C++, alias runners, valeurs par défaut, contraintes, rôle,
sources et jalons associés. Les flags / variables de runners sont publiés dans un document
séparé avec leurs relations `SETS_PARAMETER`.

Voir `Info/docs/PUBLICATION_V4.md`.



## Curation V4.1 — série 0490A–P

La première curation historique structurée promeut les 18 jalons documentés de la série
`0490A` à `0490P` (y compris `0490M-fix2`, `0490N-fix1` et `0490N-fix2`).
Ils sont regroupés sous le domaine `MULTISPECIES_RESAMPLING`. Les README dédiés sont
la preuve documentaire primaire ; après l'import Git, le builder complète automatiquement
la date et le commit d'introduction lorsque le candidat numérique est unique, ou lorsqu'un
seul candidat a créé le fichier source dédié déclaré par la curation. Un label réutilisé
comme `0414` reste donc ambigu tant qu'aucune source d'introduction ne le désambiguïse.

Voir `Info/docs/CURATION_0490_V4_1.md`.


### V4.1.1 — réconciliation par source d’introduction

Lorsqu’un label numérique curé possède plusieurs candidats Git, la réconciliation peut
encore être faite si un seul candidat a **créé le fichier source dédié** indiqué par la
curation (par exemple `README_0490P_DEVICE_CELL_POLICY_ZERO_CPU.md`). Cela évite qu’un
inventaire ou document ultérieur contenant le même numéro bloque le vrai jalon, sans
relâcher la protection contre les numéros historiquement réutilisés.

## Curation V4.2.1 — série 0491 species-Q6

La curation suivante promeut sept jalons historiques explicitement attestés : `0491A`,
`0491D`, `0491E`, `0491F`, `0491G`, `0491H` et `0491H-fix1`. Les labels `0491B` et
`0491C` ne sont pas attestés comme jalons Git distincts dans l’historique réel et ne sont
donc pas créés artificiellement. Le README `0491H_RUN_OK_LIVEVIS_VALIDATION` reste une
preuve de validation et non un jalon autonome.

Voir `Info/docs/CURATION_0491_V4_2.md`.

## Curation V4.3 — jalon 0492 run_ok refresh

La curation suivante retient un seul jalon canonique `0492`, correspondant au refresh et
à l'homogénéisation de la suite `run_ok`. Les marqueurs internes `0492a` (résolution du
mode species-resident) et `0492b` (checker sémantique d'injection) restent des sous-révisions
techniques reliées à 0492 et ne sont pas promus comme jalons autonomes.

Voir `Info/docs/CURATION_0492_V4_3.md`.

## Audit Git V3

La V3 considère `origin/surf` comme ligne historique principale par défaut (`--mainline-ref origin/surf`). Si cette ref n'existe pas, le builder essaie `surf`, puis `HEAD`.

Pour chaque branche distante `origin/*`, la base conserve :

- le nombre de commits hors ascendance de la mainline ;
- le résultat `git cherry` par commit (`+` réellement distinct, `-` patch-équivalent) ;
- les fichiers ajoutés/modifiés/renommés par commit ;
- les refs qui contiennent chaque commit ;
- les tags annotés/légers et leur message ;
- les candidats de jalons dérivés de ces preuves.

Les anciens labels numériques (`0414`, `0490A`, `0432a`, etc.) **ne sont jamais fusionnés automatiquement par leur seul nom**. Ils restent contextualisés par leur commit d'ancrage jusqu'à curation. Les labels `x...`, beaucoup moins ambigus, peuvent être reliés automatiquement au jalon canonique existant.

`Info/` est conservé dans l'inventaire Git des fichiers modifiés, mais ses propres noms de fichiers ne créent pas de candidats-jalons : le système documentaire ne s'auto-indexe pas comme histoire du solveur.

Voir `Info/docs/GIT_AUDIT_V3.md` pour le détail des tables et des statuts.

## Changer de snapshot sans modifier le code

Pour basculer vers un inventaire plus récent, déposer le nouveau fichier sous `Info/inputs/snapshots/` puis modifier uniquement `Info/reference_sources.json` :

```json
{
  "milestones": "inputs/snapshots/referentiel_jalons_SRC_GPU_SURF_20260905.tex",
  "params_inventory": "inputs/snapshots/src_mpcd_params_inventory_snapshot_040926_x14ai.csv",
  "env_inventory": "inputs/snapshots/src_mpcd_env_flags_inventory_snapshot_040926_x14ai.csv"
}
```

Des chemins explicites restent disponibles sur la ligne de commande pour les audits ponctuels.

## Consultation

```bash
python3 Info/scripts/query_src_reference.py milestone x14ai
python3 Info/scripts/query_src_reference.py milestone x14ai-fix1
python3 Info/scripts/query_src_reference.py milestone 20260907-0414-segmented-xy

python3 Info/scripts/query_src_reference.py param wallKBT
python3 Info/scripts/query_src_reference.py flag WALL_KBT
python3 Info/scripts/query_src_reference.py param q6PressureOutletDeflationEnable

python3 Info/scripts/query_src_reference.py artifact run_0493x14ai_drag_device_closure.sh

python3 Info/scripts/query_src_reference.py branches
python3 Info/scripts/query_src_reference.py publications
python3 Info/scripts/query_src_reference.py branch origin/feature/cuda-resident-q6
python3 Info/scripts/query_src_reference.py commit 3945cdc8
python3 Info/scripts/query_src_reference.py candidate 0490A
python3 Info/scripts/query_src_reference.py candidate 0414
python3 Info/scripts/query_src_reference.py search "surface tension"
python3 Info/scripts/query_src_reference.py stats
python3 Info/scripts/query_src_reference.py doctor
```

## Identifiants de jalons

Les labels historiques ne sont pas supposés uniques. La base sépare :

- `milestone_id` : label humain (`x14ai`, `0414`) ;
- `milestone_key` : clé unique namespacée (`0493x14ai`, `20260907-0414-segmented-xy`) ;
- `canonical_id` : identifiant canonique lorsque disponible.

Un simple suffixe numérique `0xxx` dans un nom de fichier n'est jamais relié automatiquement à un jalon. Cette règle évite notamment la collision entre le 0414 NACA/Darcy historique et le chantier 0414 segmented-x/y actuel.

## Mise à jour du système documentaire

Toute modification doit idéalement suivre cette règle :

- **schéma relationnel** → `Info/db/schema.sql` + future migration de schéma si nécessaire ;
- **nouvelle source d'inventaire** → `Info/inputs/snapshots/` + `reference_sources.json` ;
- **correction/complément historique** → nouvelle curation SQL sous `Info/curations/` ;
- **algorithme d'audit/import** → `Info/scripts/` ;
- **base et dump générés** → reconstruction complète puis `doctor`.

Cela garantit qu'une étape de maintenance met à jour simultanément toutes les vues de la connaissance plutôt que plusieurs tableaux autonomes.

## V4 — publication consultable

La reconstruction normale produit maintenant simultanément SQLite, dump SQL et documents `Info/generated/`. Le remplacement est groupé et rollback-capable : un échec de génération ne laisse pas une base plus récente que les documents publiés.

## V3.1 — candidats numériques conservateurs

La V3.1 corrige la création des candidats numériques historiques (`0xxx`). Une simple
modification ou suppression ultérieure d'un fichier portant un ancien numéro ne crée
plus un nouveau jalon. Un chemin ne crée un candidat numérique que lors de son ajout,
ou lorsqu'un renommage/copie introduit effectivement un nouveau label dans le nom de
destination. Les touches ultérieures restent intégralement disponibles dans
`git_commit_files`. Cette règle évite notamment qu'un déplacement de README `0490A`
ou qu'une modification tardive de l'ancien runner NACA `0414` soit interprété comme
un nouveau jalon.

## Curation V4.4 — correction 0491 et premier cycle 0493

La V4.4 généralise la politique de preuve historique. Un jalon peut être canonique sans
candidat Git numérique si une archive technique versionnée ou le code de production
l'atteste explicitement. Cette règle restaure `0491B` et `0491C`, documentés par les
archives placées sous `Info/inputs/historical/`.

Elle ajoute également le premier cycle 0493 : `0493A`, `0493B`, `0493C`, `0493C-fix3`,
`0493D`, `0493D-fix1`, `0493E`, `0493F`, `0493F-fix2`, `0493G`, `0493H`, `0493I` et
`0493J`. Les numéros non attestés ne sont pas reconstruits artificiellement.

Voir `Info/docs/CURATION_0491_V4_2.md` et `Info/docs/CURATION_0493_V4_4.md`.

## Curation V4.5 — cycles 0493o et 0493w

La V4.5 ajoute la transition entre le premier cycle 0493 résident et la série `0493x` :
références SRC `0493O0`, réparation locale de support `O1` et ses correctifs/optimisations,
qualification segmented-Darcy `O4`, puis audit/calibration du régime SRC `W0–W3`,
normalisation des runners multi-espèces `W4` et construction/qualification du Q6
`independent_masked` `W5–W8`.

La curation conserve explicitement `0493O2-fix1` sans créer de `0493O2` autonome : le
suffixe est attesté par son checker, alors qu'un jalon parent distinct ne l'est pas. `0493W4`
est conservé avec confiance B à partir du runner et des inventaires; les étapes Git/README
explicites restent en confiance A.

Voir `Info/docs/CURATION_0493OW_V4_5.md`.

### V4.5.1 — grammaire Git des jalons 0493O*/0493W*

Le parseur de candidats Git accepte désormais les suffixes numériques `lettre+index`
(`0493O1`, `0493O1-fix2`, `0493W0` … `0493W8`). La famille `0493x...` reste
explicitement exclue de cette grammaire et continue d'être traitée comme famille `X`.
La règle conservatrice V3.1 sur les chemins n'est pas modifiée : une simple modification
d'un fichier numéroté ne crée toujours pas de nouveau candidat numérique.

Ce correctif rétablit la provenance Git des cycles O/W sans changer les jalons canoniques
curés en V4.5.

## Curation V4.6 — entrée dans la série 0493x

La V4.6 consolide `0493x0` et `0493x1` à partir de leurs README, runners et du checkpoint
Git commun. `x0`, absent du référentiel consolidé initial, devient la démonstration dam-break
bi-espèces du Q6 `independent_masked`. Le placeholder de confiance C `x1` est remplacé par
le jalon réellement attesté : extension des frontières CUDA résidentes à une boîte statique
fermée sur quatre faces, utilisée pour supprimer le vent gazeux artificiel de la première
version de x0.

Voir `Info/docs/CURATION_0493X01_V4_6.md`.


## Correctif V4.6.1 — désambiguïsation des labels X purement numériques

La V4.6.1 corrige la provenance Git des labels courts `x0`, `x1`, `x2`, etc. Ces
chaînes sont aussi utilisées comme notation géométrique (par exemple `x0` pour le bord
`x=0`) et ne doivent donc pas être agrégées globalement comme jalons X lorsqu'elles
apparaissent seules dans un chemin ou un sujet Git. Pour les labels X sans suffixe
alphabétique, le builder exige désormais la forme explicite `0493xN`. Les labels
qualifiés comme `x7q` ou `x14ai-fix1` conservent leur reconnaissance historique avec ou
sans préfixe `0493`. Pour les candidats X, `anchor_commit` est également recalculé
comme la première preuve Git chronologique, au lieu de dépendre de l’ordre d’import.

### V4.7 — x2 à x4b : séquençage Q6-g force-aware

La curation `0008_0493x2_x4b_q6_force_ordering.sql` consolide le diagnostic gravitaire x2,
la preuve de concept `prestream` x3, le mono-solve x4a et la fusion CUDA x4b. Ces jalons
existaient déjà dans le référentiel : V4.7 améliore leur définition et leur provenance sans
augmenter le nombre total de jalons. Voir `docs/CURATION_0493X2_X4B_V4_7.md`.

### V4.8 — x5a / x5a2 / x5b : première surface libre et gaz explicite

La curation `0009_0493x5_free_surface_and_explicit_gas.sql` consolide la première
séquence surface libre de 0493x. `x5a` introduit `free_surface_masked` sur un liquide
partiellement rempli en conservant le séquençage Q6-g fusionné de x4b. `x5a2` qualifie
cet opérateur inchangé sur un dam-break liquide-vide et met en évidence la distinction
nécessaire entre bord du support numérique et interface physique. `x5b` ajoute ensuite
une qualification bi-espèces avec gaz compressible explicite (`q6Strength=0`) couplé au
liquide par les collisions SRC mais sans pression gazeuse imposée au solve Q6.

Le README x5b précise que ce jalon ne change pas l'opérateur CUDA; sa nature canonique
passe donc de `CODE` à `QUALIFICATION`. V4.8 étend aussi la grammaire X aux suffixes
`lettres+chiffres` (`x5a2`, `x6f2`, ...) afin que ces jalons conservent leur provenance Git.
Aucun jalon nouveau n'est créé et le total reste inchangé. Voir
`docs/CURATION_0493X5_V4_8.md`.

### V4.9 — x6a à x6g : géométrie d’interface et pression gazeuse

La curation `0010_0493x6_phase_interface_architecture.sql` consolide la séparation entre
carrier numérique et interface physique : diagnostics EOS/géométrie x6a-x6b, champs
résidents x6c, expérience cut-face x6d, diagnostic topologique x6e, stencil physique x6f,
correctif géométrique x6f2 et condition de pression gazeuse x6g. `x6f2`, absent du canon
initial, est ajouté comme jalon `FIX`; le total passe donc de 196 à 197. Voir
`docs/CURATION_0493X6_V4_9.md`.


### V4.11 — x7a à x7e : restauration de densité Q6-g-f

La curation `0012_0493x7_density_restoration.sql` remplace l'ancienne entrée canonique agrégée `x7a/x7b` par les jalons réels x7a et x7b, ajoute x7c qui déplace la restauration de densité dans le RHS Q6, puis consolide x7d (constante de temps physique `tau_rho`) et x7e (qualification combinée avec la pression gaz x6g). La ligne brute x7a/x7b du snapshot historique reste conservée. Le total canonique passe de 197 à 199 jalons. Voir `docs/CURATION_0493X7A_X7E_V4_11.md`.

### V4.12 — x7f à x7n : généralisation, coût et diagnostic Q6-g-f

La curation `0013_0493x7f_x7n_postqualification.sql` consolide l'extension de Q6-g-f aux
familles statiques multi-BC (x7f), son couplage Darcy correctement ordonné (x7g), la
factorisation des comparaisons `run_ok` (x7h), le benchmark physique multi-cas (x7i) et
le CG entièrement CUDA résident (x7j). Elle remplace ensuite le placeholder `x7k/x7l`
par deux jalons PERF distincts, restaure `x7m-fix1` comme correctif canonique du domaine
de pression monophase et ajoute x7n, calibrateur/diagnostic de chemin absent du
référentiel initial.

Le patch runner `x7f-fix1` est conservé comme provenance sans devenir un jalon ; les
sous-fixes purement outillage de x7n restent regroupés sous x7n. La réparation physique
qui suit (`x7d-v2`/signed, x7o, x7p, x7q) est volontairement reportée à la curation
suivante afin de conserver la frontière diagnostic → correction. Voir
`docs/CURATION_0493X7F_X7N_V4_12.md`.

### V4.13 — x7d-v2 à x7q : restauration signée, symétrie et fermeture de moment

La curation `0014_0493x7d_v2_x7q_repairs.sql` reconstruit la séquence de réparation
ouverte par le diagnostic x7n. Elle ajoute trois jalons absents du canon (`x7d-v2`,
`x7d-v2-fix2`, `x7d-v2-signed1`), puis consolide x7o/x7p comme corrections de symétrie
par réflexion et x7q comme fermeture exacte du mode uniforme périodique au niveau de la
reconstruction particulaire B1/RT0. `x7d-v2-fix1` (complétion d'un patch interrompu) et
`x7d-v2-fix2a` (correction de gate) sont conservés comme preuves mais ne deviennent pas
des jalons autonomes. Le total canonique passe de 202 à **205 jalons**. Voir
`docs/CURATION_0493X7D_V2_X7Q_V4_13.md`.


### V4.15 — x8k à x8t : inlet Poiseuille segmenté et outlet Neumann cinétique-pression

La curation `0016_0493x8k_x8t_open_boundary.sql` reconstruit la seconde moitié du cycle x8. Elle consolide `x8k`, ajoute `x8l` (première extrapolation de vitesse Neumann), `x8m` (benchmark Zovatto Re_H=280) et `x8n` (diagnostic de conservation amont), puis consolide séparément `x8q`, `x8r`, `x8s` et `x8t` jusqu'à la fermeture passive complète : bain cinétique local, `phi_out=0`, déflation des modes lents et cible de densité sans mode moyen.

Aucun `x8o`/`x8p` n'est créé faute de preuve autonome. Les sous-révisions `x8q-fix*` restent attachées à x8q, et le candidat Git composite `x8q-x8t` reste une preuve agrégée plutôt qu'un jalon canonique. `x8u`, qui réaligne ensuite le runner restartable x8m sur les BC x8t validées, est reporté à la curation suivante. Le total canonique passe de 214 à **217 jalons**. Voir `docs/CURATION_0493X8K_X8T_V4_15.md`.


### V4.16 — x8u puis x9a à x9h : clôture VK et scaffold capillaire

Cette curation ferme le cycle x8 par `x8u`, updater runner-only qui réaligne la lignée restartable `x8m` sur la fermeture Neumann validée `x8t`. Elle regroupe ensuite, pour accélérer la curation sans fusionner les identités, le premier bloc cohérent de x9 : `x9a` scaffold passif, `x9b` binomial+Scharr, `x9c` sweep qui retient p3, `x9d` premier saut de Laplace actif, `x9e/x9f` diagnostics goutte/ellipse, `x9g` abstraction A/B et `x9h` provider de géométrie murale. Les prototypes d'angle de contact `x9i+` restent hors de V4.16. Le total canonique passe de 217 à **221 jalons**. Voir `docs/CURATION_0493X8U_X9A_X9H_V4_16.md`.

### V4.17 — clôture accélérée du cycle 0493x9 (x9i → x9z)

La curation `0018_0493x9i_x9z_wetting_kinetic_bridge.sql` remplace les agrégats historiques `x9a-x9c` et `x9i-x9l` par les identités effectivement attestées, consolide le mouillage x9m et ses qualifications x9n/x9o/x9p, le dripping/splash x9q/x9r/x9s, puis individualise le pont cinétique x9t→x9z vers la fermeture de surface libre x10. Les prototypes x9i–x9l restent documentés comme étapes historiques supplantées; x9m est la fermeture statique préférée mais sa dynamique de ligne triple reste limitée. x9r est reclassé comme correctif actif de résolution du saut `sigma*kappa`, et x9t–x9z sont classés fonctionnellement `FREE_SURFACE_KINETICS` tout en conservant leur identité de cycle x9.

Comme depuis V4.14, le patch de transition est **source-only** : `Info/db/src_reference_dump.sql` et `Info/generated/` sont reconstruits localement par `build_src_reference.py` et ne sont pas des préimages imposées par le patch.

### V4.18 — curation x10a→x10y

Individualise les agrégats x10, sépare ablations/diagnostics du chemin qualifié `x10o+CIC+Q2+x10p/q+x10u+x10v`, et clôt le cycle x10 de fermeture cinétique de surface libre. Voir `docs/CURATION_0493X10A_X10Y_V4_18.md`.

### V4.19 — x11 + x12 : validation quantitative et chaîne de production capillaire

La curation `0020_0493x11_x12_capillary_validation.sql` ferme x11 et x12 en un seul bloc : x11a/x11b deviennent des qualifications quantitatives, x11c est individualisé comme correction de protocole/diagnostic observation-only, x12a est identifié comme l’unique nouvelle physique runtime x12, l’agrégat x12b/x12c est séparé en deux benchmarks, puis x12d/x12yl/x12cal sont consolidés comme benchmark et calibrateurs. Le total canonique passe de 243 à **245 jalons**. Voir `docs/CURATION_0493X11_X12_V4_19.md`.

### V4.20 — x13 : fluide de référence, qualification surface libre et rollback Taylor–Culick

La curation `0021_0493x13_reference_tc_rollback.sql` ferme x13 jusqu’à `x13zd`. Elle requalifie x13a-h comme chaîne constitutive scripts-only, ajoute x13i, documente le double usage historique de x13j, consolide les qualifications gouttes/TC x13k-n, individualise les expériences x13p/q/r/s/u/v et la séquence de grille x13za/zb/zb2/zb3/zc, puis fixe x13zd comme validation croisée qui invalide x13t+x13w et motive le retour au tag `surf-tension-qualified-x13h-20260831`. Les agrégats x13r/x13s, x13u/x13v et x13za-x13zc disparaissent. Le total canonique passe de 245 à **254 jalons**. Voir `docs/CURATION_0493X13_V4_20.md`.

### V4.21 — x13ze+ et cycle x14 liquide/gaz jusqu'à x14av

La curation `0022_0493x13ze_x14av_liquid_gas.sql` ferme le post-rollback x13 avec les identités effectivement attestées `x13ze/zf/zg/zj/zk/zl/zn`, puis remplace l'agrégat `x14a-x14j` par les jalons x14 réellement documentés. Elle ajoute `x14a/b/c/e/f/i`, les diagnostics offline `x14p/q`, puis la séquence application-scale `x14an→x14av`. Aucun `x13zh/x13zi/x13zm` ni `x14h` n'est inventé.

Le statut reste volontairement différencié : x14at est une validation externe **ciblée** de la profondeur de cavité Sato pour `H/D=0.8` et `Fr'_m≈0.49–0.59` (écarts 4.8–9.9 %), tandis que `H/D=1.7` reste REVIEW; x14au est `INVALID` côté viscosité liquide primaire et `REVIEW` côté gaz; x14av reste `DEMONSTRATION_DIAGNOSTIC_ONLY`. Voir `docs/CURATION_0493X13ZE_X14AV_V4_21.md`.

Comme les curations récentes, le patch livré est strictement **source-only** : les bases/dumps et `Info/generated/*` sont reconstruits après application et ne font pas partie du patch de curation.


### V4.22 — branche Neumann multiphasique post-x14av

La curation `0023_post_x14av_neumann_multiphase.sql` documente la reconstruction
expérimentale de la sortie Neumann déclenchée par l'atomiseur x14av. Elle conserve
`x8q` comme jalon historique dans son domaine initial, ajoute la variante désambiguïsée
`x8r-neumann-species`, puis la séquence `x8v→x8z` et les branches
`x9a-neumann`, `x9b-neumann`, `x9c-outlet`. Les suffixes Neumann/outlet sont
indispensables : `x8r`, `x9a`, `x9b` et `x9c` désignent déjà des jalons historiques
antérieurs et ne sont pas retargetés.

La progression est conservée comme une chaîne de diagnostics et de corrections, et non
comme neuf PASS successifs : x8w réinjecte le bruit d'occupation de la cellule frontière,
x8y devient injecteur macroscopique en backflow, x8z/x9a-neumann ne ferment que
partiellement la cinématique du réservoir, et x9b-neumann révèle l'artefact topologique
« hachoir » lorsque le support de phase disparaît au dernier maillon. `x9c-outlet`
prolonge alors uniquement `alpha` d'une cellule sur l'outlet, sans synthétiser masse ni
moment; les runs 200×400 et 400×400 en font le candidat physics-first retenu, avec une
qualification applicative qualitative seulement. L'optimisation demandée ensuite reste
hors V4.22 faute d'artefact primaire complet. Voir
`docs/CURATION_POST_X14AV_NEUMANN_MULTIPHASE_V4_22.md`.

Le patch reste strictement **source-only** : `Info/db/src_reference_dump.sql`, la base
SQLite et `Info/generated/*` sont régénérés localement et ne sont pas livrés.

### V4.23 — x9d-fix1-neumann : optimisation résidente à physique x9c inchangée

La curation `0024_0493x9d_fix1_neumann_resident_opt.sql` ajoute un unique jalon PERF
post-V4.22. Le marqueur runtime atteste `physics=x9c_unchanged` et remplace plusieurs
coûts de gestion de l’outlet par un workspace persistant et des comptages exacts. Le
smoke B/O/B de 250 pas soutient la non-régression physique courte, mais **ne qualifie
pas le gain de performance** : les temps muraux 92.53/61.10/49.73 s montrent une
dispersion baseline supérieure à l’effet recherché. Aucun `x9e-neumann` n’est créé
sans preuve primaire. Voir `docs/CURATION_0493X9D_FIX1_NEUMANN_RESIDENT_OPT_V4_23.md`.

Le patch reste strictement **source-only** : les bases/dumps et `Info/generated/*`
sont reconstruits localement après application.

### V4.24 — fermeture Git de 0414 sur `surf`

La curation `0025_20260907_0414_git_reconciliation.sql` ne crée aucun nouveau jalon :
elle réconcilie explicitement le candidat numérique `0414` porté par le commit `e2fe1ca`
avec la clé déjà existante `20260907-0414-segmented-xy`. Après l'import Git, le builder
applique uniquement ce triplet exact; les anciens usages historiques du numéro `0414`
restent volontairement distincts. Le commit d'introduction et la preuve Git sont désormais
explicites. Voir
`docs/CURATION_20260907_0414_GIT_RECONCILIATION_V4_24.md`.

Le patch reste strictement **source-only** : les bases/dumps et `Info/generated/*` sont
reconstruits localement après application.


### V4.25 — clôture documentaire de la branche `surf`

L'audit de périmètre final a confirmé que les curations provisoires V4.22/V4.23
reposaient sur des artefacts du worktree `SRC_GPU-SURF-x8q-ablation` et non sur le
`HEAD` de la branche `surf`. Elles sont donc retirées de la base `surf` avec leurs
preuves locales. Ces développements pourront être documentés ultérieurement dans un
périmètre expérimental séparé, sans retargeter les jalons historiques de `surf`.

La frontière `surf` reste celle fermée par V4.21 pour la physique x13/x14, complétée
par la réconciliation Git V4.24 du jalon namespacé `20260907-0414-segmented-xy` avec
le commit `e2fe1ca`. Aucun nouveau jalon physique n'est créé en V4.25. Voir
`docs/CURATION_SURF_SCOPE_CLOSURE_V4_25.md`.

Le patch reste strictement **source-only** : aucune base SQLite, aucun dump SQL ni
`Info/generated/*` n'est livré. **Cette section décrit l'état V4.25** ; après le cherry-pick
du 10 septembre, cette frontière est rouverte par V4.27 et les curations V4.22/V4.23 sont
réintégrées au canon.

### V4.26 — lexique rapide des jalons et glossaire des sigles

Cette évolution de publication n'ajoute ni ne retire aucun jalon canonique. Elle ajoute
`Info/generated/lexique_jalons.md` et son CSV, triés en ordre naturel numérique puis
alphabétique (`x9...` avant `x10...`, suffixes `fix2` avant `fix10`). Chaque ligne expose
le jalon, sa famille, un **type/support concret** (modification code, runner, analyseur,
calibrateur, etc.), sa nature canonique, sa fonction et son statut.

`Info/docs/GLOSSAIRE_SIGLES.md` complète ce lexique par une liste alphabétique des
sigles et notions récurrents (`Q6-g-f`, `CIC`, `RT0`, `TC`, `TG`, `VK`, etc.). Le lexique
est généré depuis SQLite; le glossaire est volontairement curé manuellement.

### V4.27 — réintégration Neumann multiphasique après cherry-pick

La lignée développée initialement dans `SRC_GPU-SURF-x8q-ablation` a désormais été
intégrée au dépôt canonique `surf`. V4.27 restaure donc sans les réécrire les curations
`0023` (x8r-neumann-species→x9c-outlet) et `0024` (x9d-fix1-neumann), que V4.25 avait
correctement retirées tant que leur code restait hors branche. La curation
`0027_0493x9e_neumann_optimization.sql` poursuit ensuite la chaîne avec `x9e-neumann`,
`x9e-fix1`, `x9e-fix2`, `x9e-fix2b` et `x9e-fix3`.

`x9e-fix3` est le chemin d'optimisation final : pool de recyclage x9e inchangé, réparation
exacte ciblée sur le support muté et fallback `0315c` exact. Le package de cleanup atteste
une validation longue pré-cleanup de 3000 pas; le smoke final après intégration `surf`
termine 250/250 en 400×400 avec le fast path `targeted_deleted_list_exact` actif et sans
fallback observé. La physique reste explicitement celle de `x9c-outlet`; aucune
qualification universelle de toute sortie Neumann n'est extrapolée.

Le total canonique attendu passe de 277 à **292 jalons**. Le snapshot ENV x14ai historique
reste intact; un nouvel inventaire actif du 10 septembre ajoute 25 contrôles Neumann et
porte `raw_env_inventory` de 524 à **549** lignes, sans nouveau paramètre `.kv`.
`Info/generated/lexique_jalons.md`, `flags.md` et les autres publications sont régénérés
automatiquement par le builder. Voir `docs/CURATION_0493X9E_NEUMANN_OPT_V4_27.md`.

### V4.28 — fermeture Git de x9e-fix3

Aucun jalon n'est ajouté. La curation `0028_0493x9e_fix3_git_reconciliation.sql`
ancre `0493x9e-fix3` sur le commit canonique
`6dfda0404c2066f3db378a5d27c30a6dcc898d39` et sur le tag officiel
`surf-neumann-qualified-x9e-fix3-20260910`. Après import Git, le builder réconcilie
le candidat daté `x9e-fix3-20260910`, produit par le nom du tag, vers le jalon
`x9e-fix3` : le suffixe `20260910` est une date de qualification et non un nouveau
jalon. La résolution exige le tag et le SHA exacts et n'élargit pas l'heuristique
générique des labels X. Voir
`docs/CURATION_0493X9E_FIX3_GIT_RECONCILIATION_V4_28.md`.

### V4.29 — inventaires courants et classement naturel des vues

V4.29 ne modifie aucune donnée scientifique. Elle rafraîchit le snapshot paramètres au
10 septembre 2026 en attestant explicitement qu'aucune nouvelle clé `.kv` n'a été introduite
par la chaîne Neumann x8q→x9e-fix3 : le nouveau snapshot paramètres est byte-identique à celui
du 4 septembre et `raw_params_inventory` reste 854. Le snapshot ENV x9e-fix3 reste la source
active à 549 entrées brutes et 650 symboles ENV publiés.

Les vues `parametres.md` et `flags.md` utilisent désormais un tri alphabétique naturel.
`jalons_par_nature.md` conserve le regroupement par nature mais trie chaque groupe en ordre
naturel numérique/alphanumérique. Le lexique global `lexique_jalons.md` reste le point d'entrée
rapide pour les 292 jalons. Voir `docs/INVENTAIRES_PUBLICATION_V4_29.md`.

### V4.30 — x14aw→x14bc : benchmark Basilisk, alpha_x6c, pulsation et liquide froid

V4.30 documente la séquence expérimentale du 11 septembre 2026 sans inventer les labels
intermédiaires absents. La curation `0029_0493x14aw_x14bc_basilisk_cold.sql` ajoute exactement
les jalons attestés `x14aw`, `x14ax`, `x14ay`, `x14az`, `x14ba` et `x14bc`. Les labels
`x14bb`/`x14bb2` ne sont pas promus : `0493x14bb2` n'était qu'un label de campagne de
calibration.

La séquence couvre l'analogue 2-D Basilisk ReL=500/WeG=200 (`x14aw`), l'accès recorder
`alpha_x6c` (`x14ax`), l'ablation gamma 12/16 non retenue (`x14ay`), l'affichage LiveVis
`alpha_x6c` (`x14az`), la loi sinusoïdale globale d'entrée et sa continuité de phase au restart
(`x14ba`), puis le runner froid pulsé `x14bc`. La calibration liquide finale est TG128, 8 graines,
PASS : `kBT_L=0.0078125`, `nu_L=0.0002122268985`, `CV=2.2%`. Le gaz conserve
`nu_G=0.0003536191886`; l'égalité stricte des viscosités cinématiques n'est pas imposée.

Les six nouvelles clés solveur `inletVelocityOscillation*` sont ajoutées au snapshot paramètres.
Le snapshot ENV est rafraîchi avec les contrôles explicites du benchmark/restart/recording x14aw–x14bc.
Les sources primaires exactes, le log TG et les captures qualitatives sélectionnées sont archivés sous
`inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip`. Voir
`docs/CURATION_0493X14AW_X14BC_BASILISK_COLD_V4_30.md`.

# Base de référence SRC_GPU-SURF

Cette arborescence contient la première base relationnelle unifiée du projet. Elle remplace progressivement la gestion de tableaux indépendants pour les jalons, paramètres, flags, runners et analyseurs.

## Principe

La base opérationnelle est `src_reference.sqlite` (SQLite). Une reconstruction complète est faite par `scripts/build_src_reference.py` dans un fichier temporaire, validée par `PRAGMA quick_check` et `PRAGMA foreign_key_check`, puis remplacée atomiquement. Une erreur d'import ou d'audit ne laisse donc jamais une base partiellement mise à jour.

Les fichiers sous `raw_inputs/` sont des **snapshots bruts immuables** servant de provenance. Ils ne sont pas des bases autonomes à maintenir manuellement. Les corrections/compléments documentaires sont des migrations SQL versionnées sous `migrations/`.

`src_reference_dump.sql` est un export déterministe destiné à la revue Git. Il n'est pas la source primaire en exécution.

## Modèle

La table `objects` fournit un registre commun. Les relations ont ainsi de vraies clés étrangères entre objets de nature différente.

- `milestones` : jalons/phases (`x14ai`, `x8r`, 0414 courant, etc.).
- `symbols` : paramètres `.kv`, flags d'environnement, clés LiveVis/control et métadonnées de sortie.
- `symbol_names` : noms canoniques, champs C++, clés `.kv`, aliases parseur/runner.
- `artifacts` : sources, runners, analyseurs, générateurs, checkers, documentation, outils MATLAB, etc.
- `relations` : liens typés (`SETS_PARAMETER`, `DEFINED_OR_USED_IN`, `ASSOCIATED_WITH`, `QUALIFIES`, `EXTENDS`, `FIXES`, ...).
- `evidence` : provenance documentaire/Git.
- `git_commits`, `git_tags` : historique Git importé quand `.git` est disponible.
- `raw_*` : conservation exacte des inventaires et du référentiel source.
- `search_fts` : index plein texte SQLite FTS5.

### Identifiants de jalons

Les labels historiques ne sont pas supposés uniques. En particulier, un suffixe numérique tel que `0414` peut exister dans plusieurs époques du projet. La base sépare donc :

- `milestone_id` : label humain (`x14ai`, `0414`), potentiellement ambigu ;
- `milestone_key` : clé interne unique et namespacée (`0493x14ai`, `20260907-0414-segmented-xy`) ;
- `canonical_id` : identifiant canonique quand il existe.

Le scanner **n'associe jamais automatiquement un simple suffixe numérique 0xxx** trouvé dans un nom de fichier. Les identifiants `x...` peuvent être liés automatiquement ; les anciens numéros seront reliés lors de l'audit Git/documentaire avec une preuve plus forte.

## Reconstruction

Depuis la racine du dépôt :

```bash
python3 scripts/build_src_reference.py
```

Le builder :

1. importe le référentiel x... actuel ;
2. importe les inventaires paramètres et flags dans les tables brutes ;
3. normalise les symboles et aliases ;
4. scanne l'arborescence du dépôt et classe les artefacts ;
5. applique les migrations SQL documentaires ;
6. construit les relations symboles ↔ fichiers, flags ↔ paramètres, symboles ↔ jalons, artefacts ↔ jalons ;
7. importe `git log` et les tags si le dépôt contient `.git` ;
8. reconstruit l'index plein texte ;
9. vérifie l'intégrité et remplace la base atomiquement.

## Consultation

```bash
python3 scripts/query_src_reference.py milestone x14ai
python3 scripts/query_src_reference.py milestone x14ai-fix1
python3 scripts/query_src_reference.py milestone 20260907-0414-segmented-xy

python3 scripts/query_src_reference.py param wallKBT
python3 scripts/query_src_reference.py flag WALL_KBT
python3 scripts/query_src_reference.py param q6PressureOutletDeflationEnable

python3 scripts/query_src_reference.py artifact run_0493x14ai_drag_device_closure.sh
python3 scripts/query_src_reference.py search "surface tension"
python3 scripts/query_src_reference.py stats
python3 scripts/query_src_reference.py doctor
```

### Exemple de navigation

`param wallKBT` expose la valeur par défaut, les contraintes et les fichiers C++ qui le définissent. La relation inverse montre que `WALL_KBT` est un alias de runner qui écrit ce paramètre.

`milestone x14ai-fix1` remonte les flags dont les métadonnées mentionnent explicitement ce jalon, ainsi que les artefacts associés et la relation `FIXES` vers `x14ai`.

## État de cette V1

La base fournie a été construite depuis :

- le référentiel consolidé au 5 septembre 2026 ;
- l'inventaire paramètres snapshot 04/09 x14ai ;
- l'inventaire flags snapshot 04/09 x14ai ;
- le snapshot de dépôt `snap_070926.zip` pour le scan d'artefacts ;
- une migration documentant le chantier 0414 courant et son nouveau switch x8s.

Le snapshot ZIP ne contient pas `.git`, donc la base fournie indique `git_import_status=skipped:no-.git`. Après installation dans le vrai dépôt Git, une reconstruction importera l'historique local complet sans changement de schéma.

## Étapes suivantes prévues

La prochaine phase est l'audit historique : importer les commits/tags et les README de jalons 0175–0493, créer les jalons pré-x manquants, puis relier explicitement runners/analyseurs/calibrateurs aux fonctionnalités qu'ils qualifient. Les corrections seront ajoutées par migrations SQL plutôt que par modification manuelle de plusieurs tableaux.

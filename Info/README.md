# Info — base de référence SRC_GPU-SURF

`Info/` est le sous-système documentaire versionné du projet SRC_GPU-SURF. Il est volontairement séparé du code de calcul (`src/`, `include/`), des runners/analyseurs (`scripts/`, `matlab/`) et des outils temporaires (`tools/`).

Son objectif est de maintenir **une seule base relationnelle** reliant :

- les jalons/phases du développement (`x14ai`, `x8r`, 0414 courant, anciens jalons numériques, etc.) ;
- les paramètres `.kv`, champs C++ et alias de runners ;
- les variables d'environnement / flags ;
- les sources, runners, générateurs, analyseurs, calibrateurs et documentation ;
- les commits/tags Git et les preuves documentaires ;
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
│   └── snapshots/
│       ├── referentiel_jalons_SRC_GPU_SURF_20260905.tex
│       ├── src_mpcd_params_inventory_snapshot_040926_x14ai.csv
│       └── src_mpcd_env_flags_inventory_snapshot_040926_x14ai.csv
├── curations/
│   └── 0001_current_0414_segmented_xy.sql
├── scripts/
│   ├── build_src_reference.py
│   └── query_src_reference.py
└── docs/
    ├── ARCHITECTURE.md
    └── BOOTSTRAP_AUDIT.md
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
2. `Info/inputs/snapshots/` — inventaires/référentiels bruts conservés comme provenance ;
3. `Info/reference_sources.json` — manifeste indiquant quels snapshots sont actifs ;
4. `Info/curations/*.sql` — compléments/corrections documentaires versionnés ;
5. le dépôt lui-même — arborescence du code et historique Git.

Les curations ne sont pas des migrations de schéma. Elles ajoutent ou corrigent de la connaissance documentaire sans modifier le builder. Les futures vraies migrations de schéma disposent d'une table séparée `schema_migrations`.

Le builder travaille dans `src_reference.sqlite.tmp`, vérifie `PRAGMA quick_check` et `PRAGMA foreign_key_check`, puis remplace la base atomiquement. Une erreur d'import ne laisse donc jamais une base partiellement mise à jour.

`src_reference_dump.sql` est produit en parallèle pour rendre les modifications de contenu inspectables dans Git. `src_reference.sqlite` est déclaré binaire par `Info/.gitattributes`.

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
9. importe `git log --all` et les tags si Git est disponible ;
10. reconstruit l'index plein texte ;
11. valide l'intégrité et remplace la base atomiquement.

Les chemins absolus de la machine ne sont pas écrits comme identité documentaire dans la base : `meta.repo_root='.'` et `meta.info_root='Info'` dans l'installation normale.

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

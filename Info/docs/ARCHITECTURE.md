# Architecture relationnelle de `Info/`

`Info/` est un sous-système documentaire autonome placé à la racine du dépôt, mais il décrit le dépôt complet.

```text
SRC_GPU-SURF/
├── src/
├── include/
├── scripts/
├── matlab/
├── ...
└── Info/                 <- base documentaire
    ├── db/
    ├── inputs/
    ├── curations/
    ├── scripts/
    └── docs/
```

Le builder maintient deux notions différentes :

```text
repo_root = SRC_GPU-SURF/
info_root = SRC_GPU-SURF/Info/
```

Le scan d'artefacts porte sur le dépôt de calcul et exclut `Info/` par conception.

## Graphe d'objets

```text
objects
  ├── milestones
  ├── symbols ──< symbol_names
  ├── artifacts
  └── git commits
       │
       └──────── relations ────────┐
             source_object_id      │
             relation_type         │
             target_object_id ─────┘
```

Exemples :

```text
symbol:env:WALL_KBT
    --SETS_PARAMETER-->
symbol:param:wallKBT
    --DEFINED_OR_USED_IN-->
artifact:src/params_io_base.cpp
```

```text
milestone:0493x14ai-fix1
    --FIXES-->
milestone:0493x14ai

symbol:env:MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE
    --ASSOCIATED_WITH-->
milestone:0493x14ai-fix1
```

```text
artifact:scripts/run_0414_segmented_xy_neumann_qualification.sh
    --QUALIFIES-->
milestone:20260907-0414-segmented-xy
    --EXTENDS-->
milestone:0493x8r / x8s / x8t / x8k
```

## Sources brutes, curations et données générées

La base distingue trois couches :

```text
inputs/snapshots/     données brutes de provenance
        │
        ├──── repo Git + arborescence
        │
        ▼
normalisation automatique par Info/scripts/build_src_reference.py
        │
        ├──── curations/*.sql
        ▼
db/src_reference.sqlite + db/src_reference_dump.sql
```

Cette séparation permet de reconstruire la base après évolution des règles de normalisation sans perdre l'inventaire historique original.

## Schéma unique

`Info/db/schema.sql` est l'unique définition du schéma. Le builder ne contient aucune copie embarquée du DDL.

- `schema_migrations` est réservé aux futures évolutions structurelles de la base ;
- `curations_applied` enregistre les compléments documentaires appliqués lors d'une reconstruction.

## Manifeste de sources

`Info/reference_sources.json` sélectionne les snapshots courants. Un changement d'inventaire ne nécessite donc pas de modifier le code Python.

## Portabilité Git

Les chemins d'artefacts sont relatifs à `repo_root`. Les métadonnées persistantes normales sont elles aussi stables : `.` pour le dépôt et `Info` pour le sous-système documentaire. Les chemins absolus ne servent qu'au runtime et ne doivent pas provoquer de diff Git selon la machine.

## Niveaux de confiance

Les relations automatiques sont associées à un niveau de confiance :

- `A` : relation explicite/provenance directe ;
- `B` : inférence structurée forte ;
- `C` : inférence textuelle/historique à confirmer.


## Extension V3 — graphe Git historique

La V3 ajoute une couche d'audit qui ne promeut jamais directement un ancien identifiant numérique en jalon canonique.

```text
git_commits
   ├──< git_commit_files
   ├──< git_commit_refs >── git_refs
   ├──< git_branch_commit_status >── git_branch_audit
   ├──1 git_commit_mainline_status
   └──< git_candidate_evidence >── git_milestone_candidates

git_tags ────────────────┘
```

### Ligne principale

La référence par défaut est `origin/surf`. Le builder calcule pour chaque branche :

```text
ANCESTOR_OF_MAINLINE
PATCH_EQUIVALENT_IN_MAINLINE
HAS_UNIQUE_PATCHES
MAINLINE
AUDIT_ERROR
```

Au niveau commit :

```text
IN_MAINLINE
PATCH_EQUIVALENT_IN_MAINLINE
UNIQUE_OUTSIDE_MAINLINE
```

`git_branch_commit_status` conserve le résultat `git cherry` **par branche** ; `git_commit_mainline_status` donne une synthèse globale par commit.

### Candidats historiques

Deux familles sont distinguées :

- `X` : `x3`, `x14ai-fix1`, etc. ; agrégation globale autorisée et lien automatique possible vers `milestones` ;
- `NUMERIC` : `0175`, `0334a`, `0414`, `0490A`, etc. ; chaque candidat reste ancré à un commit afin d'éviter les collisions historiques.

Exemple volontaire : deux commits contenant `0414` produisent deux `candidate_id` différents. La fusion éventuelle relève d'une curation explicite.

Les preuves automatiques sont classées `A/B/C` selon leur force : tag ou sujet explicitement préfixé, chemin README/artefact, branche ou mention contextuelle.

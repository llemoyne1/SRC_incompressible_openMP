# Audit bootstrap — base de référence sous `Info/`

## Sources initiales

- Référentiel jalons consolidé 05/09/2026 : 138 lignes de jalons/phases.
- Inventaire paramètres snapshot 04/09 x14ai : 854 lignes brutes.
- Inventaire flags snapshot 04/09 x14ai : 524 lignes brutes.
- `snap_070926.zip` : scan de l'arborescence du code hors `Info/`.
- Curation `0001_current_0414_segmented_xy.sql` : chantier 0414 courant et switch x8s ajouté après les inventaires du 04/09.

## Adaptations de migration vers `Info/`

1. séparation `repo_root` / `info_root` ;
2. détection de la racine du dépôt par Git avec fallback archive ;
3. déplacement de la base sous `Info/db/` ;
4. déplacement des scripts documentaires sous `Info/scripts/` ;
5. schéma SQL retiré du builder et chargé exclusivement depuis `Info/db/schema.sql` ;
6. snapshots sélectionnés par `Info/reference_sources.json` ;
7. anciennes « migrations » documentaires renommées en `curations/` et suivies dans `curations_applied` ;
8. métadonnées de chemins rendues stables entre machines ;
9. `Info/` volontairement exclu du scan des artefacts de calcul ;
10. fichiers temporaires SQLite ignorés, base binaire déclarée via `.gitattributes`.

## Smoke test archive sans `.git`

Installation testée avec `Info/` directement sous une extraction de `snap_070926.zip` :

- 139 jalons/phases ;
- 965 symboles normalisés ;
- 1523 noms/aliases ;
- 984 artefacts ;
- 2546 relations typées ;
- 138 preuves documentaires ;
- 1 curation appliquée ;
- `git_import_status=skipped:no-git-worktree` attendu ;
- `PRAGMA quick_check = ok` ;
- 0 violation de clé étrangère ;
- 0 relation orpheline.

## Cas tests de navigation

### `wallKBT`

La requête retrouve le type `double`, le défaut `-1.0`, l'héritage depuis `kBT`, les fichiers C++ et la relation inverse depuis `WALL_KBT`.

### `x14ai-fix1`

La requête retrouve la définition, `FIXES -> x14ai`, le flag principal de fermeture de résultante et les prérequis associés.

### collision `0414`

Le chantier courant reste sous la clé `20260907-0414-segmented-xy`. Aucun simple suffixe numérique de nom de fichier n'est utilisé comme identité globale.

## Étape suivante

Après installation dans le clone Git réel, une reconstruction doit importer `git log --all` et les tags. Cette phase alimentera ensuite l'audit exhaustif des jalons pré-`x`, sans modification du schéma de base.

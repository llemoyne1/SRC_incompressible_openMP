# Audit bootstrap — base de référence SRC_GPU-SURF v1

## Sources importées

- Référentiel jalons consolidé 05/09/2026 : 138 lignes de jalons/phases.
- Inventaire paramètres snapshot 04/09 x14ai : 854 lignes brutes.
- Inventaire flags snapshot 04/09 x14ai : 524 lignes brutes.
- `snap_070926.zip` : scan de l'arborescence `scripts/`, `matlab/`, `src/`, `include/`, documentation et outils.
- Migration `0001_current_0414_segmented_xy.sql` : chantier courant 0414 et switch x8s ajouté après les inventaires du 04/09.

## Base construite

- 139 jalons/phases ;
- 965 symboles normalisés ;
- 1523 noms/aliases de symboles ;
- 984 artefacts ;
- 2546 relations typées ;
- 138 preuves documentaires explicites ;
- 1 migration SQL appliquée.

Les lignes brutes restent disponibles dans `raw_params_inventory`, `raw_env_inventory` et `raw_milestone_rows`.

## Contrôles

- `PRAGMA quick_check = ok` ;
- 0 violation de clé étrangère ;
- 0 relation orpheline ;
- test d'échec d'import : la base précédente reste byte-for-byte inchangée ;
- smoke Git local : commit `x14ai` détecté et relié ;
- tag Git annoté : import correctement résolu vers le commit sous-jacent.

## Cas tests de navigation

### x14ai-fix1

La requête retrouve :

- la fonction et le statut du jalon ;
- la relation `FIXES -> x14ai` ;
- le flag `MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE` ;
- les flags/prérequis x14ad associés ;
- les paramètres de phase dont les métadonnées mentionnent explicitement x14ai-fix1.

### wallKBT

La requête retrouve :

- type `double` ;
- défaut `-1.0` ;
- contrainte `négatif => hérite de kBT` ;
- champ C++ et clé `.kv` `wallKBT` ;
- définitions dans `include/simulation_params.h` et `src/params_io_base.cpp` ;
- relation inverse depuis l'alias runner `WALL_KBT`.

### collision du label 0414

Le scanner a révélé qu'un ancien runner NACA/Darcy porte déjà le suffixe `0414`. Les suffixes numériques ne sont donc pas des identifiants globaux sûrs. Le chantier courant est enregistré sous la clé unique :

`20260907-0414-segmented-xy`

et le scanner refuse d'associer automatiquement les artefacts sur la seule présence d'un numéro `0xxx`.

## Limites connues de cette V1

1. Le ZIP de snapshot ne contient pas `.git`, donc la base fournie n'a pas encore les 427 commits de la branche `surf`. Le builder les importera lorsqu'il sera exécuté dans le vrai clone Git.
2. Les jalons historiques 0175–0493 pré-`x` ne sont pas encore créés comme entités exhaustives ; l'audit Git/README constitue la phase suivante.
3. Les relations automatiques de confiance B/C doivent progressivement être confirmées par commits, README de jalons ou code source.
4. Le référentiel LaTeX actuel est encore une entrée brute. Une future étape générera les vues LaTeX/PDF directement depuis SQLite.
5. La classification `nature` des 138 jalons historiques est initialement heuristique ; elle doit être revue pendant l'audit historique.

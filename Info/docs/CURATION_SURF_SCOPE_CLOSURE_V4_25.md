# V4.25 — clôture du périmètre documentaire `surf`

## Objet

V4.25 ferme la reconstruction historique de la branche `surf`. Elle ne crée aucun
nouveau jalon physique. Son rôle est de corriger le périmètre après l'audit final des
branches et worktrees.

## Correction de périmètre V4.22/V4.23

Les curations provisoires V4.22 et V4.23 avaient été construites à partir de paquets,
logs et marqueurs runtime provenant du worktree expérimental
`SRC_GPU-SURF-x8q-ablation`. Le contrôle direct du `HEAD` de `surf` n'y retrouve pas
les marqueurs `0493x9c-outlet`, `0493x9d-fix1-neumann`,
`resident_workspace_exact_counts` ou `phase_support_continuation`.

Ces éléments ne doivent donc pas appartenir à la base canonique de `surf`. V4.25 retire :

- `0023_post_x14av_neumann_multiphase.sql` et ses neuf jalons ajoutés ;
- `0024_0493x9d_fix1_neumann_resident_opt.sql` et son jalon PERF ;
- les documents, logs, validations et archives de provenance issus de ce worktree.

Aucune conclusion scientifique portée par ces expériences n'est niée : elles sont
simplement réservées à une future curation explicitement scoped sur le worktree ou sur
une branche qui les intégrera réellement.

## Frontière finale de `surf`

La physique post-rollback x13 et le cycle liquide/gaz x14 restent fermés par V4.21,
jusqu'à `0493x14av`. Le dernier développement solveur attesté sur `surf`, le commit
`e2fe1ca29042c2391cd5b6ee7f9eb7fe9a2065a8` (`0414: generalize segmented open
boundaries to x/y on CUDA resident path`), correspond au jalon déjà existant
`20260907-0414-segmented-xy`. V4.24 a fermé sa réconciliation Git sans créer de doublon.

V4.25 conserve cette réconciliation et retire uniquement les éléments hors périmètre.

## Règle pour la suite

La base `surf` peut maintenant être considérée comme documentairement fermée à cette
frontière. Toute curation ultérieure du worktree `SRC_GPU-SURF-x8q-ablation` devra être
explicitement séparée et ne devra pas être présentée comme histoire de `surf` tant que
les changements correspondants ne sont pas intégrés à cette branche.

Le patch V4.25 reste strictement **source-only** : aucune base SQLite, aucun dump SQL,
aucun `Info/generated/*`, aucun fichier `src/*`, `include/*`, runner solveur ou
`livevis_control.kv` n'est livré.

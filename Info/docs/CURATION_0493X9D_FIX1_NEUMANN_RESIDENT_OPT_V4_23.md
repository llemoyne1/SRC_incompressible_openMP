# V4.23 — 0493x9d-fix1-neumann : optimisation résidente de la sortie Neumann

## Périmètre

Cette curation ajoute **un seul jalon** après V4.22 : `0493x9d-fix1-neumann`.
Elle ne crée pas de `x9e-neumann` faute de preuve primaire correspondante et ne modifie
aucun des jalons capillaires historiques `x9a/x9b/x9c/x9d`.

## Preuve primaire

La preuve conservée est le transcript runtime fourni le 9 septembre 2026. Le binaire
optimisé s'identifie par le marqueur :

`[0493x9d-fix1-neumann] mode=resident_workspace_exact_counts physics=x9c_unchanged ...`

Le reste du marqueur décrit une optimisation d'implémentation : compteurs persistants,
`tailPool=persistent_exact`, métadonnées d'espèce `change_only`, suppression de la
synchronisation `preCandidateSync`, comptages hôte exacts des candidats et slots
inactifs, géométrie de lancement exacte et buffer candidats préservé. Le fallback
`legacy_exact` reste annoncé.

## Non-régression physique courte

Le protocole B/O/B exécute 250 pas sur la même géométrie 200x400 :

| run | Nliq final | x99 final | wall |
|---|---:|---:|---:|
| x9c baseline 1 | 8542 | 0.309473 | 92.53 s |
| x9d-fix1 | 8578 | 0.308004 | 61.10 s |
| x9c baseline 2 | 8577 | 0.311155 | 49.73 s |

Les observables de démonstration restent cohérentes à ce niveau court, ce qui soutient
la déclaration `physics=x9c_unchanged`. Cela ne constitue pas une nouvelle qualification
physique de la BC Neumann ni de l'atomiseur.

## Performance : conclusion volontairement limitée

Le premier couple baseline/optimisé suggère une baisse de temps, mais le second baseline
est encore plus rapide que le run optimisé. La dispersion de temps mural domine donc la
comparaison. V4.23 classe le jalon `PERF` au sens de sa **nature d'implémentation**, mais
son statut indique explicitement que le gain de performance n'est **pas qualifié** par
ce triplet de runs.

Une qualification performance future devra utiliser un protocole contrôlé (LiveVis et
recording neutralisés ou identiques, plusieurs répétitions, même état/preimage, statistiques
sur temps/pas hors warm-up).

## Provenance

`Info/inputs/historical/0493x9d_fix1_neumann_resident_opt_original_sources.zip`
conserve le transcript fourni byte-for-byte et contient son manifeste SHA-256.

Le patch V4.23 reste source-only : aucune base SQLite, aucun dump SQL généré et aucun
`Info/generated/*` ne doit être livré dans le patch.

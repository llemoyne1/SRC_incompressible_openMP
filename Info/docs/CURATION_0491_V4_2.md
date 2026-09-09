# Curation V4.4 — correction de la série 0491 species-Q6

## Objet

La V4.2.1 avait retiré `0491B` et `0491C` parce qu'aucun candidat numérique Git ne
survivait pour ces deux labels. Cette règle était trop restrictive : **l'absence de label
dans le graphe Git ne prouve pas l'absence d'un jalon**, notamment lorsque plusieurs
portes de développement ont été consolidées dans un même commit.

Deux archives techniques maintenant versionnées sous `Info/inputs/historical/` corrigent
ce point :

- `conception_q6_multiespeces_cuda_resident_0491.tex` définit explicitement le plan
  `0491A` à `0491H`, notamment `0491B` (dépôt partagé + shadow CUDA) et `0491C`
  (application CUDA opt-in) ;
- `rapport_mpcd_incompressible_complete_0493w1_calibration_q6_multiespeces.tex` décrit
  rétrospectivement l'extension comme ayant été **construite par portes successives** et
  nomme à nouveau `0491B` et `0491C`.

La V4.4 restaure donc ces deux jalons dans le canon, avec une confiance `B` et sans leur
inventer de SHA d'introduction. Les jalons A et D–H/H-fix1 conservent leur ancrage Git.

## Jalons canoniques

| Jalon | Nature | Provenance primaire | Rôle |
|---|---|---|---|
| 0491A | INFRA | Git + README | contrat species-Q6 et référence CPU |
| 0491B | CODE | documentation historique | dépôt partagé et shadow CUDA |
| 0491C | CODE | documentation historique + traces code | application CUDA opt-in |
| 0491D | QUALIFICATION | Git + runner | matrice des quatre chemins |
| 0491E | QUALIFICATION | Git + runner | audit résident strict |
| 0491F | QUALIFICATION | Git + runner | énergie et thermostat |
| 0491G | QUALIFICATION | Git + runner | frontières/Darcy |
| 0491H | QUALIFICATION | Git + runners | campagne consolidée |
| 0491H-fix1 | FIX | Git + README | correctif final et qualification approfondie |

## Politique de preuve retenue

Un jalon peut désormais être canonique s'il est soutenu par une preuve historique forte,
même sans candidat Git numérique. La base distingue donc :

1. **Git-attesté** : label présent dans commit, chemin créé ou README/runners ;
2. **document-attesté** : archive de conception ou rapport rétrospectif explicite ;
3. **code-attesté** : commentaire/contrat runtime ou implémentation conservant le label.

La réconciliation automatique avec `git_milestone_candidates` reste conservatrice et ne
concerne que les jalons pour lesquels un candidat sûr existe. `0491B/C` restent donc
canoniques avec `introduced_commit=NULL` tant qu'un ancrage Git non ambigu n'est pas
établi.

## Chaîne fonctionnelle

`0491A -> 0491B -> 0491C` représente la progression contrat CPU, shadow CUDA puis
application dynamique. Les qualifications D–G valident ensuite le chemin C, H consolide
la campagne et `H-fix1` ferme la série.

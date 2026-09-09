# Curation V4.1.1 — série historique 0490A–P

## Objet

Cette curation est la première promotion structurée du backlog Git numérique vers le
référentiel canonique. Elle couvre la chaîne multi-espèces/resampling documentée par les
README `README_0490*.md`.

La curation ajoute 18 jalons :

| Jalon | Nature | Fonction documentée |
|---|---|---|
| `0490A` | INFRA | registre des espèces |
| `0490B` | CODE | dépôt cellule–espèce |
| `0490C` | CODE | resampling conservatif par espèce |
| `0490D` | CODE | fermeture de masse sensible à la phase |
| `0490E` | CODE | garde de population par espèce |
| `0490F` | CODE | refill d'espèces mixtes |
| `0490G` | CODE | transferts donneur–receveur par espèce |
| `0490H` | CODE | dépôt cellule–espèce CUDA |
| `0490I` | CODE | fermeture de masse multi-espèces CUDA |
| `0490J` | CODE | garde de population multi-espèces CUDA |
| `0490K` | CODE | plan de transferts multi-espèces CUDA |
| `0490L` | QUALIFICATION | validation du chemin résident |
| `0490M` | PERF | fast path CUDA résident |
| `0490M-fix2` | FIX | fermeture conservative du chemin résident |
| `0490N` | CODE | maintenance résidente multi-espèces |
| `0490N-fix1` | DIAGNOSTIC | télémétrie résidente par espèce |
| `0490N-fix2` | FIX | matérialisation de transferts multiples |
| `0490P` | PERF | politique cellule sur device / zéro CPU |

## Provenance

Chaque entrée possède un README dédié dont le nom encode explicitement le jalon et la
fonction. Ces README constituent la preuve documentaire primaire de niveau A. Les commits
et dates ne sont pas dupliqués dans le SQL de curation : ils sont récupérés depuis les
tables Git au moment de la reconstruction.

## Réconciliation Git conservatrice

Les anciens numéros `0xxx` ne sont pas des identités globales. Le builder conserve donc la
règle V3.1 : un numéro trouvé dans Git reste contextualisé par son commit.

Après import Git, V4.1.1 peut relier automatiquement un jalon curé dans deux cas :

1. il existe exactement un jalon canonique portant ce `milestone_id` et exactement un
   candidat Git `NUMERIC` portant le même label normalisé ;
2. plusieurs candidats portent ce label, mais exactement un d'entre eux a créé le fichier
   source dédié déclaré par la curation (`source_file`), avec une preuve `COMMIT_PATH` de
   confiance A.

Dans ce cas le candidat d'introduction devient `CURATED`, `linked_milestone_object_id` est
renseigné et la date/commit d'introduction du jalon sont complétés depuis ce candidat. Les
autres candidats homonymes restent dans le backlog. Si aucune source d'introduction ne
permet de lever l'ambiguïté (par exemple les deux générations de `0414`), aucune liaison
automatique n'est faite.

## Effet attendu sur les publications

Après reconstruction sur le dépôt complet :

- `milestones` passe de 139 à **157** entrées ;
- `Info/generated/jalons.md` contient les 18 jalons 0490 ;
- `Info/generated/jalons_par_nature.md` les classe par `INFRA`, `CODE`, `QUALIFICATION`,
  `PERF`, `FIX` et `DIAGNOSTIC` ;
- les candidats 0490 correspondants apparaissent dans la section « déjà reliés » de
  `audit_candidats_git.md` plutôt que dans le backlog non curé ;
- les paramètres et flags restent inchangés par cette curation.

## Validation

Le test V4.1.1 doit vérifier :

```text
published_milestones=157
published_params=314
published_flags=625
quick_check=ok
foreign_key_violations=0
```

Sur l'historique réel, `git_candidates_reconciled=18` est attendu pour cette série. Une
valeur inférieure à 18 mérite inspection avant curation de la série suivante.


## Correctif V4.1.1 — candidats documentaires secondaires

Le dépôt réel fait apparaître deux candidats `0490P` : le commit d’introduction du jalon
(`README_0490P_DEVICE_CELL_POLICY_ZERO_CPU.md`) et un commit ultérieur qui crée des
inventaires consolidés `*_0490p.csv`. Le second est une mention documentaire légitime,
mais ne doit ni créer un deuxième jalon ni bloquer la réconciliation.

V4.1.1 utilise donc le `source_file` de la curation comme preuve d’introduction : quand un
seul candidat a créé ce fichier avec une preuve `COMMIT_PATH` de confiance A, ce candidat
est relié au jalon canonique. Les autres candidats homonymes restent `CANDIDATE` comme
traces historiques non promues. Cette règle ne repose ni sur le score seul ni sur la date.

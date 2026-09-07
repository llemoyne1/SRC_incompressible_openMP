# Audit Git V3 — SRC_GPU-SURF

## But

La V3 enrichit la base avec l'histoire disponible dans **toutes les refs Git**, sans supposer que l'ascendance de `surf` contient à elle seule l'intégralité du développement.

Elle ne fusionne pas d'anciennes branches dans le code. Elle les utilise uniquement comme provenance documentaire.

## Données importées

Le builder enregistre :

- `git_commits` : auteur, dates, sujet, parents/merge ;
- `git_commit_files` : fichiers modifiés avec statut Git et renommages ;
- `git_tags` : tags légers/annotés et messages ;
- `git_refs` : branches locales, branches distantes et tags ;
- `git_commit_refs` : appartenance d'un commit aux branches ;
- `git_branch_audit` : synthèse d'une branche vis-à-vis de la mainline ;
- `git_branch_commit_status` : résultat `git cherry` pour chaque commit propre à une branche ;
- `git_commit_mainline_status` : synthèse globale du statut d'un commit ;
- `git_milestone_candidates` / `git_candidate_evidence` : mentions de jalons encore à curer.

## Audit inter-branches

Par défaut :

```bash
python3 Info/scripts/build_src_reference.py --mainline-ref origin/surf
```

Le builder applique l'équivalent de :

```bash
git rev-list origin/surf..origin/<branch>
git cherry -v origin/surf origin/<branch>
```

Les statuts de branche sont :

- `MAINLINE` : la branche de référence ;
- `ANCESTOR_OF_MAINLINE` : aucun commit hors de l'ascendance de `surf` ;
- `PATCH_EQUIVALENT_IN_MAINLINE` : commits hors arbre mais tous patch-équivalents ;
- `HAS_UNIQUE_PATCHES` : au moins un `git cherry +` ;
- `AUDIT_ERROR` : comparaison Git non exploitable.

## Candidats-jalons

### Labels `x...`

Ils sont considérés suffisamment spécifiques pour être regroupés automatiquement. Lorsqu'un jalon canonique existe déjà, le candidat est `LINKED`.

### Labels numériques

Les labels `0xxx` sont historiquement réutilisables. Ils ne sont donc **jamais** considérés comme identifiants globaux.

Un candidat numérique est ancré à son commit :

```text
candidate:numeric:0414:commit-<sha>
```

Deux usages différents de `0414` restent donc séparés jusqu'à une curation explicite.

## Exclusion récursive de `Info/`

Les modifications des fichiers `Info/` restent visibles dans `git_commit_files`, car elles appartiennent réellement à Git. En revanche, les chemins `Info/...` ne génèrent aucun candidat-jalon et un commit ne touchant que `Info/` ne conserve pas de candidat issu de son sujet. Cela évite que le système documentaire se transforme en source historique sur lui-même.

## Consultation

```bash
python3 Info/scripts/query_src_reference.py branches
python3 Info/scripts/query_src_reference.py branch origin/clean/von-karman-base
python3 Info/scripts/query_src_reference.py commit 17b290c6
python3 Info/scripts/query_src_reference.py candidate 0490A
python3 Info/scripts/query_src_reference.py candidate 0414
```

`candidate 0414` peut légitimement retourner plusieurs objets : c'est une propriété de sécurité de la base, pas un doublon à supprimer automatiquement.

## Promotion d'un candidat

La promotion vers `milestones` doit rester une curation versionnée sous `Info/curations/`. Une curation peut :

1. créer ou compléter le jalon canonique ;
2. relier les candidats/preuves correspondants ;
3. marquer les candidats `CURATED` ou `REJECTED` ;
4. conserver toutes les preuves Git originales.

Aucune promotion numérique n'est effectuée automatiquement par le builder.

## Raffinement V3.1 : introduction vs simple mention de chemin

Pour la famille numérique (`0175`, `0338`, `0414`, `0490A`, ...), le nom d'un fichier
ne constitue une preuve de création de jalon que lorsque le fichier est ajouté, ou
lorsqu'un rename/copy fait apparaître le label dans le nouveau nom. Les opérations
`M`, `D` et les déplacements qui conservent déjà le même label ne génèrent pas de
nouveau candidat. Elles restent enregistrées dans `git_commit_files` et pourront être
utilisées ultérieurement pour documenter l'évolution d'un jalon curaté.

Cette règle est volontairement asymétrique : il vaut mieux manquer un candidat faible
qui sera retrouvé par sujet/tag/README que créer plusieurs faux jalons à chaque mise à
jour d'un runner historique.

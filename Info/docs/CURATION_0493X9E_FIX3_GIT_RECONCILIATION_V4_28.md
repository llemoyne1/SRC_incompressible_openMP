# V4.28 — fermeture Git de `0493x9e-fix3`

## Objet

V4.28 ne crée aucun jalon et ne modifie aucune conclusion physique de V4.27.
Elle ferme uniquement la provenance Git du chemin Neumann multiphasique qualifié
`0493x9e-fix3` après son intégration dans la branche canonique `surf`.

L'ancre canonique est :

- commit : `6dfda0404c2066f3db378a5d27c30a6dcc898d39` ;
- sujet : `0493x9e-fix3: optimize multiphase Neumann outlet` ;
- tag : `surf-neumann-qualified-x9e-fix3-20260910`.

## Pourquoi deux candidats Git apparaissent

Le parseur Git extrait le label `x9e-fix3` du sujet du commit. Ce label correspond
exactement au jalon canonique et est donc lié automatiquement à
`milestone:0493x9e-fix3`.

Le nom du tag contient en revanche le token `x9e-fix3-20260910`. Le suffixe
`20260910` est la date de qualification portée par le nom du tag, pas une nouvelle
révision du solveur. Le candidat `candidate:x:x9e-fix3-20260910` doit donc être
réconcilié explicitement vers le même jalon.

Le builder V4.28 effectue cette réconciliation uniquement lorsque le **nom exact du
tag** pointe vers le **SHA exact** ci-dessus. La règle générique d'extraction des
jalons X n'est pas élargie.

## Effet attendu

Sur le dépôt `surf` validé en V4.27 :

- `milestones` reste à 292 ;
- `raw_params_inventory` reste à 854 ;
- `raw_env_inventory` reste à 549 ;
- `published_milestones` reste à 292 ;
- `published_flags` reste à 650 ;
- `curations_applied` passe de 27 à 28 ;
- `git_candidates_reconciled` passe de 52 à 53 ;
- le jalon `0493x9e-fix3` reçoit son `introduced_commit` et son tag officiels.

Aucun `Info/generated/*`, dump SQL, C++/CUDA ou runner n'appartient au patch source-only
V4.28 ; les publications sont régénérées localement après application.

# Curation V4.3 — jalon 0492 run_ok refresh

## Objet

Le jalon 0492 est une étape d'infrastructure et de qualification des runners publics
`run_ok_*`. L'historique Git expose un README explicite `README_0492_RUN_OK_REFRESH.md` :
la curation retient donc **un seul jalon canonique `0492`**.

Les suffixes observés dans le code, `0492a` et `0492b`, sont traités comme des
**sous-révisions techniques** et non comme des jalons autonomes :

- `0492a` apparaît dans la résolution/compatibilité du mode species-resident
  (`suite_species_resident_mode_0492a`) au sein de la base commune des runners ;
- `0492b` est le checker Python `check_injection_species_0492b.py`, utilisé par les deux
  scénarios d'injection pour vérifier l'état initial et le contrat multi-espèces à l'exécution.

Aucun jalon alphabétique intermédiaire n'est reconstruit artificiellement.

## Contrat retenu pour 0492

Le checker global `scripts/check_run_ok_0492.sh` vérifie notamment que :

- chaque `run_ok_*.sh` source l'unique base `scripts/src_mpcd_run_ok_common.sh` ;
- les runners ne chaînent pas vers d'autres runners shell ;
- le binaire CUDA résident 0486 attendu est exposé par défaut ;
- `PREFLIGHT_ONLY` est disponible ;
- le fichier LiveVis racine existe et porte le contrat de champs/filtrage attendu ;
- les paramètres physiques visibles des cas surface libre restent explicitement exposés ;
- la microphysique de référence (gamma, dt, kBT, angle de rotation) est homogène ;
- la chaîne species-resampling peut résoudre le mode résident de production ou de validation.

Le checker `0492b` complète cette validation sur les injections : il lit l'état binaire,
contrôle les populations/roles par type, vérifie les diagnostics runtime par espèce et,
si demandé, la présence de cellules mixtes dans les sorties cellule–espèce.

## Relations historiques

`0492` est documenté comme une consolidation des acquis de :

- `0490P`, qui finalise la politique cellule multi-espèces côté device sans décision CPU ;
- `0491H-fix1`, qui clôt la qualification approfondie du Q6 sensible aux espèces.

Le refresh ne modifie donc pas le statut de ces jalons : il les rend exploitables dans une
suite `run_ok` homogène, inspectable et reproductible.

## Réconciliation Git

La source primaire de la curation est `README_0492_RUN_OK_REFRESH.md`. Après import Git,
le builder lie le jalon canonique au candidat qui a introduit ce fichier. Les éventuelles
mentions `0492a` ou `0492b` restent dans l'audit Git comme traces de sous-révisions et ne
créent pas de jalon publié supplémentaire.

# V4.27 — réintégration Neumann multiphasique et optimisation x9e-fix3

## Objet

V4.27 met la base documentaire en accord avec le nouveau `surf` après cherry-pick de la
lignée autonome développée dans `SRC_GPU-SURF-x8q-ablation`. La correction de périmètre
V4.25 était valide lorsqu'elle a été faite : le code n'était alors pas dans `surf`. Elle
reste donc documentée comme événement historique, mais son exclusion n'est plus la
frontière courante.

V4.27 restaure **sans réécriture** les curations V4.22/V4.23 et leurs preuves primaires,
puis documente la suite x9e jusqu'au cleanup production de `x9e-fix3`.

## Chaîne restaurée V4.22/V4.23

Les dix jalons réintroduits sont :

`x8r-neumann-species → x8v → x8w → x8x → x8y → x8z → x9a-neumann → x9b-neumann → x9c-outlet → x9d-fix1-neumann`.

Les suffixes `-neumann` / `-outlet` restent indispensables car `x8r`, `x9a`, `x9b`,
`x9c` et `x9d` possèdent déjà des identités historiques dans d'autres cycles.

La conclusion physique reste celle de V4.22 : `x9c-outlet` est un correctif ciblé de
support de phase pour l'outlet de l'atomiseur, pas une qualification universelle de toute
condition de Neumann multiphasique. V4.23 reste également conservatrice : son triplet
B/O/B supporte une non-régression physique courte de `x9d-fix1-neumann`, mais ne qualifie
pas son gain de performance.

## x9e-neumann — recyclage résident

`x9e-neumann` conserve explicitement `physics=x9c_unchanged`. Il ajoute au workspace
`x9d-fix1-neumann` un buffer persistant des slots fluides supprimés pendant le pas et
construit le pool d'insertion sous la forme :

```text
[ slots supprimés pendant le pas | tail inactif compact ]
```

Les candidats Neumann et leurs comptages restent exacts. Le runner unifié expose trois
profils `x9c`, `x9d-fix1` et `x9e`, ce dernier étant le candidat optimisé par défaut.

## x9e-fix1 — correction de compilation

Le label est conservé dans le lexique car il est explicitement attesté. Il répare
uniquement un littéral de chaîne C/C++ coupé par un retour à la ligne dans le banner x9e.
Aucune physique ni logique de performance n'est modifiée.

## x9e-fix2 puis x9e-fix2b

`x9e-fix2` tente de supprimer du chemin normal le scan `role[0:oldActive]` en prouvant la
compacité du préfixe par un invariant comptable strict. Un oracle full-prefix peut être
réactivé pour qualifier cette preuve et `0315c` reste le fallback exact.

`x9e-fix2b` remplace ensuite l'hypothèse de réservoir dense par une vérification
`O(deletedCount)` des seuls slots effectivement supprimés. Cette amélioration reste
insuffisante pour les pas dont la population varie : le diagnostic de premier fallback
observe dès le pas 1 un bilan légitime de `1055` suppressions pour `994` insertions,
soit `netDelta=-61` et `expectedActive=639939` pour `oldActive=640000`.

## x9e-fix3 — réparation exacte ciblée

`x9e-fix3` abandonne l'idée de « ne rien réparer si le pas est équilibré » et remplace la
réparation globale normale par une réparation exacte restreinte au support qui peut avoir
été modifié :

1. les trous de l'ancien préfixe viennent de `deletedIndices` ;
2. les éventuels trous de croissance sont inclus jusqu'à `expectedActive` ;
3. les donneurs possibles sont bornés par le tail effectivement touché par le pool ;
4. le plus petit trou est apparié au plus grand donneur actif, conformément à l'ordre de
   la réparation exacte `0315c` ;
5. le support modifié est vérifié exactement ;
6. toute incohérence de bornes, de comptage ou de coût retombe sur `0315c`.

Le cleanup production retire ensuite l'oracle full-prefix et la télémétrie de chantier,
mais conserve la validation exacte locale, le work-cap et le fallback `0315c`.

## Qualification et portée

Le package de cleanup indique que l'algorithme ciblé pré-cleanup a déjà passé **3000 pas**.
Après cleanup et intégration dans `surf`, le smoke fourni par l'utilisateur termine
**250/250** en 400×400 avec :

```text
prefixRepair=targeted_deleted_list_exact fallback=0315c_exact
step=250/250 ... wall=20.1s
[src_mpcd_base] done
```

Aucun marker de fallback x9e n'est observé dans ce smoke. Cette preuve qualifie le chemin
d'implémentation et sa non-régression sur le cas d'atomiseur utilisé ; elle n'élargit pas
la portée physique de `x9c-outlet` à toutes les topologies Neumann.

## Provenance

`Info/inputs/historical/0493x9e_neumann_optimization_original_sources.zip` conserve
byte-for-byte les packages x9e, fix1, runner unifié, fix2, fix2b, diagnostic first-fallback,
fix3 ciblé et cleanup production, accompagnés d'un manifeste SHA-256. Les README sont en
plus extraits byte-for-byte sous `Info/inputs/historical/` pour consultation et indexation.

Le fichier `0493x9e_fix3_surf_cleanup_smoke_20260910.txt` est explicitement une
**transcription curée** des lignes terminales fournies, et non un faux log original.

## Mise à jour de l’inventaire des flags

Le snapshot x14ai du 4 septembre est conservé intact comme provenance. V4.27 crée un nouvel
inventaire actif `src_mpcd_env_flags_inventory_snapshot_100926_x9e_fix3.csv`, obtenu à partir
des 524 entrées antérieures plus **25 contrôles Neumann** introduits ou explicitement
historicisés par la lignée x8q→x9e-fix3. Il contient les gates backend, le work-cap x9e-fix3
et les alias `NEUMANN_PROFILE`, `NEUMANN_VIRTUAL_LAYERS`, `NEUMANN_COARSE_LAYERS` et
`NEUMANN_TARGET_OCCUPANCY`. Le flag d’oracle fix2 est conservé avec le statut « historique,
supprimé du binaire par cleanup x9e-fix3 ». Aucun nouveau paramètre `.kv` n’est introduit
par cette chaîne, donc l’inventaire des paramètres reste inchangé.

## Effet sur le canon

À partir de V4.26 (277 jalons), la restauration V4.22/V4.23 remet 10 jalons et V4.27 en
ajoute 5 (`x9e-neumann`, `x9e-fix1`, `x9e-fix2`, `x9e-fix2b`, `x9e-fix3`) : le total
canonique attendu devient **292 jalons**. L’inventaire ENV actif passe de 524 à **549** lignes;
le nombre de paramètres bruts reste 854. Le lexique les publie automatiquement dans l’ordre
naturel et `flags.md` est régénéré depuis le nouvel inventaire.

Aucun fichier C++/CUDA, runner solveur ni `livevis_control.kv` n'est modifié par le patch
documentaire V4.27.

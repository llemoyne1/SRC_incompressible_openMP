# V4.29 — rafraîchissement des inventaires et des listes de consultation

## Objet

V4.29 est une évolution **de publication et d'inventaire uniquement**. Elle ne crée aucun
jalon, ne change aucune relation physique et ne modifie aucun code solveur. Son objectif est
de synchroniser les vues humaines avec l'état `surf` V4.28 après réintégration et qualification
de la lignée Neumann x9e-fix3.

## Inventaire des paramètres

Un snapshot courant est publié sous :

`Info/inputs/snapshots/src_mpcd_params_inventory_snapshot_100926_x9e_fix3.csv`

Il est byte-for-byte identique au snapshot du 4 septembre (`SHA-256`
`1c172b2ca7b4f02047150b9e54bb096385afe21e9c4990c65094fc33361b710c`). Cette identité est
volontaire : l'intégration x8q→x9e-fix3 n'introduit **aucune nouvelle clé de paramètre `.kv`**.
Le décompte brut reste donc `raw_params_inventory=854` et la publication normalisée reste
`314` paramètres canoniques. Le nouveau nom de snapshot atteste simplement que cette absence
de changement a été réauditée au 10 septembre 2026.

## Inventaire des flags / variables de runner

Le snapshot actif reste :

`Info/inputs/snapshots/src_mpcd_env_flags_inventory_snapshot_100926_x9e_fix3.csv`

Il contient `549` entrées brutes, soit `25` de plus que le snapshot x14ai du 4 septembre.
La publication normalisée produit `650` symboles ENV. Ces ajouts couvrent les contrôles de la
chaîne Neumann multiphasique et de ses profils x9c/x9d-fix1/x9e.

## Listes générées de consultation

Après `build_src_reference.py`, les trois documents à consulter sont :

- `Info/generated/parametres.md` — paramètres canoniques, tri alphabétique naturel ;
- `Info/generated/flags.md` — flags/variables runner, tri alphabétique naturel ;
- `Info/generated/jalons_par_nature.md` — jalons regroupés par nature et triés naturellement
  à l'intérieur de chaque groupe.

Pour retrouver directement un identifiant (`x10e`, `x14ai`, etc.),
`Info/generated/lexique_jalons.md` reste la vue globale la plus rapide, avec tri naturel sur les
`292` jalons canoniques.

## Invariants attendus

V4.29 ne change pas les volumes de connaissance de V4.28 : `292` jalons, `854` lignes
paramètres brutes, `549` lignes ENV brutes, `314` paramètres publiés et `650` flags publiés.
Seul `reference_version` passe à `V4.29`.

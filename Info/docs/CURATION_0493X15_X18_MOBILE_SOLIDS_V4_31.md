# V4.31 — curation x15 → x18d : solides matériels mobiles et FSI

## Objet

Cette curation met `Info/` au niveau de la section **Solides mobiles** du rapport projet au
15 septembre 2026. Elle couvre la chaîne de décision complète : diagnostic du `chi-solid`
volumique, tentatives de remapping, première frontière cinétique Eulerienne, passage à une
frontière lagrangienne persistante, couplage mécanique membrane/volet et nettoyage x18d.

Le principe canonique est désormais :

```text
milieu poreux / optimisation : chi -> Darcy/Brinkman
solide matériel imperméable  : chi0 -> Gamma0={chi=0.5} -> mesh lagrangien persistant
                               -> crossing particule/segment mobile -> réaction mécanique
```

Le chemin Darcy historique n'est pas réinterprété silencieusement. Pour un solide matériel,
`Gamma(t)` devient l'autorité géométrique après initialisation.

## Jalons ajoutés

V4.31 ajoute **31 jalons** explicitement attestés :

- x15 : `x15a`, `x15b`, `x15c`, `x15e`, `x15f` ;
- x16 dynamique/remapping : `x16a` à `x16i` hors labels non attestés ;
- x16 frontière cinétique : `x16j` à `x16q` ;
- x17 : `x17a`, `x17b`, `x17c`, `x17d`, `x17d-fix2` ;
- x18 : `x18a`, `x18a-fix2`, `x18b`, `x18d`.

Absences intentionnelles : `x18c` est une proposition fast-path spécialisée rejetée et n'est pas
canonique; `x18a-fix1` est un simple câblage de runner; les réglages membrane x17d-fix3..fix8
restent des preuves de campagne sous x17d et non des jalons scientifiques autonomes.

## Résultats de référence

- x16a : conservation/action-réaction au voisinage du roundoff sur `rigid_slab_1d`.
- x16d--x16i : le déplacement/remapping de `chi` crée des événements de capture et ne restaure pas
  une invariance galiléenne satisfaisante; direction abandonnée comme principe final.
- x17b : **PASS 6/6**, zéro pénétration stricte, persistance du mesh, fermeture action-réaction/charge
  et contrôle galiléen; c'est la référence d'imperméabilité matérielle.
- x17c/x17d : le transfert FSI nodal fonctionne, mais le modèle structurel minimal n'est pas retenu
  comme solveur de solide détaillé.
- x18a/x18b : volet rigide 1-DOF utilisant directement les impacts x17a; audits observés sans
  pénétration sur les fenêtres documentées.
- x18d : diagnostics lourds de qualification opt-in. **Mise à jour V4.31-fix1** : application réelle,
  compilation CUDA locale et runs du volet réussis; statut `VALIDATED/FUNCTIONAL`. Le gain de
  performance chiffré reste à benchmarker.

## Inventaires

Le snapshot paramètres actif devient `src_mpcd_params_inventory_snapshot_150926_x18d.csv` et ajoute 20 clés canoniques
liées au solide matériel/mobile. Le snapshot ENV actif devient `src_mpcd_env_flags_inventory_snapshot_150926_x18d.csv` et ajoute
41 contrôles de runners absents de V4.30.

Le paramètre de politique x18d est :

```text
chiSolidQualificationDiagnosticsEnable = false
```

`false` est le chemin normal; `true` réactive les diagnostics de qualification historiques.

## Provenance

Narratif : `Info/inputs/historical/README_0493X15_X18_MOBILE_SOLIDS_20260915.md`.

Archive : `Info/inputs/historical/0493x15_x18_mobile_solids_20260912_15_original_sources.zip`.

SHA-256 : `c1d55589bf7ca21257411b4585290ec3e66d0fe1fc6e9db5daa9c89e7be0b7b7`.

Le rapport consolidé TeX/PDF et les packages/summaries sélectionnés sont inclus dans l'archive avec
un manifest SHA-256 interne.

## Validation attendue

Le patch V4.31 est **source-only** : pas de `Info/generated/*`, pas de base SQLite/dump, pas de
modification de `src/`, `include/`, `scripts/` racine ni `livevis_control.kv`.

Après application :

```bash
python3 -m py_compile \
  Info/scripts/build_src_reference.py \
  Info/scripts/publish_src_reference.py \
  Info/scripts/query_src_reference.py

python3 Info/scripts/build_src_reference.py --mainline-ref origin/surf
python3 Info/scripts/query_src_reference.py doctor
python3 Info/scripts/query_src_reference.py stats

python3 Info/scripts/query_src_reference.py milestone x17a
python3 Info/scripts/query_src_reference.py milestone x17b
python3 Info/scripts/query_src_reference.py milestone x18a
python3 Info/scripts/query_src_reference.py milestone x18d
python3 Info/scripts/query_src_reference.py param chiKineticBoundaryMode
python3 Info/scripts/query_src_reference.py param chiSolidQualificationDiagnosticsEnable
python3 Info/scripts/query_src_reference.py param chiSolidHingedAngularDamping
```


## Addendum V4.31-fix1

Les requêtes discriminantes ont montré que les métadonnées de provenance des paramètres étaient
trop larges. Elles sont corrigées dans le snapshot actif et la validation locale x18d du 15/09/2026
est enregistrée dans `CURATION_0493X15_X18_MOBILE_SOLIDS_V4_31_FIX1.md`.

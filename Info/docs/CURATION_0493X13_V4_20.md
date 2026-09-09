# Curation x13 — V4.20

V4.20 ferme le cycle x13 jusqu’à **x13zd**, c’est-à-dire du calibrage constitutif du fluide SRC jusqu’à la validation croisée qui invalide les fermetures expérimentales Taylor–Culick et motive le rollback au tag `surf-tension-qualified-x13h-20260831`. Aucun C++/CUDA, runner solveur ou `livevis_control.kv` n’est modifié.

## 1. Transport et fluide de référence

`x13a→x13h` est reclassé comme une chaîne de **calibration/qualification scripts-only**, pas comme des évolutions du solveur. `x13g` est une qualification de reproductibilité statistique GPU; `x13h-A/B/C` qualifient acoustique, viscosité/densité et domaine Mach, puis `x13h` consolide le point gamma=8, angle=120°, lambda/h=0.72.

`x13i` est ajouté comme calibrateur de loi d’échelle en kBT. `x13j` est conservé comme **une seule identité globale malgré un double usage historique attesté** : calibrateur SRC autonome et qualification Young–Laplace du point x13h. Créer deux x13j aurait inventé une nomenclature absente des sources.

Le commit `7655b81...` n’est pas réinterprété comme introduction de x13h : il constitue la preuve A de la chaîne surface-libre officiellement qualifiée et le point de rollback.

## 2. Qualification dynamique et défaut Taylor–Culick

`x13k/l/m` sont des qualifications dynamiques n=2/3/4. `x13n` reste un benchmark : la fréquence de goutte est bonne mais la rétraction Taylor–Culick est trop lente malgré une traction capillaire locale cohérente. `x13o` est l’ablation normal-only de x10v, OFF dans la chaîne qualifiée.

## 3. Branche expérimentale d’invalidation

V4.20 individualise les jalons que l’ancien référentiel agrégeait ou omettait :

- `x13p` zone de crossing libre;
- `x13q` turnover des orphelins;
- `x13r` refroidissement direct des cellules interfaciales;
- `x13s` refroidissement anisotrope;
- `x13u` combinaison x13t+x10u;
- `x13v` séparation relocalisation/swap;
- `x13za`, `x13zb`, `x13zb2`, `x13zb3`, `x13zc` pour la séquence d’audit de grille et de baseline.

Les agrégats `x13r/x13s`, `x13u/x13v` et `x13za-x13zc` sont supprimés. `x13t`, `x13w`, `x13w-fix3`, `x13x`, `x13z` et `x13zd` sont consolidés. Les candidats Git `x13tw` et `x13t-x13x-experimental-before-rollback-20260831` restent volontairement agrégés/non canoniques.

## 4. Fin causale x13zd

`x13zd` est la frontière de V4.20 : la fermeture x13t+x13w-fix3, favorable à Taylor–Culick, échoue sur gouttes oscillantes fermées et contracte artificiellement le support. Le dépôt revient donc à `7655b81`, tag x13h qualifié. Les `x13ze+` sont post-rollback/run_ok et sont reportés avec le bloc x14.

## Provenance

Les sources courantes x13a-n, l’audit du commit 7655b81, le rapport technique final x13, le référentiel historique et des logs x13p sont archivés sous `Info/inputs/historical/`; leurs octets exacts sont conservés dans `0493x13a_x13zd_original_sources.zip` avec manifeste SHA-256. Les copies lisibles placées directement dans `Info/inputs/historical/` peuvent uniquement supprimer des espaces horizontaux terminaux afin de satisfaire `git diff --check`; le ZIP et son manifeste restent l’autorité byte-for-byte. Pour les expériences rollbackées x13q-r-s-u-v-z*, les noms de README/patchers/runners sont en outre attestés par l’audit Git multi-ref du commit d’archive `3dafac...`; celui-ci est enregistré comme preuve et non comme commit d’introduction.

# Curation x13ze+ et x14 liquide/gaz — V4.21

V4.21 poursuit directement V4.20. Elle ne rouvre pas la qualification x13a→x13zd : `x13zd` reste la validation croisée qui invalide x13t+x13w comme fermeture générale, et le point de production surface libre reste le commit `7655b81b1b2fd16eecefa8d8b3bebac4cd9f87f1`, tag `surf-tension-qualified-x13h-20260831`.

Cette curation est strictement documentaire. Elle ne modifie aucun C++/CUDA, runner solveur ni `livevis_control.kv`.

## 1. Frontière post-rollback x13ze+

Le commit d'archive `a18d274ba28d0a8ce14432fdc5fa52a132b5410f` atteste sept identités postérieures au rollback : `x13ze`, `x13zf`, `x13zg`, `x13zj`, `x13zk`, `x13zl` et `x13zn`.

- `x13ze` fige les démonstrations `run_ok` impact/puddle sur la chaîne surface libre qualifiée `x10o+CIC+Q2+x10p/q+x10u+x10v full-vector swap+x12a` ;
- `x13zf` est une démonstration qualitative dripping, explicitement non calibrée comme benchmark de robinet ou de Weber critique ;
- `x13zg` est la bibliothèque de profil surface libre commune aux démonstrations `run_ok` ;
- `x13zj`, `x13zk`, `x13zl` et `x13zn` sont des jalons d'harmonisation/checker/collection/cleanup `run_ok`, attestés par leurs README dans le commit d'archive.

Aucun `x13zh`, `x13zi` ou `x13zm` n'est créé : l'absence de ces lettres dans la séquence ne constitue pas une preuve d'existence.

Les trois scripts x13ze/zf/zg présents dans le snapshot sont copiés lisiblement sous `Info/inputs/historical/` et leurs octets originaux sont figés dans le ZIP de provenance. Les quatre README x13zj/zk/zl/zn, absents du snapshot fourni, sont référencés par couple immutable `commit+path`; ils ne sont pas reconstruits à partir d'une transcription, afin de respecter le contrat byte-for-byte.

## 2. Thermostat par espèce : x14a→x14i sans jalon inventé

L'ancien référentiel contenait un agrégat `x14a-x14j` en plus de quelques identités individuelles. V4.21 supprime cet agrégat et individualise uniquement les jalons attestés par le commit `c3107ec1e486ce1c5b9829c4a7a2473c16438908` :

- `x14a`, smoke deux types ;
- `x14b`, qualification dynamique avec collision SRC active sur grille exacte ;
- `x14c`, probe production-like avec grid shift ;
- `x14d`, implémentation du thermostat résident séparé par espèce sur collision SRC commune ;
- `x14e`, qualification du chemin SRC de production ;
- `x14f`, qualification exacte du chemin `src-q6-g-f` ;
- `x14g`, bridge des cell IDs exacts post-stream/grid-shift ;
- `x14i`, qualification finale `src-q6-g-f` avec grid shift actif.

`x14d` et `x14g` étaient déjà canoniques : ils sont enrichis par leur commit/date d'introduction et par les marqueurs source directs. **Aucun x14h n'est créé**, faute de preuve autonome.

## 3. Construction de la fermeture liquide/gaz x14j→x14ai-fix1

Les jalons déjà présents dans V4.20 sont conservés mais réconciliés avec leurs commits d'introduction :

- `20a5920...` : x14j→x14s, avec la géométrie bilatérale, la réflexion spéculaire gazeuse et la séquence diagnostic `x14p→x14q→x14r→x14s` sur le volume gazeux accessible ;
- `5dd3461...` : x14t→x14w, pression thermodynamique, impact normal, kick cinétique excédentaire et Couette biphasique ;
- `8a4fc40...` : x14x→x14ai-fix1, ablations de traction, diagnostic du bilan global, traînée et fermeture de résultante Q6 réellement appliquée.

V4.21 ajoute explicitement `x14p` et `x14q`, dont les analyseurs déclarent eux-mêmes une portée **offline diagnostic only**. La loi accessible-volume active reste x14s; x14p/q ne sont pas rétroactivement présentés comme des implémentations CUDA.

Le statut physique demeure borné par les preuves du rapport x14 du 7 septembre : x14l qualifie l'imperméabilité normale du gaz, x14s la pression thermodynamique corrigée par volume accessible, x14v le transfert cinétique normal excédentaire, x14ad la distribution locale de traction et x14ai-fix1 la seule résultante globale sur une composante liquide fermée et isolée des frontières Q6 externes. Le Couette x14w reste `PASS-like` pour la transmission tangentielle, sans création d'un terme de frottement ad hoc.

## 4. Bloc application-scale x14an→x14as

Le commit `75ea8907aa7d2d9f6a3e1d3d639a48e850ee0672` atteste une séquence de runners `x14an→x14as` menant à la comparaison externe :

- `x14an` : jet gazeux plan sur bain liquide ;
- `x14ao` : insertion d'une buse finie via le chemin Darcy/chi déjà qualifié ;
- `x14ap` : défauts de similitude expérimentale ;
- `x14aq` : variante avec réservoirs ambiants latéraux ;
- `x14ar` : variante d'atmosphère hard-density ;
- `x14as` : topologie à sorties larges, avec pression gazeuse mesurée comme covariable génératrice.

Ces runners prouvent l'identité et l'intention des jalons, mais pas un résultat PASS autonome. V4.21 les classe donc comme **campagne/construction**, sans transformer une intention de qualification en validation acquise.

## 5. x14at : validation externe ciblée, pas validation globale

La campagne Sato Stage-A fournit une preuve quantitative exploitable mais étroite. À `H/D=0.8`, les deux cas les plus discriminants donnent :

| Fr'_m mesuré | h/D SRC | h/D Sato | écart |
| ---: | ---: | ---: | ---: |
| 0.4880 | 0.6039 | 0.6344 | -4.8 % |
| 0.5859 | 0.6861 | 0.7616 | -9.9 % |

Ces écarts sont inférieurs à la dispersion expérimentale rapportée dans le document de comparaison. En revanche, la série `H/D=1.7` reste `REVIEW` parce que le runner ne conserve pas une géométrie de lance homologue : la longueur de buse change avec la hauteur. La simulation reste en outre une similitude partielle géométrie/`Bo_D`/`Fr'_m`, pas une similitude eau-air complète en Reynolds, Ohnesorge et rapport de densités.

Le statut canonique de x14at est donc **validation externe ciblée de l'ordre de grandeur de la réponse normale intégrée**, et non PASS général de l'interaction liquide/gaz.

## 6. x14au : le calibrateur de viscosité ne ferme pas la réserve constitutive

Le rapport x14au donne :

- liquide `src-q6-g-f`, échelle primaire : `INVALID`, `nu=0.0012771422`, `CV=27.85 %` ;
- liquide à l'échelle application : `REVIEW`, `CV=11.91 %` ;
- gaz SRC, échelle primaire : `REVIEW`, `CV=7.91 %` ;
- gaz à l'échelle application : `REVIEW`, `CV=14.45 %`.

La cohérence entre échelles est compatible à 2 sigma, mais elle est seulement diagnostique. V4.21 interdit donc de transformer x14au en qualification constitutive réussie.

## 7. x14av : démonstration atomiseur, non qualification d'atomisation

Le runner et l'analyseur x14av déclarent explicitement `DEMONSTRATION_DIAGNOSTIC_ONLY`. Les métriques de pénétration, largeur aval et composants détachés servent à observer la capacité de la chaîne, sans critère physique PASS/FAIL d'atomisation.

Le snapshot contient aussi un `run_ok_air_assisted_atomizer.sh` plus récent utilisant la géométrie multi-axe 0414. Cette variante est enregistrée comme preuve du **même x14av** ; aucune identité `x14av-0414` n'est inventée faute de jalon autonome attesté.

## 8. Provenance et invariants de publication

`Info/inputs/historical/0493x13ze_x14av_original_sources.zip` contient les fichiers source/runner/analyseur du snapshot pertinents et les trois rapports externes matérialisés. Chaque entrée est écrite à partir des octets originaux sans transformation ; `MANIFEST_SHA256.tsv` donne taille et SHA-256 par entrée. Le SHA-256 du ZIP est fourni à côté.

Les copies lisibles ajoutées hors ZIP sont conservées exactes tant que `git diff --check` le permet; seule une normalisation de whitespace/line endings serait autorisée si nécessaire. Le ZIP reste l'autorité byte-for-byte.

Le patch V4.21 est **source-only** : il ne contient ni `Info/db/src_reference_dump.sql`, ni `Info/db/src_reference.sqlite*`, ni `Info/generated/*`. Après application, ces produits sont régénérés localement par `Info/scripts/build_src_reference.py` sur un checkout disposant de l'historique Git complet.

La cible canonique est de 277 jalons et 22 curations. Les inventaires physiques ne changent pas : 314 paramètres publiés et 625 flags publiés. Le nombre de commits/références/candidats Git reste celui de V4.20 lorsqu'on reconstruit sur le même dépôt historique; l'ajout d'identités X réconcilie leurs candidats exacts sans modifier la métrique `git_candidates_reconciled`, qui concerne les candidats numériques historiques.

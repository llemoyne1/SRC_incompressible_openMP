# V4.24 — réconciliation Git du jalon 0414 segmented x/y

## Objet

Le jalon `20260907-0414-segmented-xy` existe depuis la migration initiale de la base.
Il représente l'extension qualifiée des open boundaries segmentées aux axes x et y sur
le chemin CUDA résident `src-q6-g-f`.

V4.24 **ne crée aucun nouveau jalon physique**. Elle ferme uniquement l'ambiguïté Git
restante autour du label numérique `0414`, qui est historiquement réutilisé dans le dépôt.

## Preuve Git de `surf`

Le commit :

`e2fe1ca29042c2391cd5b6ee7f9eb7fe9a2065a8`

porte le sujet :

`0414: generalize segmented open boundaries to x/y on CUDA resident path`

et ajoute notamment `scripts/run_0414_segmented_xy_neumann_qualification.sh`.
Cette combinaison identifie sans ambiguïté le candidat numérique courant avec le jalon
namespacé `20260907-0414-segmented-xy`; les anciens usages numériques de `0414` restent
séparés et ne sont pas reclassés.

## Qualification déjà portée par le jalon

La documentation `docs/qualification_0414_segmented_xy.md` qualifie sept topologies
(`right`, `top`, `left`, `bottom`, `left_top`, `right_top`, `left_partial_top`) sur le CG
coopératif CUDA résident x7j, avec fermeture de bookkeeping particulaire et tests de
covariance d'orientation. Le benchmark `right_top` à 800 pas mesure aussi la réduction
de conditionnement apportée par x8s dans des conditions propres (LiveVis et recording OFF).

La limite connue reste inchangée : l'extension analytique x8s n'est pas appliquée aux
outlets partiels non séparables; la physique reste résolue sur le chemin CUDA résident,
avec un conditionnement plus défavorable.

## Portée de V4.24

V4.24 renseigne `introduced_commit`. Après l'import Git, le builder applique une exception
exacte sur le triplet `(0414, e2fe1ca, 20260907-0414-segmented-xy)` : seul ce candidat est
marqué `CURATED`, puis la relation `EVIDENCED_BY_COMMIT` et la preuve `GIT_COMMIT` sont
ajoutées. La règle générique reste conservatrice et les anciens candidats numériques
`0414` ne sont pas modifiés. Aucun solveur, runner ou paramètre n'est touché.

Ce patch reste strictement **source-only** : aucune base SQLite, aucun dump SQL et aucun
`Info/generated/*` n'est livré.

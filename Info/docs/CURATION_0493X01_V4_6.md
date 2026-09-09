# Curation V4.6 — 0493x0 / 0493x1

## Objet

Cette curation ferme la transition entre le cycle `0493w` et la série `0493x`.
Le référentiel consolidé d'origine contenait `0493x1` uniquement comme placeholder de
confiance C et ne contenait pas `0493x0`. L'historique Git et les README dédiés permettent
désormais de reconstruire les deux jalons sans extrapolation.

## 0493x0 — démonstration dam-break bi-espèces

`0493x0` est une démonstration d'intégration/visualisation du Q6 multi-espèces
`independent_masked` : liquide projeté (`q6Strength=1`), gaz compressible non projeté
(`q6Strength=0`), colonne liquide libérée par gravité. Le README précise explicitement
qu'il ne s'agit pas d'un benchmark surface libre calibré.

La première variante utilisait un petit couple inlet/outlet gazeux en haut de la cuve pour
sélectionner une topologie segmented déjà qualifiée. Cette solution introduisait toutefois
une injection continue de gaz et un panache artificiel; elle est remplacée dans le même
checkpoint historique par le chemin closed-box de `x1`.

## 0493x1 — closed-box CUDA résident

`0493x1` étend le chemin CUDA résident à une boîte statique non périodique sur quatre faces.
Le premier sous-ensemble qualifié est volontairement étroit : faces `solid` ou `specular`,
aucun segment ouvert, pas de bounceback, pas d'obstacle immergé, pas de domaine mobile et
pas de resampling dans la qualification dam-break.

Le chemin résident enchaîne streaming/réflexion quatre faces, collision SRC persistante,
Q6 `independent_masked` lorsque demandé, puis thermostat résident. Le Q6 annonce
`boundaryFamily=closed_box`; le smoke `src/src-q6` exige conservation exacte des populations
et masses par espèce, absence totale de compteurs inlet/outlet et absence de fallback CPU.

## Politique de curation

- `x0` est créé comme jalon canonique, confiance A.
- `x1` n'est pas dupliqué : son placeholder existant est remplacé par la définition historique
  attestée, confiance A.
- `x2` n'est pas modifié dans cette curation; il reste la frontière du bloc suivant.
- Les deux jalons étant de famille globale `X`, leur provenance Git se lie automatiquement au
  build lorsque les candidats correspondants sont présents.

## Effet attendu

La V4.5.1 publie 195 jalons. V4.6 en ajoute exactement un (`x0`) et enrichit `x1` :

```text
published_milestones=196
curations_applied=7
quick_check=ok
foreign_key_violations=0
publication_missing_docs=0
```

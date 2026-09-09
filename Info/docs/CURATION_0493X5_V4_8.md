# Curation V4.8 — 0493x5a / x5a2 / x5b : première séquence surface libre

## Objet

Cette curation consolide trois jalons déjà présents dans le référentiel initial. Elle
n'ajoute aucun jalon canonique : elle remplace les descriptions rétrospectives par le
rôle attesté des README, runners et diagnostics survivants.

## Chaîne retenue

| Jalon | Nature | Rôle historique |
|---|---|---|
| x5a | CODE | introduit `free_surface_masked` sur un liquide partiellement rempli, avec support absolu liquide et pression de jauge nulle sur face active/inactive |
| x5a2 | QUALIFICATION | applique l'opérateur x5a inchangé à un dam-break liquide-vide dynamique et révèle la limite support numérique / interface physique |
| x5b | QUALIFICATION | première qualification liquide-gaz : liquide projeté, gaz explicite compressible `q6Strength=0`, couplage par collisions SRC |

## Interprétation

x5a constitue le premier passage de Q6-g d'un liquide plein vers un domaine liquide
partiellement occupé. Le support de pression est déterminé par le remplissage absolu
`mass/referenceCellMass`; le bord de ce support est encore traité comme une interface à
pression de jauge nulle placée à une demi-maille.

x5a2 ne modifie pas l'opérateur. Son dam-break liquide-vide est précisément un test
discriminant : le comportement pré-impact est robuste, mais la fragmentation après impact
montre que le bord du support particulaire ne peut pas servir de géométrie d'interface
physique générale. Cette observation prépare directement les jalons x6 de reconstruction
de phase/interface.

x5b ajoute ensuite un gaz explicite sans rendre ce gaz incompressible. Le gaz reçoit la
force volumique et participe aux collisions multi-espèces, mais sa force Q6 déclarée est
nulle et aucune correction Q6 directe ne lui est appliquée. À ce stade, sa pression n'est
pas encore utilisée comme valeur Dirichlet du problème elliptique liquide : le couplage de
pression sera traité dans la séquence x6.

## Classification de x5b

Le référentiel initial classait x5b comme `CODE`. Le README dédié précise toutefois que
le jalon « deliberately does not change the CUDA operator » et qu'il ajoute la première
qualification dynamique bi-espèces. V4.8 le classe donc `QUALIFICATION`, sans diminuer
son importance architecturale comme première étape avec gaz compressible explicite.

## Provenance primaire

- `README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md` ;
- `README_0493X5A2_DYNAMIC_FREE_SURFACE_DAM_BREAK.md` ;
- `README_0493X5B_LIQUID_GAS_FREE_SURFACE.md`.

La famille X reste liée par le mécanisme global de candidats Git. V4.8 étend la grammaire
X aux suffixes historiques `lettres+chiffres` tels que `x5a2` et `x6f2`, tout en conservant
la désambiguïsation V4.6.1 des labels purement numériques (`x0`, `x1`, ...). Cette curation
n'impose aucun SHA et ne modifie pas le solveur.

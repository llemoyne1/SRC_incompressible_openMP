# Curation V4.7 — 0493x2 à 0493x4b : naissance du séquençage Q6-g

## Objet

Cette curation consolide quatre jalons déjà présents dans le référentiel initial. Elle
n'ajoute aucun jalon : elle remplace les descriptions rétrospectives courtes par la chaîne
causale attestée par les runners, les README dédiés et le rapport consolidé.

## Chaîne retenue

| Jalon | Nature | Rôle historique |
|---|---|---|
| x2 | DIAGNOSTIC | liquide plein sous gravité : révèle que la projection post-collision arrive trop tard pour corriger la vitesse de transport |
| x3 | CODE | `prestream` : force -> Q6 -> streaming, avec maintien du Q6 post-collision comme second solve de preuve |
| x4a | CODE | `prestream_single` : un seul solve Q6 avant transport |
| x4b | PERF | `prestream_single_fused` : dépôt du moment tentative et application force+Q6 fusionnés sur CUDA |

## Interprétation physique

Le résultat déterminant de x2 est que faible divergence après collision ne suffit pas : la
vitesse réellement utilisée par le streaming doit être projetée après prise en compte de la
force. x3 teste directement cette hypothèse. x4a montre qu'un second solve post-collision
est inutile car collision SRC et thermostat relatif ne déplacent pas les particules. x4b
supprime enfin le passage particulaire dédié au kick sans changer cet ordre physique.

Le chemin x4b devient le support temporel de la suite du chantier Q6-g-f; il ne signifie pas
que toute la fermeture Q6-g-f (interface, condition de pression, reconstruction face-particule,
restauration de densité) est déjà présente à x4b.

## Provenance

- x2 : `run_0493x2_liquid_only_q6*.sh` et extension `--liquid-only` du générateur x0 ;
- x3 : `README_0493X3_Q6_FORCE_PRESTREAM_TEST.md` et matrice TG/boîte liquide ;
- x4a : `README_0493X4A_Q6_FORCE_SINGLE_SOLVE.md` ;
- x4b : `README_0493X4B_Q6_FORCE_CUDA_FUSION.md`.

La famille X reste liée globalement par le moteur Git; cette curation n'impose aucun SHA.

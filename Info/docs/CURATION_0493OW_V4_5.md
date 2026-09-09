# Curation V4.5 — cycles 0493o et 0493w

## Objet

Cette curation relie le premier cycle 0493 résident (A–J) aux développements qui précèdent directement la série `0493x` : réparation locale du support, calibration constitutive du fluide SRC, référence segmented/Darcy calibrée, normalisation des runners multi-espèces puis Q6 `independent_masked`.

La règle reste conservatrice : **un label n'est créé que s'il est explicitement attesté** par Git, un README, le code de production ou un runner/checker numéroté. Une séquence alphabétique ou numérique n'est jamais complétée par interpolation.

## Série 0493o

| Jalon | Nature | Rôle retenu | Preuve primaire |
|---|---|---|---|
| 0493O0 | BENCHMARK | références SRC-only TG et segmented/Darcy, diagnostics passifs | checker et deux runners O0 |
| 0493O1 | CODE | split local piloté par la population effective `Neff` | README / implémentation O1 |
| 0493O1-fix2 | FIX | autorité CUDA du split-only, suppression du fallthrough CPU dangereux | checker O1-fix2 |
| 0493O2-fix1 | FIX | runner TG mono/dual-espèces à état identique hors types | checker O2-fix1 |
| 0493O3 | PERF | early-exit si aucune paire cellule/espèce n'est pauvre | checker + analyzer O3 |
| 0493O4 | QUALIFICATION | qualification appariée de la réparation sur segmented-Darcy | checker O4 + commit Git |

### Pourquoi il n'existe pas de jalon canonique `0493O2`

Le dépôt conserve explicitement `0493O2-fix1` (`check_0493o2_fix1_tg_multispecies_runner.sh`) et le checkpoint Git groupe `0493o1-o3`, mais aucune preuve autonome suffisamment forte n'identifie un `0493O2` de base distinct. V4.5 conserve donc le suffixe réellement attesté au lieu d'inventer son parent.

### Contrat O1

Le mode O1 est un resampling résident local `split-only`. Pour une paire cellule/espèce de masse positive :

```text
Neff = (sum m)^2 / sum(m^2)
```

Si `Neff < NMin`, les fragments les plus lourds sont scindés jusqu'à `NTarget` ou jusqu'à une limite de sûreté/ressource. Une scission `m -> m/2 + m/2` à vitesse inchangée conserve localement masse, impulsion et énergie cinétique à l'arrondi près. O1 ne répare pas encore les paires vides par refill global.

O1-fix2 est une correction de sûreté importante : le nouveau chemin CUDA doit être autoritaire. Un retour vers l'ancien population guard CPU pouvait encore effectuer des merges alors que `resamplingExtractionEnable=false`, incompatibles avec la sémantique active-prefix de ce chemin.

## Série 0493w

| Jalon | Nature | Rôle retenu | Preuve primaire |
|---|---|---|---|
| 0493W0 | BENCHMARK | audit du régime cinétique du cas segmented-Darcy | runner/analyzer/checker W0 |
| 0493W1 | CALIBRATOR | mesure `nu`, `c_s`, `D_self`, Sc et nombres adimensionnels | suite calibrateur W1 |
| 0493W2 | BENCHMARK | référence segmented-Darcy avec fluide SRC calibré | runner W2 + commit Git |
| 0493W3 | FIX | correction de l'injection dans les cellules partielles d'une aperture segmentée | commit `9355b6b` |
| 0493W4 | RUNNER | normalisation des injections multi-espèces par famille liquid/gas | runner partagé + inventaires |
| 0493W5 | CODE | première version périodique de `independent_masked` | README/runner W5 |
| 0493W6 | DIAGNOSTIC | divergence du flux projeté vs champ cellulaire redéposé | README/runner/checker W6 |
| 0493W7 | CODE | extension `independent_masked` aux familles de BC résidentes | README + qualification W7 |
| 0493W8 | QUALIFICATION | équivalence TG mono / dual-identique | README + campagne W8 |

### W0–W3 : passer d'un cas numérique à une référence physique

W0 teste explicitement l'hypothèse qu'une partie des anomalies du cas cylindre/Darcy provient d'un régime SRC/MPCD extrême plutôt que d'un défaut à réparer immédiatement. W1 remplace ensuite les estimations constitutives par des mesures : viscosité Taylor–Green, réponse acoustique et autodiffusion. W2 réinjecte ces propriétés dans un cas segmented/Darcy calibré. W3 corrige alors le traitement de l'injection au bord des cellules partiellement ouvertes.

Cette chaîne est importante dans le référentiel : elle sépare **défaut numérique de support**, **régime constitutif du fluide** et **sémantique de frontière**.

### W4 : sémantique d'injection indépendante du numéro de type

Le runner partagé conserve les marqueurs `0493w4` dans les diagnostics et expose explicitement :

- `INJECT_PHASE` / `BACKGROUND_PHASE` ;
- forces Q6 déclarées par espèce ;
- forces de fermeture de masse ;
- rapport de masses particulaires ;
- domaine initial `empty|full` ;
- contrat de post-check par espèce.

W4 est donc conservé avec confiance canonique **B** : son rôle est attesté par le code et les inventaires, mais il n'est pas ancré par un README/commit dédié comparable à W5–W8.

## W5–W8 : `independent_masked`

W5 introduit un opérateur Q6 structurellement indépendant par espèce. Une espèce de `q6StrengthDeclared=0` ne construit pas de support actif, ne lance pas de solveur et ne reçoit aucune correction particulaire directe. Le support repose sur une occupation normalisée par `referenceCellMass`, pas sur la fraction massique brute du mélange.

W6 montre qu'annuler la divergence du flux auxiliaire de face ne garantit pas automatiquement la même divergence après application aux particules puis redépôt en cellules, en particulier près d'un bord interne du masque. Le jalon est volontairement diagnostique : il rend le mismatch visible sans le masquer par un critère artificiel.

W7 enlève la restriction périodique de W5 et suit les topologies déjà prises en charge par le Q6 résident : canal, full-face IO, segmented IO et Darcy. W8 clôt ce cycle par une qualification Taylor–Green mono / dual-identique : les deux labels représentent alors le même fluide et doivent retrouver la référence mono à opérateur comparable.

## Graphe historique retenu

```text
0493J
  -> O0 -> O1 -> O1-fix2 -> O2-fix1
                    |
                    +-> O3 -> O4 -> W0 -> W1 -> W2 -> W3 -> W4

0491C -----------------------------------------------> W5 -> W6
                                                       |     |
                                                       +--> W7 -> W8
```

Les flèches résument les dépendances de curation et ne prétendent pas que chaque commit Git forme une branche linéaire indépendante.

## Résultat attendu après reconstruction

À partir de la V4.4 validée à 180 jalons, V4.5 ajoute 15 jalons canoniques :

```text
milestones=195
published_milestones=195
curations_applied=6
```

Le nombre exact `git_candidates_reconciled` est laissé au builder : certains jalons sont document/code-attestés et n'ont volontairement pas besoin d'un candidat numérique Git autonome.

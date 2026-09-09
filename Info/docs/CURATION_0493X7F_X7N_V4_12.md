# Curation V4.12 — 0493x7f à 0493x7n

## Périmètre

V4.12 consolide la séquence qui suit immédiatement la qualification x7e et s'arrête
avant la réparation algorithmique de la restauration de densité (`x7d-v2` puis x7q).
La frontière retenue est volontaire : x7f–x7n décrit l'extension, la mesure des coûts et
le diagnostic du chemin Q6-g-f ; la séquence suivante décrit la correction physique de
ce diagnostic.

## Décisions canoniques

| Jalon | Nature | Décision |
|---|---|---|
| x7f | CODE | généralisation Q6-g-f aux familles statiques multi-BC et projection pré-transport à force nulle |
| x7f-fix1 | — | **non canonique** : réparation d'initialisation du runner LiveVis sous `set -u`; source conservée |
| x7f-fix2 | FIX | garde wall-simple réellement corrigée dans le chemin résident |
| x7g | CODE | Darcy/Brinkman déplacé avant Q6-g-f et non rejoué après collision |
| x7h | INFRA | factorisation du chemin `src-q6-g-f` dans les `run_ok_*` historiques |
| x7i | BENCHMARK | comparaison physique TG / Poiseuille / bend-pipe / same-face IO, sans seuil PASS/FAIL arbitraire |
| x7j | PERF | CG masqué entièrement CUDA résident, physique inchangée |
| x7k | PERF | stripping des diagnostics Q6-g-f hors cadence de résumé |
| x7l | PERF | stripping des téléchargements/réductions thermostat et espèces, physique inchangée |
| x7m | CODE | registre de phases rendu autorité pour l'activation de l'interface physique |
| x7m-fix1 | FIX | domaine de pression monophase rendu indépendant de l'occupation particulaire |
| x7n | DIAGNOSTIC | calibrateur sélectionnable par chemin + diagnostics compression/bruit |

Le placeholder `reference:x7k/x7l` est supprimé du canon mais sa ligne brute reste dans
`raw_milestone_rows` et est réattachée comme preuve B aux deux jalons réels.

## Pourquoi x7k et x7l sont séparés

Les deux étapes ont été introduites par le même commit `0493x7k-x7l`, mais leurs README
et patches sont distincts. x7k cadence les audits Q6-g-f coûteux au premier pas et à
`summaryEvery`; x7l applique ensuite le même principe aux réductions et téléchargements
du thermostat/registre espèces. Les deux sont des optimisations de coût, non des
modifications de physique. Le candidat Git composite reste une provenance du commit et
ne devient pas un jalon canonique composite.

## Pourquoi x7f-fix1 n'est pas canonique

Le patch x7f-fix1 initialise uniquement l'environnement LiveVis du runner de validation
pour éviter une variable non définie avec `set -u`, alors que LiveVis reste désactivé.
Il ne change ni le contrat de frontière ni le solveur. x7f-fix2 modifie au contraire une
garde du chemin résident wall-simple et mérite le statut FIX canonique déjà présent dans
le référentiel.

## x7m et x7m-fix1

x7m corrige d'abord l'erreur conceptuelle qui assimilait une fluctuation `alpha<0.5` à
une interface dans un registre monophase. Sa première version conserve toutefois
`pressureMask=carrierMask`. Le bend-pipe révèle ensuite que des cellules temporairement
vides dans le domaine fictif peuvent tronquer le domaine de pression et rendre une
composante pure-Neumann incompatible. x7m-fix1 impose donc le domaine de calcul complet
comme domaine de pression monophase. C'est une correction structurelle distincte et
explicitement attestée par son patcher historique.

## x7n et la frontière avec V4.13

x7n rend le calibrateur 0493w1 sélectionnable par chemin (`src`, `src-q6`, `src-q6-g-f`)
et ajoute les outils hors ligne qui discriminent transport transversal, fluctuations
d'occupation et compression cohérente. Le commit qui ajoute ses README/runner/analyseurs
porte le diagnostic « défaut x7d compression/bruit identifié via Poiseuille+TG ».

Les sous-révisions `fix1` à `fix4c` du calibrateur sont des raffinements de préflight,
sélection d'expériences et robustesse d'analyse ; elles restent sous x7n. En revanche,
les modifications suivantes de l'opérateur de densité (`x7d-v2`, branche signée), les
symétries x7o/x7p et la fermeture exacte de moment x7q seront auditées ensemble en V4.13.

## Provenance Git

La base V4.11 importait 49 refs et auditait 22 branches. Pour la portion x7f–x7n, les
commits d'introduction observés appartiennent au lignage `surf`, mais la décision n'est
pas prise à partir de `surf` seul : l'audit repose sur l'inventaire multi-ref déjà importé.

Seuls x7j et le couple x7k/x7l possèdent un sujet Git qui nomme explicitement leur jalon :

- `8e11eefc50...` — `0493x7j: make Q6-g-f CG fully CUDA resident pre-smoke` ;
- `f12cfe7c65...` — `0493x7k-x7l: strip Q6-g-f production diagnostics telemetry`.

Pour x7f, x7g, x7h, x7i, x7m et x7n, les commits ajoutent les README/runners correspondants
mais leur sujet ne constitue pas une identité d'introduction explicite. V4.12 ne force donc
pas `introduced_commit` pour eux.

## Provenance historique archivée

Les patches/patchers historiques sont conservés sous `Info/inputs/historical/`. Les copies
`.patch` directement lisibles ne diffèrent des sources récupérées que par la normalisation
des espaces/tabulations horizontaux de fin de ligne, afin de satisfaire `git diff --check`.
Le ZIP `0493x7f_x7n_original_sources.zip` contient les octets exacts des sources récupérées ;
le manifeste `0493x7f_x7n_original_sources.sha256` permet de vérifier chacune d'elles.

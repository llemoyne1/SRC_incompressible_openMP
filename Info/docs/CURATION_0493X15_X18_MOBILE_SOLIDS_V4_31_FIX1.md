# V4.31-fix1 — provenance des paramètres et validation fonctionnelle x18d

## Objet

Ce correctif documentaire ne crée aucun nouveau jalon. Il corrige deux points apparus lors des
requêtes discriminantes de V4.31 :

1. les 20 paramètres `chiKineticBoundaryMode` / `chiSolid*` utilisaient des métadonnées trop larges
   (`x16--x18`, `x16j--x18d`), ce qui créait des relations `ASSOCIATED_WITH` de provenance trop
   générales ;
2. `x18d` était encore marqué `CURRENT/PENDING_LOCAL_CUDA_BUILD_AND_BENCHMARK` alors que la
   compilation CUDA locale et les runs du volet ont depuis été exécutés avec succès sur le
   worktree réel.

## Provenance paramètre → jalon

Le snapshot paramètres reste le même fichier actif mais ses 20 lignes mobiles sont précisées :

- `chiKineticBoundaryMode` → **x16j** ;
- `chiSolidDynamicsEnable`, `chiSolidModel`, `chiSolidMass` → **x16a** ;
- `chiSolidQualificationDiagnosticsEnable` → **x18d** ;
- ressorts/aire/amortissement/sortie membrane de base → **x17c** ;
- ancrage, flexion et renforts transverses de membrane → **x17d** ;
- gravité, amortissement de charnière, conditions initiales et sortie du volet → **x18a**.

La catégorie générique reste `Solides matériels mobiles / FSI`, sans identifiant de jalon, afin que
l'inférence automatique ne transforme pas une plage historique en fausse provenance.

## Statut x18d

Validation opérateur rapportée le **15 septembre 2026** sur le dépôt réel :

- patch x18d appliqué ;
- compilation CUDA locale : **OK** ;
- runs `hinged_plate_2d` : **fonctionnels**.

Le jalon peut donc être marqué **VALIDATED/FUNCTIONAL**. Cette validation atteste le fonctionnement
du chemin normal nettoyé et sa compatibilité avec le démonstrateur volet. Elle **ne quantifie pas**
un facteur d'accélération : un benchmark avant/après reste nécessaire pour toute revendication de
performance chiffrée.

Le contrat x18d reste :

```text
chiSolidQualificationDiagnosticsEnable = false   # chemin normal
chiSolidQualificationDiagnosticsEnable = true    # campagne de qualification
```

## Effets attendus après reconstruction

- aucun nouveau jalon : `milestones=329` ;
- mêmes inventaires bruts : `raw_params_inventory=880`, `raw_env_inventory=621` ;
- une curation supplémentaire : `curations_applied=31` ;
- version de référence : `V4.31-fix1` ;
- `doctor` sans orphelin ni violation de clé étrangère ;
- `milestone x18d` affiche `VALIDATED/FUNCTIONAL` ;
- les requêtes `param` n'attribuent plus artificiellement les paramètres de volet à x16j/x18d.

Comme V4.31, le correctif est **source-only** : `Info/generated/*`, SQLite et le dump SQL doivent être
régénérés sur le checkout réel.

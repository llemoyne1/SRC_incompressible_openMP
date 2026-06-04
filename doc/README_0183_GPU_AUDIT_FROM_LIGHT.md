# 0183 — Audit GPU depuis `clean/openmp-light`

Ce différentiel ne modifie pas le noyau numérique SRC/MPCD. Il ajoute seulement
un audit statique des boucles candidates au GPU et une note de cadrage pour le
chantier `feature/gpu-prototype-from-light`.

Point de départ imposé : `clean/openmp-light`. La version `production-stripped`
reste une cible de livraison, mais elle n'est pas le bon socle de prototypage GPU
car elle a perdu une partie des diagnostics internes utiles à la comparaison
CPU/GPU.

## Fichiers ajoutés

```text
doc/README_0183_GPU_AUDIT_FROM_LIGHT.md
scripts/audit_gpu_candidates_0183.py
dev_history/artifacts/gpu_audit_0183/gpu_candidate_inventory_0183.csv
dev_history/artifacts/gpu_audit_0183/gpu_candidate_summary_0183.csv
```

Le script est en lecture seule et n'a aucune dépendance externe.

```bash
python3 scripts/audit_gpu_candidates_0183.py \
  --root . \
  --out dev_history/artifacts/gpu_audit_0183
```

## Chaîne du pas de temps à préserver

Le pas `run_src_mpcd_base_step` applique successivement : streaming/forçage,
conditions limites, solide immergé, collision SRC, projection Q6, réponse
capacité/viriel, thermostat, maintien de débit moyen, puis branches resampling
lorsqu'elles sont activées (`src/src_mpcd_base.cpp`, lignes 370--432 et
468--590 dans ce snapshot). Cette organisation est essentielle pour le prototype
GPU : toute accélération partielle doit pouvoir être désactivée et comparée à ce
chemin CPU OpenMP.

Les diagnostics à conserver comme oracles CPU/GPU sont les summaries runtime,
masse, moment, température/kBT, résidus Q6, itérations CG, compteurs resampling,
charge virielle/capacity, diagnostics wall/solid leak et dumps `.smpcd`.

## Classement des opérations candidates

| Rang | Opération | Coût probable | Parallélisme | Difficulté mémoire | Risque numérique | Comparaison CPU/GPU | Intérêt physique | Décision |
|---:|---|---|---|---|---|---|---|---|
| 1 | Projection Q6 / solveur elliptique CG | élevé dès que `projectionEnable=true`; les profils 0159 signalaient `q6_projection` comme verrou principal après nettoyage | très bon : tableaux cellules/faces, stencil, AXPY, dot products | moyenne : conserver les champs sur device et gérer les réductions globales | moyen : ordre des réductions et trajectoire résiduelle CG non bit-identiques | excellente : résidus, itérations, divergence avant/après, correction de moment | très fort pour TG, Poiseuille, obstacle/marche, piston | première vraie cible GPU recommandée |
| 2 | Dépôts particules → cellules | élevé et répété : collision, Q6, thermostat, resampling, capacity | très bon sur particules puis cellules | forte : scatter/reduction; le CPU utilise des buffers locaux par thread `nt*nc` plutôt que des atomics | moyen à fort : masse/moment cellule alimentent Q6, thermostat et resampling | bonne si on compare masse, moment, population, champs cellule | très fort tous cas | deuxième cible, ou première seulement si architecture device-résidente |
| 3 | Collision SRC par cellule/particule | moyen à élevé | bon après reconstruction des moments cellule | moyenne : rotation particulaire simple, mais dépôt préalable difficile | faible à moyen : signe aléatoire et wallVP doivent rester déterministes | bonne : moment, kBT, wallVP, stats vitesse | fort tous cas | suivre les dépôts |
| 4 | Thermostat cell-relative | moyen | bon mais multi-passe | moyenne à forte : moments, énergie relative, échelles, rescale particulaire | moyen : agit sur kBT et viscosité | très bonne : `kBTBefore/After`, échelles, particules rescalées | fort Poiseuille/piston/wallVP | suivre les dépôts/collision |
| 5 | Resampling pondéré | élevé en Q6+resampling | mixte : dépôts parallèles, listes et pool irréguliers | très forte : mutations de rôles, free slots, listes donneurs/receveurs | fort : protège les cellules pauvres, trajectoire fragile | moyenne : diagnostics nombreux mais égalité stricte difficile | très fort | à différer |
| 6 | Fermeture virielle/capacity | faible à moyen sauf piston/capacity | bon : cellules + particules | moyenne : dépôt masse, gradient pression, correction vitesse | moyen à fort en piston | bonne : pression virielle, charge pariétale, correction moment | fort piston seulement | différer après Q6/dépôt |
| 7 | Summaries et diagnostics | faible en mode light | bon | faible à moyenne | faible | excellent comme oracle | diagnostic élevé, accélération faible | garder CPU |

## Justification par zones de code

### Q6 / CG : meilleure cible minimale

`apply_q6_periodic_projection` commence par un dépôt cellule, construit le champ
de flux de base, prépare les masques/conditions limites, appelle `project_face_field`,
puis reconstruit et applique la correction particulaire (`src/q6_projection_adapter.cpp`,
lignes 1350--1527). Le coeur elliptique est déjà isolé dans
`project_face_field` et `solve_cg` (`src/elliptic_projection.cpp`, lignes
717--796 et 384--492). Le noyau le plus intéressant est
`apply_elliptic_operator_plan_and_dot`, qui applique un stencil précompilé et
calcule simultanément `pAp` (`src/elliptic_projection.cpp`, lignes 353--381).

C'est le meilleur premier portage parce qu'il travaille sur des champs réguliers
cellule/face, sans listes dynamiques ni mutation de particules. Le coût physique
est important, les métriques de validation existent déjà, et une variante GPU
peut être confinée derrière une option tout en gardant le résultat CPU comme
référence.

### Dépôts particules → cellules : importants mais plus risqués

Plusieurs modules font le même type de réduction particules→cellules. La
collision SRC remplit `localCount/localMass/localPx/localPy` par thread puis
réduit par cellule (`src/src_collision.cpp`, lignes 258--287 et 306--414). Q6
utilise le même schéma pour reconstruire les vitesses cellule
(`src/q6_projection_adapter.cpp`, lignes 160--225). Le thermostat reconstruit les
moments, puis l'énergie relative cellule avant le rescale (`src/thermostat.cpp`,
lignes 117--224). Le dépôt pondéré resampling est encore plus riche : rôle,
masse, moment, population, classification active/wet/poor/rich et listes
candidates (`src/weighted_resampling.cpp`, lignes 2306--2695).

GPU : très rentable à terme, mais le choix algorithmique est structurant :
atomiques, tri/binning par cellule, ou réduction par blocs. Il faut éviter de
commencer ici tant que le choix CUDA/OpenMP target/Kokkos/SYCL n'est pas tranché.

### Collision et thermostat : parallèles mais dépendants des dépôts

La rotation SRC finale est très favorable au GPU : chaque particule lit la vitesse
moyenne et l'angle cellule, puis met à jour `vx,vy` (`src/src_collision.cpp`,
lignes 444--462). Le thermostat final est analogue : chaque particule lit son
échelle cellule et rescale la vitesse relative (`src/thermostat.cpp`, lignes
226--244). Ces passes seules ne justifient toutefois pas un aller-retour CPU/GPU
si les dépôts restent CPU.

### Resampling : à ne pas porter en premier

Le resampling est physiquement central, mais il combine dépôts pondérés,
classification de cellules, listes pauvres/riches, pool de particules, opérations
d'extraction/insertion, remap conservatif et renormalisation thermique. Le code du
pas montre aussi qu'un redépôt peut suivre le garde de population, puis un autre
redépôt peut suivre les éditions de rôles (`src/src_mpcd_base.cpp`, lignes
468--590). Cette branche doit rester CPU tant que Q6 et les dépôts simples ne
sont pas validés côté GPU.

## Première cible GPU minimale proposée

Cible : **backend optionnel pour le solveur elliptique Q6/CG**, pas pour le
resampling.

Périmètre recommandé du premier vrai patch code :

1. ajouter une option désactivée par défaut, par exemple `gpuEnable=false` et
   `gpuBackend=none`, ou plus strictement `q6GpuEnable=false` ;
2. garder le chemin CPU inchangé et utilisé par défaut ;
3. ajouter une interface interne du type `project_face_field_gpu_optional(...)`
   qui renvoie explicitement au CPU si le backend n'est pas compilé ;
4. commencer par le validateur elliptique autonome `build/validate_elliptic_projection`,
   puis seulement intégrer `apply_q6_periodic_projection` ;
5. comparer sur champs, pas bit-à-bit : `residualRel`, `iterations`,
   `divAfterProjectedFluxRms`, `divAfterCellVelocityRms`, masse/moment et
   summaries finales.

Backend conseillé pour le tout premier essai : **OpenMP target optionnel** si le
compilateur de la machine le supporte, car cela ajoute moins de dépendances de
code qu'un port CUDA complet. Si l'environnement GPU cible est NVIDIA et stable,
CUDA deviendra probablement plus performant pour les réductions CG, mais il
introduit immédiatement un second langage de compilation.

## Plan de validation CPU/GPU

### Niveau 0 — validation elliptique isolée

- Construire CPU par défaut.
- Construire variante GPU optionnelle.
- Lancer `build/validate_elliptic_projection` sur les cas périodique et masque
  si disponibles.
- Comparer `residualRel`, norme de divergence après projection, nombre
  d'itérations et erreur RMS du flux projeté.

### Niveau 1 — Q6 dans le pas complet, sans resampling

Cas :

- `tg_periodic_full` avec `projectionEnable=true`, `resamplingEnable=false` ;
- `poiseuille_wall_full` avec wallVP ;
- `open_rect_obstacle_full` / backward step ;
- `piston_virial_full` en gardant capacity/viriel CPU si le GPU ne couvre que Q6.

Tolérances : ne pas exiger une identité binaire. Comparer les métriques physiques
et numériques : masse totale, moment, kBT, `q6ResidualRel`, `q6Iterations`,
`q6DivBefore/After`, vitesse moyenne, pression/capacity pour piston.

### Niveau 2 — Q6+resampling avec GPU limité à Q6

Objectif : vérifier qu'un Q6 GPU partiel ne perturbe pas la branche resampling
CPU. Les métriques critiques sont `mRelRms`, `mRelMaxAbs`, `nPoor/nRich`,
compteurs extraction/insertion/remap, masse et kBT.

### Niveau 3 — Von Kármán

Seulement après les quatre cas discriminants. Le sillage périodique sert alors de
test dynamique qualitatif et statistique, pas de critère bit-à-bit.

## Patch code à éviter au début

- Ne pas porter d'abord `weighted_resampling.cpp`.
- Ne pas remplacer immédiatement tous les dépôts par des atomiques GPU.
- Ne pas supprimer les diagnostics internes de `openmp-light`.
- Ne pas modifier les fichiers `.smpcd` tant que la comparaison CPU/GPU n'est pas
  stabilisée.
- Ne pas toucher `production-stripped` avant validation du prototype.

## Commandes proposées

```bash
git checkout clean/openmp-light
git checkout -b feature/gpu-prototype-from-light
unzip -o SRC_MPCD_openmp_gpu_audit_0183_files_only.zip
python3 scripts/audit_gpu_candidates_0183.py \
  --root . \
  --out dev_history/artifacts/gpu_audit_0183
git add doc/README_0183_GPU_AUDIT_FROM_LIGHT.md \
        scripts/audit_gpu_candidates_0183.py \
        dev_history/artifacts/gpu_audit_0183/gpu_candidate_inventory_0183.csv \
        dev_history/artifacts/gpu_audit_0183/gpu_candidate_summary_0183.csv
git commit -m "Add GPU candidate audit from OpenMP light baseline"
```

## Conclusion opérationnelle

La première accélération GPU réellement utile doit viser le solveur elliptique
Q6/CG, car il est coûteux, régulier, isolable et validable. Les dépôts
particules→cellules sont probablement le second verrou majeur, mais ils imposent
un choix mémoire plus profond. Le resampling doit rester CPU dans la première
phase afin de préserver le garde de population et les validations physiques.

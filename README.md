SRC/MPCD incompressible — version OpenMP de référence

Ce dépôt contient une version de référence d’un code SRC/MPCD pour l’étude d’écoulements liquides quasi incompressibles, actuellement centré sur un écoulement de Poiseuille périodique en direction longitudinale, avec forçage volumique, murs thermalisants en direction transverse, redistribution incompressible de particules, fermeture liquide de type pression effective, et parallélisation OpenMP de la redistribution par tuiles.

L’objectif principal du dépôt est de conserver une base de développement reproductible :

préparation MATLAB des cas tests et des états initiaux ;

sérialisation stricte des paramètres et états particulaires vers le C++ ;

exécution C++/OpenMP du schéma SRC/MPCD ;

validation progressive par tranches ;

diagnostics de conservation, homogénéité d’occupation, débit, énergie, fermeture liquide et performance OpenMP ;

conservation des scripts historiques ayant servi aux étapes intermédiaires de validation.

La branche main doit être considérée comme une branche de référence complète, incluant les scripts de validation intermédiaires. Les développements futurs plus spécialisés, par exemple l’adaptation à un cylindre et à une allée de von Kármán, devraient partir d’une branche séparée afin de préserver cet historique.

1. Organisation du dépôt

SRC_incompressible_openMP/
├── include/
│   ├── boundary_conditions.h
│   ├── common_grid.h
│   ├── dump_io.h
│   ├── liquid_closure.h
│   ├── params_io.h
│   ├── srd_collision.h
│   ├── state_io.h
│   ├── types.h
│   ├── zone_pass.h
│   └── zone_pass_openmp.h
│
├── src/
│   ├── boundary_conditions.cpp
│   ├── common_grid.cpp
│   ├── dump_io.cpp
│   ├── liquid_closure.cpp
│   ├── params_io.cpp
│   ├── srd_collision.cpp
│   ├── state_io.cpp
│   ├── zone_pass.cpp
│   ├── zone_pass_openmp.cpp
│   ├── main_benchmark_poiseuille.cpp
│   ├── main_benchmark_poiseuille_openmp.cpp
│   ├── main_benchmark_poiseuille_openmp_profiled.cpp
│   ├── main_benchmark_poiseuille_openmp_profiled_closure_omp.cpp
│   ├── main_benchmark_poiseuille_openmp_profiled_refbuild_omp.cpp
│   ├── main_benchmark_poiseuille_openmp_profiled_shifted_profiled.cpp
│   ├── main_step01_stream_bc_collision.cpp
│   ├── main_step02_zone_pass.cpp
│   ├── main_step03_double_zone_pass.cpp
│   ├── main_step04_liquid_closure.cpp
│   ├── main_step05_full_step.cpp
│   ├── main_step06_openmp_base_validate.cpp
│   ├── main_step07_openmp_double_validate.cpp
│   ├── main_step08_openmp_full_validate.cpp
│   ├── main_step08_openmp_full_validate_sharedref.cpp
│   └── main_step09_openmp_full_validate_syncserial.cpp
│
├── matlab/
│   ├── prepare_benchmark_poiseuille_equal_openmp_profiled_shifted.m
│   ├── prepare_benchmark_poiseuille_equal_openmp_profiled_shifted_run_simple.m
│   ├── build_benchmark_poiseuille_params_equal.m
│   ├── build_tranche1_params.m
│   ├── build_tranche2_params.m
│   ├── build_tranche4_params.m
│   ├── build_tranche5_params.m
│   ├── build_ad_hoc_state_uniform.m
│   ├── write_params_kv.m
│   ├── write_state_bin.m
│   ├── read_params_kv.m
│   ├── read_state_bin.m
│   ├── read_cellfields_bin.m
│   ├── compare_*.m
│   ├── process_*.m
│   └── prepare_*.m
│
├── .gitignore
└── README.txt

Le dépôt contient volontairement plusieurs exécutables main_* et plusieurs scripts MATLAB historiques. Ils correspondent aux différentes étapes de construction et de validation de la méthode : streaming + conditions limites + collision, redistribution par zone, double passe tuilée, fermeture liquide, validation OpenMP, puis benchmark Poiseuille profilé.

2. Dépendances

2.1. C++ / OpenMP

Le code C++ utilise :

un compilateur C++ moderne, typiquement g++ ou clang++ ;

le standard C++17 ou compatible ;

OpenMP pour les versions parallèles ;

un environnement Linux ou WSL recommandé.

Exemple typique :

g++ --version

et, pour OpenMP :

g++ -fopenmp --version

2.2. MATLAB

MATLAB est utilisé pour :

construire les structures de paramètres ;

générer les états initiaux particulaires ;

écrire les fichiers binaires lus par le C++ ;

générer des scripts bash de lancement ;

comparer les sorties C++ avec les références MATLAB ;

post-traiter les métriques de benchmark et de scaling OpenMP.

Aucune toolbox spécialisée n’est supposée indispensable pour le cœur de préparation des cas simples ; les scripts de post-traitement peuvent toutefois utiliser des fonctions de tracé, tableaux, lecture/écriture de fichiers et manipulation de structures.

2.3. Organisation locale

Les builds, fichiers binaires d’entrée/sortie, dumps et résultats lourds ne doivent pas être versionnés. Le .gitignore ignore notamment :

build/
build_*/
cmake-build-*/
*.o
*.a
*.so
*.exe
*.out
*.bin
runs/
results/
outputs/
dump/
dumps/
slurm-*.out
*.log

Dans l’état actuel, CMakeLists.txt est traité comme local/non versionné. Si une configuration CMake stable est ajoutée plus tard, cette règle devra être revue.

3. Modèle physique et numérique

3.1. Méthode SRC/MPCD

Le code implémente une dynamique particulaire de type SRC/MPCD. L’état particulaire contient au minimum :

les positions x, stockées sous forme intercalée [x1,y1,x2,y2,...] côté C++ ;

les vitesses v, stockées de façon analogue ;

un type particulaire type, utilisé pour préserver une interface commune avec des cas plus généraux ;

une position initiale ou de référence r0, utile pour certains diagnostics ou extensions.

Un pas de temps complet combine les opérations suivantes :

application des forces volumiques ;

streaming particulaire ;

conditions limites ;

collision SRC/SRD avec décalage aléatoire de la grille de collision ;

redistribution incompressible des particules ;

fermeture liquide et correction de vitesse ;

diagnostics et dumps éventuels.

3.2. Cas Poiseuille actuel

Le cas benchmark actuel correspond à un écoulement de Poiseuille dans un domaine rectangulaire, avec :

caseType        = poiseuille
Lx              = 10
Ly              = 10
Nx              = 50
Ny              = 50
gamma           = 20
n               = gamma * Nx * Ny = 50000
dt              = 5e-3
alphaDeg        = 170
kBT             = 1
bodyForceX      = 0.1
g               = 0
boundary_left   = periodic
boundary_right  = periodic
boundary_bottom = thermalize
boundary_top    = thermalize

Les valeurs ci-dessus correspondent au benchmark build_benchmark_poiseuille_params_equal.m, aligné sur une référence MATLAB exportée historiquement.

Le forçage bodyForceX entraîne l’écoulement longitudinal. Les murs inférieur et supérieur sont thermalisants. Les directions gauche/droite sont périodiques.

4. Redistribution incompressible

4.1. Objectif

La redistribution vise à imposer une quasi-incompressibilité en contrôlant localement le nombre de particules par cellule. Le paramètre central est :

gamma = nombre cible moyen de particules par cellule

Une cellule est considérée hors bande si son occupation devient trop faible ou trop élevée par rapport à gamma. Les seuils sont pilotés par :

coef
highMode
lowMode
lowThrBulkOverride
maxRedistribPasses
enableMomentumCorrectionPostRedistribution

L’idée générale est de déplacer localement des particules entre cellules trop remplies et cellules déficitaires tout en limitant les artefacts de densité et en corrigeant autant que possible l’effet sur la quantité de mouvement.

4.2. Restrictions actuelles

La version tuilée/OpenMP est conçue pour les cas liquides à volume fixe, sans surface libre active :

noSurfaceCase = true
redistributionEnableSurfaceTopology = false
redistributionWallWettingEnabled = false
useInterfaceVelocityReorientation = false

Cela signifie que les cas avec surface libre, mouillage, piston ou géométrie mobile ne sont pas l’objectif de cette version de référence. Ils doivent être traités plus tard avec une extension explicite de la logique de redistribution et de frontière.

5. Redistribution par tuiles et double passe décalée

5.1. Motivation

Une redistribution globale sur tout le domaine est difficile à paralléliser efficacement. La stratégie utilisée ici consiste à découper le domaine en zones rectangulaires indépendantes. Chaque zone traite localement les particules dont elle est responsable.

Cette approche prépare le passage à une parallélisation plus large :

OpenMP intra-nœud ;

puis éventuellement CUDA ou MPI ;

tout en gardant une méthode proche de la référence MATLAB.

5.2. Paramètres de tuilage

Les paramètres principaux sont :

useZoneRedistribution = true
zoneTileNx            = 25
zoneTileNy            = 25
zoneUseShiftedSecondPass = true
zonePassthroughMode   = false
zoneSingleFullDomainMode = false

Dans le benchmark actuel, avec Nx = Ny = 50 et zoneTileNx = zoneTileNy = 25, le domaine est découpé en tuiles de 25 cellules par 25 cellules pour la passe de base.

5.3. Double passe : base puis shifted

Pour réduire les artefacts de couture entre tuiles, la redistribution est appliquée en deux temps :

passe base : tuiles alignées sur la grille naturelle ;

passe shifted : tuiles décalées, afin de recouper les interfaces de la première passe.

L’idée est que les défauts d’occupation qui resteraient bloqués aux frontières de tuiles dans la première passe puissent être corrigés lors de la passe décalée.

5.4. Implémentation OpenMP

La fonction centrale est :

run_zone_pass_openmp(...)

Elle effectue une passe de redistribution tuilée selon un mode de layout (base ou shifted). Dans la version OpenMP, les zones sont traitées en parallèle avec une boucle :

#pragma omp parallel for schedule(static)

La logique générale d’une passe est :

construction du layout de zones ;

extraction des particules appartenant à chaque zone ;

snapshot local de l’état d’entrée ;

application locale du noyau de redistribution ;

empaquetage des positions/vitesses modifiées ;

fusion dans l’état de sortie global.

Les métriques de profilage distinguent notamment :

timeLayout
timeZoneExtract
timeSnapshot
timeAlloc
timeKernel
timePack
timeMerge

Ces métriques permettent d’identifier le coût relatif de la construction des zones, du snapshot, du noyau de redistribution proprement dit et de la fusion globale.

6. Fermeture liquide incompressible

6.1. Rôle de la fermeture

La redistribution impose une contrainte forte sur l’occupation locale, mais elle peut perturber la dynamique, la quantité de mouvement ou la pression effective. La fermeture liquide vise à reconstruire une pression effective cohérente et à appliquer une correction de vitesse contrôlée.

La fermeture utilise notamment :

useLiquidClosure = true
useOptimalBetaRepair = true
betaRepair
betaEOS
Kvirial
smoothPdriveAtInterzone
smoothPdriveInterzoneWidthCells
smoothPdriveInterzoneBlend
smoothPdriveIncludeShiftedLayouts

6.2. Pression effective

Le modèle distingue une contribution cinétique et une contribution de type viriel ou pénalisation de densité :

Ptot = Pkin + Pvir

La contribution de fermeture est pilotée par une raideur effective Kvirial, un coefficient betaEOS, et une densité cible liée à l’occupation moyenne attendue gamma.

Dans les développements antérieurs, cette fermeture a été pensée comme une manière de conserver un comportement liquide : densité proche de la cible, pression effective capable de porter les gradients imposés, et correction dynamique évitant que la redistribution ne devienne purement géométrique.

6.3. Correction optimale

Lorsque useOptimalBetaRepair = true, le coefficient effectif de correction est choisi de manière à minimiser l’erreur RMS entre l’état de référence post-SRC et l’état après redistribution/correction. Les métriques produites incluent notamment :

betaRepairOpt
betaRepairApplied
betaRepairNum
betaRepairDen
rmsRepairDU
maxRepairDU
meanAbsRepairDU
momentumDeltaX
momentumDeltaY

6.4. Lissage interzone

Le tuilage introduit potentiellement des discontinuités faibles aux interfaces entre zones. L’option :

smoothPdriveAtInterzone = true

active un lissage de la pression motrice ou du champ de correction au voisinage des interfaces interzones. Les paramètres associés définissent l’épaisseur et l’intensité du mélange.

7. Workflow de préparation et lancement

Le workflow de référence est en deux temps :

MATLAB prépare un dossier d’exécution ;

le binaire C++/OpenMP lit ces fichiers et exécute le benchmark.

7.1. Préparation MATLAB

Depuis MATLAB, se placer dans la racine du dépôt ou ajouter matlab/ au path :

cd('/home/llemoyne/gasdyn/mpcd/incompressible')
addpath('matlab')

Lancer la préparation du benchmark de référence :

prep = prepare_benchmark_poiseuille_equal_openmp_profiled_shifted_run_simple();

ou, selon le script utilisé :

prep = prepare_benchmark_poiseuille_equal_openmp_profiled_shifted();

Le script construit :

workdir/params.kv
workdir/in_x.bin
workdir/in_v.bin
workdir/in_type.bin
workdir/in_r0.bin
workdir/run_benchmark_poiseuille_equal_openmp_profiled_shifted.sh

Par défaut, le dossier de travail est :

rbps8/

et l’exécutable attendu est :

/home/llemoyne/gasdyn/mpcd/incompressible/build/main_benchmark_poiseuille_openmp_profiled_shifted_profiled

Ces chemins peuvent être remplacés par des overrides MATLAB :

prep = prepare_benchmark_poiseuille_equal_openmp_profiled_shifted_run_simple(struct( ...
    'workdir', '/home/llemoyne/gasdyn/mpcd/incompressible/rbps8_test', ...
    'nThreads', 8, ...
    'seed', 1));

Les champs passés en override qui correspondent à des paramètres physiques ou numériques sont transmis à build_benchmark_poiseuille_params_equal. Les champs de runtime (workdir, exePath, prefixIn, prefixOut, seed, nThreads, x, v, type, r0) sont consommés par le script de préparation et ne sont pas écrits comme paramètres physiques.

7.2. Exécution bash générée

Le script MATLAB affiche une commande du type :

bash /home/llemoyne/gasdyn/mpcd/incompressible/rbps8/run_benchmark_poiseuille_equal_openmp_profiled_shifted.sh

Le script bash :

exporte OMP_NUM_THREADS ;

rend l’exécutable appelable par chmod +x ;

lance le binaire C++ avec les chemins vers params.kv et les états binaires.

La signature attendue du binaire principal est :

./main_benchmark_poiseuille_openmp_profiled_shifted_profiled \
  params.kv \
  state_x.bin \
  state_v.bin \
  state_type.bin \
  state_r0.bin \
  out_prefix \
  has_type \
  has_r0 \
  nthreads

Dans le cas généré par MATLAB, has_type = 1, has_r0 = 1, et nthreads correspond à l’override nThreads.

8. Compilation

Le dépôt ne doit pas stocker les fichiers de build. Dans l’organisation locale actuelle, l’exécutable attendu est placé dans :

build/main_benchmark_poiseuille_openmp_profiled_shifted_profiled

Si un CMakeLists.txt local est disponible, une procédure typique est :

cd /home/llemoyne/gasdyn/mpcd/incompressible
mkdir -p build
cd build
cmake ..
make -j

Si l’on compile directement avec g++, une commande indicative pour le benchmark principal est :

cd /home/llemoyne/gasdyn/mpcd/incompressible
mkdir -p build

g++ -std=c++17 -O3 -fopenmp -Iinclude \
  src/boundary_conditions.cpp \
  src/common_grid.cpp \
  src/dump_io.cpp \
  src/liquid_closure.cpp \
  src/params_io.cpp \
  src/srd_collision.cpp \
  src/state_io.cpp \
  src/zone_pass.cpp \
  src/zone_pass_openmp.cpp \
  src/main_benchmark_poiseuille_openmp_profiled_shifted_profiled.cpp \
  -o build/main_benchmark_poiseuille_openmp_profiled_shifted_profiled

Les autres fichiers main_* correspondent à des exécutables de validation ou de benchmark antérieurs. Pour les compiler, remplacer simplement le dernier fichier main_*.cpp dans la commande ci-dessus.

9. Sorties produites

Le benchmark profilé écrit notamment :

out_metrics.csv
out_runout.kv
out_stepXXXX_x.bin
out_stepXXXX_v.bin
out_stepXXXX_type.bin
out_stepXXXX_r0.bin
out_stepXXXX_cellfields.bin

selon le préfixe de sortie demandé.

9.1. Fichier métriques CSV

Le fichier *_metrics.csv contient les diagnostics pas à pas :

step
occStd
outBand
meanKinetic
meanUx
meanUy
Qx
baseOccStd
baseOutBand
shiftedOccStd
shiftedOutBand
meanPdrive
meanPdriveRaw
meanVelocityX
meanVelocityY
particlesMovedDense
particlesMovedSparse
betaRepairOpt
betaRepairApplied
rmsRepairDU
maxRepairDU
meanAbsRepairDU
momentumDeltaX
momentumDeltaY
nThreadsUsedBase
nThreadsUsedShifted
timeStepTotal
timeRefBuild
timeBase
timeShifted
timeClosure
timeDiagnostics
timeDump

9.2. Fichier runout KV

Le fichier *_runout.kv résume l’état final et le profilage global :

finalOccStd
finalOutBand
finalMeanKinetic
finalMeanVelocityX
finalMeanVelocityY
finalQx
totalParticlesMovedDense
totalParticlesMovedSparse
finalBetaRepairOpt
finalBetaRepairApplied
finalRmsRepairDU
finalMomentumDeltaX
finalMomentumDeltaY
nThreadsUsedBase
nThreadsUsedShifted
timeTotalWall
timeLoopTotal
timeRefBuild
timeBase
timeShifted
timeClosure
timeDiagnostics
timeDumps
fracRefBuild
fracBase
fracShifted
fracClosure
fracDiagnostics
fracDumps
timeBaseLayout
timeBaseExtract
timeBaseSnapshot
timeBaseAlloc
timeBaseKernel
timeBasePack
timeBaseMerge
timeShiftedLayout
timeShiftedExtract
timeShiftedSnapshot
timeShiftedAlloc
timeShiftedKernel
timeShiftedPack
timeShiftedMerge
fracBaseLayout
fracBaseExtract
fracBaseSnapshot
fracBaseAlloc
fracBaseKernel
fracBasePack
fracBaseMerge
fracShiftedLayout
fracShiftedExtract
fracShiftedSnapshot
fracShiftedAlloc
fracShiftedKernel
fracShiftedPack
fracShiftedMerge

Ces champs sont importants pour diagnostiquer si le coût est dominé par le noyau de redistribution, la copie/snapshot, le packing, la fusion, la fermeture liquide ou les dumps.

10. Scripts MATLAB principaux

10.1. Préparation de benchmarks

Fichiers importants :

prepare_benchmark_poiseuille_equal_openmp_profiled_shifted.m
prepare_benchmark_poiseuille_equal_openmp_profiled_shifted_run_simple.m
build_benchmark_poiseuille_params_equal.m
build_ad_hoc_state_uniform.m
write_params_kv.m
write_state_bin.m

Le script de préparation :

vérifie que les fonctions MATLAB nécessaires sont sur le path ;

construit les paramètres physiques et numériques ;

génère ou reçoit un état initial (x,v,type,r0) ;

écrit params.kv ;

écrit les fichiers binaires d’entrée ;

génère un script bash prêt à lancer le binaire C++.

10.2. Lecture et post-traitement

Fichiers utiles :

read_params_kv.m
read_state_bin.m
read_cellfields_bin.m
read_f64_grid_bin.m
read_i32_grid_bin.m
analyze_openmp_scaling_results.m
process_*.m
compare_*.m

Ces scripts servent à relire les sorties C++, vérifier les écarts avec les références MATLAB, tracer les indicateurs et analyser la scalabilité OpenMP.

10.3. Scripts historiques par tranches

Les familles :

prepare_tranche*.m
process_tranche*.m
compare_step*.m
main_step*.cpp

correspondent aux étapes progressives de validation :

Tranche 1 : streaming + conditions limites + collision SRC/SRD
Tranche 2 : redistribution simple par zones
Tranche 3 : double passe base + shifted
Tranche 4 : fermeture liquide
Tranche 5 : pas complet
Étapes 6-9 : validations OpenMP et comparaisons avec versions synchrones/sérielles

Ces fichiers ne sont pas tous nécessaires au lancement du benchmark final, mais ils sont essentiels pour reconstruire l’historique méthodologique et refaire des validations intermédiaires lors de la publication des résultats.

11. Stratégie de validation

La validation du code s’est construite par tranches, afin d’éviter de mélanger trop tôt les difficultés :

Tranche 1 : valider streaming, conditions limites et collision ;

Tranche 2 : valider une passe de redistribution par zones ;

Tranche 3 : valider la double passe base + shifted ;

Tranche 4 : valider la fermeture liquide ;

Tranche 5 : valider le pas complet ;

Étapes OpenMP : comparer versions sérialisées, synchrones et parallèles ;

Benchmark Poiseuille : vérifier le débit, la stabilité énergétique, l’occupation, les corrections de fermeture et les temps par phase.

Les métriques principales sont :

occStd                écart-type relatif d’occupation cellulaire
outBand               fraction de cellules hors bande d’occupation
Qx                    débit longitudinal moyen
meanKinetic           énergie cinétique moyenne
betaRepairApplied     correction optimale appliquée par fermeture liquide
rmsRepairDU           intensité RMS de correction de vitesse
momentumDeltaX/Y      variation globale de quantité de mouvement
nThreadsUsedBase      nombre de threads réellement utilisés en passe base
nThreadsUsedShifted   nombre de threads réellement utilisés en passe shifted

Pour les campagnes de scaling OpenMP, le script analyze_openmp_scaling_results.m agrège les résultats de sous-dossiers threads_* et calcule notamment :

elapsed_seconds
speedup_vs_1
efficiency_vs_1
deltaQx_vs_1
deltaOccStd_vs_1
deltaMeanKinetic_vs_1

12. Limites actuelles

Cette version de référence est volontairement spécialisée :

cas liquide à volume fixe ;

pas de surface libre active ;

pas de mouillage ;

pas de réorientation de vitesse d’interface ;

pas de piston ou de frontière mobile complexe dans la version tuilée actuelle ;

géométrie principale : domaine rectangulaire Poiseuille ;

obstacle solide interne non encore intégré dans cette branche de référence.

Ces limitations sont importantes pour les développements futurs. Un cas d’allée de von Kármán autour d’un cylindre nécessitera au minimum :

une représentation d’obstacle solide circulaire ;

une condition limite particulaire sur cylindre ;

une stratégie de redistribution compatible avec cellules solides/fluides partielles ;

des diagnostics de force, traînée, portance et fréquence de shedding ;

une réflexion sur la manière d’appliquer ou de masquer la fermeture liquide au voisinage du solide.

Ces développements doivent être faits sur une branche dédiée, par exemple :

git checkout -b feature/von-karman-cylinder

ou sur une branche nettoyée issue de main, par exemple :

git checkout -b clean/von-karman-base

13. Utilisation Git recommandée

La branche main conserve l’état complet et l’historique de validation. Avant toute modification importante :

cd /home/llemoyne/gasdyn/mpcd/incompressible
git status
git pull --rebase origin main

Pour créer une branche de développement :

git checkout -b feature/nom-de-la-branche
git push -u origin feature/nom-de-la-branche

Pour archiver l’état complet avant nettoyage :

TAG=archive/pre-cleanup-main-$(date +%Y%m%d)
git tag -a "$TAG" -m "Archive full project before cleanup branch"
git push origin "$TAG"

Pour identifier précisément la version de départ d’une analyse :

git rev-parse --short HEAD

Les demandes de modification devraient idéalement préciser :

Dépôt : https://github.com/llemoyne1/SRC_incompressible_openMP
Branche : <branche>
Commit de départ : <hash>
Fichiers concernés : <liste>
Objectif : <objectif physique/numérique>
Contraintes : <fichiers ou mécanismes à ne pas modifier>
Tests attendus : <script ou métrique de validation>

14. Notes pour publications et reproductibilité

Ce dépôt doit permettre de reconstruire l’évolution de la méthode depuis les tests élémentaires jusqu’au benchmark OpenMP profilé. Pour une publication, il sera probablement utile de conserver :

la branche main comme archive complète ;

une branche nettoyée contenant uniquement la version finale reproductible ;

un tag correspondant à chaque figure ou série de résultats ;

les paramètres params.kv de chaque campagne ;

les scripts MATLAB ayant généré les états initiaux ;

les sorties *_runout.kv et *_metrics.csv utilisées pour les figures ;

les informations de compilation : compilateur, options, nombre de threads, machine, environnement WSL ou cluster.

Une bonne pratique est d’associer à chaque campagne un dossier externe de résultats, non versionné dans Git, contenant :

params.kv
run_benchmark_*.sh
*_metrics.csv
*_runout.kv
figures/
logs/

et de noter dans un fichier texte le commit exact :

git rev-parse HEAD > commit_used.txt

15. État actuel du README

Le README historique était volontairement très court et centré sur le benchmark Poiseuille OpenMP profilé. Cette version étendue décrit le projet dans son état actuel : méthode, scripts MATLAB, structure C++, tuilage, fermeture liquide, workflow de lancement, diagnostics et stratégie de branches.

À terme, il serait préférable de renommer ce fichier en :

README.md

afin de bénéficier d’un affichage Markdown complet sur GitHub.


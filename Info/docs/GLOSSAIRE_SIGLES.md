# Glossaire rapide des sigles et notions SRC_GPU-SURF

Ce glossaire complète `Info/generated/lexique_jalons.md`.

- Le **lexique des jalons** répond à « que signifie `x10e` ? ».
- Le **présent glossaire** répond à « que signifie `Q6-g-f`, `CIC`, `RT0`, `TC`, etc. ? ».

Les entrées sont classées par ordre alphabétique. Elles privilégient le sens effectivement utilisé
par SRC_GPU-SURF ; lorsqu'un nom est une convention interne plutôt qu'un acronyme standard, cela
est indiqué explicitement.

| Sigle / terme | Développement / nom | Fonction dans SRC_GPU-SURF | Remarque |
|---|---|---|---|
| `alpha (α)` | Fraction / indicateur de phase | Champ géométrique local utilisé pour distinguer support liquide, interface et extérieur. | L'interface physique est typiquement repérée autour de `alpha=0.5`; plusieurs variantes d'alpha existent selon l'usage, notamment x6c et x10cic. |
| `B0` | Label interne de reconstruction / diagnostic face→particule | Étape historique de diagnostic de l'application des corrections de face vers les particules. | À distinguer du chemin B1/RT0 actif de reconstruction. |
| `B1` | Label interne de reconstruction face→particule | Reconstruction affine des corrections Q6 définies aux faces vers les particules. | Dans le chemin qualifié, B1 est associé à la reconstruction RT0/MAC et à la fermeture périodique x7q. |
| `Ca` | Nombre capillaire | Compare les effets visqueux aux effets de tension superficielle. | Utilisé dans les campagnes de surface libre / Taylor–Culick. |
| `CG` | Gradient conjugué | Solveur itératif utilisé par la projection Q6. | Les versions récentes disposent d'un chemin CUDA résident, notamment x7j. |
| `chi (χ)` | Fraction / masque Darcy du solide | Champ de pénalisation des régions solides ou poreuses. | Intervient dans les cas Darcy-Brinkman et la distinction fluide/solide. |
| `CIC` | Cloud-In-Cell | Dépôt/interpolation particule→grille utilisé notamment pour construire l'alpha cinétique x10cic. | Le champ CIC cinétique est volontairement séparé de l'alpha x6c utilisé par Q6/capillarité. |
| `CUDA` | Compute Unified Device Architecture | Backend GPU utilisé pour les chemins résidents du solveur. | Les qualifications récentes cherchent à éviter les fallbacks CPU et transferts hôte inutiles. |
| `Darcy / Brinkman` | Modèle de milieu poreux / pénalisation volumique | Représente les solides et pertes de quantité de mouvement via un champ `chi` et une pénalisation. | Le couplage avec Q6-g-f est explicitement ordonné et qualifié dans le cycle x7. |
| `EOS` | Equation of State / équation d'état | Fournit une fermeture de pression, notamment pour la phase gaz explicite x6g/x14. | Le chemin gaz utilise une pression de référence liée à `gamma`, `kBT` et l'aire de cellule. |
| `Fr'_m` | Froude modifié de quantité de mouvement | Nombre sans dimension utilisé pour comparer les cas d'impact / jet liquide-gaz à des références externes. | Employé notamment dans la comparaison Sato de x14at. |
| `gamma (γ)` | Occupation moyenne de particules par cellule | Paramètre MPCD contrôlant la population moyenne par cellule. | Influence coût, bruit statistique et propriétés de transport. |
| `GPU` | Graphics Processing Unit | Matériel d'exécution des chemins CUDA résidents. | La reproductibilité trajectoire-par-trajectoire n'est pas supposée bit-à-bit entre matériels/exécutions. |
| `kappa (κ)` | Courbure d'interface | Entre dans le saut capillaire `sigma*kappa`. | Les cycles x9–x12 distinguent champ de courbure, cutoff de résolution et géométrie cinétique. |
| `kBT` | Échelle thermique `k_B T` | Contrôle l'agitation thermique des particules et intervient dans plusieurs fermetures physiques. | Peut être spécifique à l'espèce dans les développements multi-espèces / liquide-gaz. |
| `Ma` | Nombre de Mach | Rapport entre vitesse caractéristique et vitesse du son. | Sert à contrôler le domaine quasi-incompressible des cas de qualification. |
| `MAC` | Marker-And-Cell / grille décalée | Convention de localisation des composantes de vitesse/corrections sur les faces de cellule. | Le chemin B1 reconstruit les corrections MAC/face vers les particules. |
| `MPCD` | Multi-Particle Collision Dynamics | Méthode mésoscopique particulaire : streaming puis collision collective par cellule. | Le socle du projet est un fluide SRC/MPCD avec rotation stochastique de type SRD. |
| `Neumann` | Condition de Neumann | Famille de conditions de sortie imposant une dérivée / flux plutôt qu’une valeur primaire. | Le cycle x8 traite la sortie passive cinétique-pression; la lignée post-x14av x8r-neumann→x9c-outlet adapte la fermeture au multiphasique et x9e-fix3 en optimise le chemin résident; 0414 généralise les ouvertures segmented x/y. |
| `Oh` | Nombre d'Ohnesorge | Compare effets visqueux à inertie et tension superficielle. | Utilisé dans les qualifications de surface libre et Taylor–Culick. |
| `P/K` | Quantité de mouvement / énergie cinétique | Raccourci employé pour les fermetures conservant simultanément moment linéaire et énergie cinétique. | Très présent dans les cycles x9–x10 de rétention cinétique. |
| `phi (φ)` | Potentiel de projection Q6 | Inconnue scalaire du solveur de projection, utilisée pour reconstruire la correction de vitesse / pression. | Les conditions de sortie x8r imposent notamment `phi=0` sur l'outlet de pression. |
| `Q2` | Reconstruction biquadratique tensorielle | Interpolant 2D construit sur un stencil 3×3 du champ alpha CIC pour crossing et normale subcellulaires. | Correspond au jalon x10biq ; actif dans la chaîne x12. |
| `Q6` | Projection quasi-incompressible interne au projet | Projette le champ de vitesse / moment afin de réduire la divergence. | Le label est historique/interne au projet ; les versions récentes opèrent sur GPU résident. |
| `Q6-g` | Q6 force-aware | Variante qui inclut la force dans la vitesse tentative avant streaming afin que la projection agisse sur la vitesse réellement transportée. | Base de l'architecture Q6-g-f. |
| `Q6-g-f` | Chaîne Q6 force-aware + interface + face→particule + densité | Chemin de projection de référence combinant force prestream, interface physique, pression, reconstruction B1/RT0 et restauration lente de densité. | Sélectionné par le mode `src-q6-g-f`; distinct du comparateur historique `src-q6`. |
| `Re` | Nombre de Reynolds | Rapport inertie / viscosité. | Utilisé pour caractériser TG, Poiseuille, VK, jets et autres cas de qualification. |
| `RT0` | Reconstruction affine de type RT0 sur grille MAC | Reconstruit vers les particules les corrections portées par les faces. | Dans SRC_GPU-SURF, le terme apparaît principalement comme `RT0/MAC-to-particle` dans B1. |
| `Sc` | Nombre de Schmidt | Rapport viscosité cinématique / diffusivité massique. | Mesuré par les calibrateurs de transport du fluide SRC. |
| `sigma (σ)` | Tension superficielle | Coefficient du saut capillaire `sigma*kappa`. | Paramètre central des cycles x9–x14. |
| `SRC` | Nom interne du chemin de collision stochastique du projet | Collision collective par cellule fondée sur une rotation stochastique des vitesses relatives, utilisée comme socle MPCD. | Le projet emploie `src` comme mode de calcul sans projection Q6. |
| `SRD` | Stochastic Rotation Dynamics | Formulation standard de collision MPCD par rotation stochastique. | Le socle SRC/MPCD du projet appartient à cette famille. |
| `TC` | Taylor–Culick | Cas de rétraction d'une feuille liquide sous tension superficielle. | Benchmark majeur des cycles x12–x13. |
| `TG` | Taylor–Green | Vortex / champ périodique analytique utilisé pour calibrer et qualifier le transport. | Sert notamment à mesurer la viscosité effective. |
| `VK` | von Kármán | Rue de tourbillons derrière obstacle utilisée pour tester dynamique, fréquence et rupture de symétrie. | Les campagnes x7/x8 l'utilisent comme cas applicatif sensible. |

## Règle de maintenance

Ce fichier est **curé manuellement**. Il ne doit contenir que des termes réellement utilisés dans le projet
et suffisamment stables pour aider à la lecture des runners, rapports et commentaires de code. Les détails
historiques restent dans la base relationnelle et dans `Info/generated/jalons.md`.

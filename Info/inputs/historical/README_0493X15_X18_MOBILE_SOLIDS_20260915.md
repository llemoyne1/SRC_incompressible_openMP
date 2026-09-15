# 0493x15 -> x18d — solides matériels mobiles, frontière lagrangienne et FSI

Date documentaire : **2026-09-15**.  Cette source consolide le chantier « solides mobiles »
mené du 12 au 14 septembre 2026 et la section correspondante du rapport de projet.

## Décision physique qui structure la lignée

Le projet distingue désormais explicitement deux usages de `chi` :

1. **milieu poreux / optimisation** : `chi -> Darcy/Brinkman`, chemin historique inchangé ;
2. **solide matériel imperméable** : `chi0 -> Gamma0={chi=0.5} -> frontière lagrangienne persistante -> collision cinétique particule/paroi`.

Pour le second usage, `chi` reste le format géométrique utilisateur, mais après l'initialisation
`Gamma(t)` devient l'autorité géométrique. La frontière ne doit plus être rasterisée puis extraite à
chaque pas pour décider le franchissement.

## x15 — pourquoi le chi-solid volumique n'est pas la fermeture matérielle finale

Les campagnes x15a/x15b/x15c instrumentent séparément Brinkman, `outward_bath`, chiVP, réaction
totale et perméabilité. Elles montrent qu'une fermeture mécanique exacte ne garantit pas
l'imperméabilité : `mean + chiVP` peut fermer le budget tout en restant poreux. x15e obtient zéro
crossing avec la chaîne historique forte (`mean_outward_bath`, alpha=800000, chiVP=0.25), tandis
que x15f rétablit de très nombreux crossings lorsqu'on enlève `outward_bath`. La conclusion de
conception est que l'imperméabilité historique dépend surtout d'une réémission **après** pénétration,
ce qui est inadéquat pour une frontière matérielle mobile.

## x16a--x16i — dynamique solide et échec du remapping comme principe final

x16a introduit `SolidDynamics`/`SolidGeometry` et le premier DOF `rigid_slab_1d`; x16b ajoute la
charge spatiale exacte `Delta p_s(c)=-Delta p_f(c)` et sa projection générique vers les DOF. Les
bilans x16a ferment quantité de mouvement et action-réaction au voisinage du roundoff.

x16d met ensuite en évidence le défaut du masque mobile binaire : les basculements de cellules
capturent brusquement des particules. Sur le test galiléen documenté, la masse fictive change
d'environ +639 aux événements de masque, et le RMS d'impulsion atteint ~430.5 contre ~35.7 loin
des événements; `outward_bath` représente alors environ 69% du pic. x16f montre que la seule
synchronisation temporelle ne corrige pas le phénomène; x16g neutralise le bath au pas de capture
mais l'impulsion réapparaît; x16h réinjecte spatialement et réduit fortement le pic mais crée une
déplétion artificielle. x16i compare `binary_event` et `swept_geometry`: les erreurs galiléennes
restent de l'ordre de 0.27--0.29 et le swept remapping coûte davantage. Cette branche est donc
conservée comme **historique d'invalidation** du principe `Delta chi -> remapping`.

## x16j--x16q — première frontière cinétique issue de chi, puis limite de la reconstruction Eulerienne

x16j introduit `chiKineticBoundaryMode=specular`: la surface `chi=0.5` est traitée comme une paroi
cinétique, avec crossing subcellulaire Q2 et réflexion spéculaire dans le repère local de la paroi.
Les jalons x16k--x16q raffinent géométrie, diagnostic de pénétration, recherche de racine, cohérence
des arêtes et topologie Q2. Les cas rigides deviennent propres, mais les cas déformables restent
sensibles et la complexité de la reconstruction continue augmente. Cette lignée valide le **principe
cinétique**, mais est supplantée pour le solide matériel mobile par x17a.

## x17a/x17b — état de référence pour l'imperméabilité matérielle

x17a extrait une seule fois le contour `chi=0.5` (marching squares/bilinéraire), construit un mesh
lagrangien persistant et résout directement l'intersection entre une particule et un segment mobile
dans l'espace-temps. Avec `P(s)=P0+s dP`, `A(s)=A0+s(A1-A0)` et `B(s)=B0+s(B1-B0)`, la condition
d'intersection donne une équation quadratique exacte en `s`. Au point d'impact :

    c  = v - u_wall
    c' = c - 2 (c.n) n
    v' = u_wall + c'

et `Delta p_s = -Delta p_f`. x17b ajoute l'exclusion initiale unique des particules du côté solide,
sans remapping pendant le run. Sa qualification de référence est **PASS** sur six cas (courbe
statique, rigide, déformation prescrite; repos/boost) : zéro pénétration stricte, persistance du mesh,
fermeture action-réaction/charge et test galiléen.

## x17c/x17d — mécanique de membrane : utile pour le couplage, non retenue comme modèle structural final

x17c transforme les noeuds du contour en DOF matériels : ressorts d'arêtes, pénalité d'aire et
amortissement relatif; l'impulsion sur une arête est distribuée aux deux noeuds par fonctions de
forme. x17d ajoute ancrages, flexion et essais de cohérence transverse. La campagne a établi le
transfert bidirectionnel fluide-structure mais a aussi montré les limites d'un modèle structural
minimal : effondrement pour une pénalité d'aire trop faible, puis cas trop raides ou repliements/
auto-intersections lorsque l'on cherche une forte flèche. La décision est de ne pas investir dans
un solveur de solide détaillé pour la démonstration principale. `x17d-fix2` reste néanmoins un
correctif de calcul important : suppression d'un plafond historique de 4096 blocs afin de couvrir
tous les slots particulaires actifs sur les gros cas.

## x18a/x18b — démonstrateur actuel : volet rigide articulé

x18a ajoute `hinged_plate_2d`, solide fermé de faible épaisseur à un seul DOF `theta` autour d'une
charnière fixe. L'équation est

    I theta_ddot = tau_hydro + tau_g - C theta_dot

et l'impulsion angulaire hydrodynamique est assemblée directement à partir des impacts x17a :
`Delta Lz=(x-xH) Jy - (y-yH) Jx`. La géométrie est reconstruite par rotation rigide exacte du contour.
La sortie physique principale `chi_hinged_plate_0493x18a.csv` conserve angle, vitesse angulaire,
forces et couples.

x18b réutilise ce modèle pour une chute depuis environ -45 deg dans un fluide initialement au repos.
Le sweep de densité multiplie masse particulaire et kBT par le même facteur, afin de changer la masse
surfacique tout en gardant `kBT/m` et donc l'échelle de vitesse thermique. Les labels `gas/liquid`
sont des régimes de densité du même modèle MPCD, pas deux équations d'état distinctes.

`x18a-fix2` corrige une incohérence d'initialisation mise en évidence par LiveVis : pour un angle
initial non nul, l'ancien `darcyInitialDeactivateBelowChi=0.5` créait un trou vertical alors que le
contour lagrangien était déjà tourné. Le correctif désactive cette déactivation Eulerienne et exclut
les particules dans la géométrie réellement tournée avant le premier pas.

Les audits x18 observés sont propres sur le solide rigide : x18a à Ux=0.52 donne 150 échantillons
sans particule intérieure et sans collision multiple; x18b gaz avec diagnostic à chaque pas donne
254 échantillons, ~1.10e6 particules inspectées par échantillon, 284789 collisions cumulées aux
instants audités et zéro pénétration stricte/second/third collision. Il s'agit d'une validation
d'imperméabilité observée, pas d'une preuve formelle d'absence de traversée complète intra-pas.

## x18d — nettoyage du chemin normal

Le coût des diagnostics de qualification (x16l, inventaire fictitious-fluid x16c, fermetures x17a,
réductions de réaction, CSV de contrôle) rendait les sweeps longs inutilement chers. x18d introduit
`chiSolidQualificationDiagnosticsEnable=false` par défaut : le chemin normal conserve la physique et
les résultats scientifiques mais ne paye plus les oracles de qualification. Le mode `true` les
réactive pour les campagnes dédiées. Pour `hinged_plate_2d`, la charge minimale est
`(Delta Px, Delta Py, Delta Lz)`; pour `membrane_2d`, les impulsions nodales et forces internes
restent physiques.

**Statut au 15 septembre 2026 :** x18d est l'architecture courante documentée, mais sa compilation
CUDA locale et son benchmark de performance restent l'autorité avant de lui attribuer un statut
`PASS` de production.

## Choix documentaires explicites

- `0493x18c_mobile_solid_production_fastpath` **n'est pas un jalon canonique** : c'était une proposition
  spécialisée `hinged_plate_2d` rejetée parce que l'optimisation devait être globale.
- `x18a-fix1` n'est pas promu : il corrige uniquement le câblage du runner.
- les nombreux réglages mécaniques `x17d-fix3...fix8` restent des preuves historiques sous `x17d`;
  seul `x17d-fix2` est promu séparément car il corrige la couverture particulaire du collisionneur.
- les diagnostics de pénétration sont conservés comme outils de qualification opt-in, non comme
  calculs physiques du chemin normal.

## Provenance binaire

Archive primaire associée :

`Info/inputs/historical/0493x15_x18_mobile_solids_20260912_15_original_sources.zip`

SHA-256 : `c1d55589bf7ca21257411b4585290ec3e66d0fe1fc6e9db5daa9c89e7be0b7b7`

L'archive contient les packages source sélectionnés, les summaries disponibles, le CSV physique du
volet, l'analyseur de pénétration x18 et les versions TeX/PDF du rapport consolidé. Elle possède son
propre `MANIFEST_SHA256.txt`.


## Validation locale x18d — 15 septembre 2026

Après application de x18d sur le worktree réel, la compilation CUDA locale a réussi et les runs
`hinged_plate_2d` ont été exécutés avec succès. x18d est donc considéré fonctionnel et validé pour
le chemin normal nettoyé. Cette validation ne fournit pas encore de mesure quantitative du gain de
performance; toute revendication d'accélération reste subordonnée à un benchmark avant/après.

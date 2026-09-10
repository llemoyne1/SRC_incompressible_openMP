# Curation V4.22 — branche Neumann multiphasique post-x14av

## Périmètre

Cette curation prolonge V4.21 à partir de la démonstration atomiseur `x14av`.
Elle documente la campagne de reconstruction de la sortie cinétique Neumann
déclenchée lorsque le jet liquide atteint l'outlet droit.

Le problème n'est **pas** reclassé comme un nouveau cycle capillaire x9. La base
possède déjà les jalons historiques `x9a`, `x9b`, `x9c`, etc. de tension
superficielle. Les sources des 8–9 septembre ont malheureusement réutilisé
certains de ces labels pour la branche Neumann. V4.22 conserve donc les noms
historiques bruts comme preuve mais désambiguïse les identités canoniques :

- source `0493x8r` post-x14av → `0493x8r-neumann-species`;
- source/log `0493x9a-neumann` → `0493x9a-neumann`;
- source/log `0493x9b-neumann` → `0493x9b-neumann`;
- source explicitement nommée `0493x9c-outlet` → `0493x9c-outlet`.

Les jalons historiques `0493x8r`, `0493x9a`, `0493x9b` et `0493x9c`
restent inchangés.

## Point de départ : x8q sous contrainte multiphasique

Le `x8q` historique reconstruit la demi-distribution cinétique entrante d'une
sortie Neumann par un bain local. Ce mécanisme avait été qualifié dans le
contexte des écoulements ouverts précédents. L'atomiseur `x14av` révèle une
limite de domaine : quand une interface liquide/gaz arrive sur l'outlet, la
reconstruction cinétique peut rétroagir sur la composition et le support de
phase.

Le package `x8q_ablation_neumann_0493x8q.zip` définit alors un A/B causal :
conserver la sémantique de pression/Q6 Neumann mais couper uniquement les ghosts
cinétiques x8q. Le cas OFF est explicitement diagnostique et ne devient pas une
BC de production. V4.22 ajoute cette preuve au `x8q` existant sans invalider sa
qualification historique dans son domaine initial.

## Reconstruction expérimentale

### x8r-neumann-species

La première tentative sépare le bain x8q par espèce :

`bath[cellule_frontière][espèce]`

afin que nombre, masse, moment, énergie, type et fallback thermique ne puissent
plus mélanger gaz et liquide. Les checks statiques sont positifs, mais la
famille de reconstruction par bain n'est pas retenue : la source x8v indique
explicitement que les reconstructions x8q/x8r ont échoué lorsque l'interface
atteint l'outlet.

### x8v — réplique microscopique

x8v abandonne le fit de moments et miroir directement chaque particule réelle
proche de la frontière dans une cellule extérieure virtuelle. La copie conserve
exactement type, masse et vitesse et n'est matérialisée que si sa trajectoire
recroise effectivement l'outlet. Le README x8w rapporte toutefois un échec
runtime quasi immédiat de x8v.

### x8w — cellules virtuelles statistiques

x8w remplace la réplique unitaire par des cellules virtuelles extérieures
échantillonnées à partir de la cellule physique immédiatement adjacente. Cette
version échoue parce qu'elle réinjecte directement les fluctuations
d'occupation MPCD de la cellule frontière dans la demi-population entrante :
le test court produit une couche de densité à l'outlet.

### x8x — réservoir virtuel coarse-grained

x8x sépare :

- le support d'espèce à la face ;
- la densité totale moyenne sur plusieurs cellules intérieures ;
- les moments cinétiques coarse-grained par espèce ;
- une population extérieure Poisson indépendante.

Le sampler lui-même est vérifié : pour les paramètres gaz de l'atomiseur, le
demi-flux analytique vaut `1.0376329136` particules/cellule/pas et le Monte-Carlo
du package donne `1.037345`, variance `1.04039035`. Ce résultat valide le
mécanisme d'échantillonnage mais pas la BC complète. La campagne suivante
constate encore une dérive de densité du réservoir avec le déficit intérieur.

### x8y — réservoir de pression à densité de référence

x8y remplace la densité coarse-grained par une occupation de référence `Nref`
(8 dans le cas nominal) tout en gardant support de phase et moments par espèce.
Le long run révèle un nouveau défaut : après contact liquide/outlet, le
coarse-state liquide peut avoir une vitesse moyenne normale dirigée vers
l'intérieur. x8y recopie alors ce drift dans le Maxwellien extérieur et le
réservoir devient un injecteur liquide macroscopique.

### x8z — suppression du backflow normal

x8z impose, dans le repère de normale sortante,

`u_n,ghost = max(u_n,interior, 0)`.

La variance thermique reste inchangée. Le run 200×400 conservé atteint 1500
pas et montre encore une pathologie forte en aval : `N_liq=66737`,
`meanLiquidVx=-0.03369` et `downstreamWidth80=1.1862`. La correction est donc
partielle.

### x9a-neumann — suppression du drift complet en backflow

Le README x9a rapporte qu'avec x8z le liquide peut encore glisser
tangentiellement le long de l'outlet lorsque la composante normale est clampée.
x9a met donc la **vitesse moyenne complète** du réservoir à zéro en régime de
backflow, tout en gardant les fluctuations thermiques.

À 1800 pas sur 200×400, le mode catastrophique est réduit mais la population
liquide reste très élevée (`55519`) et l'étalement aval demeure important
(`downstreamWidth80=1.052`). La source x9b interprète le résidu comme une
barrière cinétique du demi-réservoir liquide.

### x9b-neumann — réservoir gaz + outflow liquide strict

x9b sépare les deux phases :

- le gaz conserve le réservoir virtuel de pression ;
- le liquide ne reçoit **aucun** candidat virtuel entrant ;
- une particule liquide sortante suit simplement le chemin physique
  `crossing -> inactive`.

Le gain est net sur le cas 200×400 à 1800 pas :

| branche | N liquide | mean ux liquide | width80 | detachedComponents |
|---|---:|---:|---:|---:|
| x9a-neumann | 55519 | 0.02448 | 1.05197 | 9 |
| x9b-neumann | 15563 | 0.15211 | 0.05521 | 7 |

Ces valeurs sont des diagnostics de l'analyseur x14av, pas des critères de
qualification physique. Visuellement, x9b met cependant en évidence une limite
nouvelle : la frontière agit comme un « hachoir ». Les particules qui quittent
le domaine sont correctement supprimées, mais la perte de support alpha dans
la dernière cellule est vue par la chaîne d'interface comme une nouvelle
extrémité liquide/gaz et peut détacher artificiellement des morceaux.

### x9c-outlet — prolongation du support de phase

x9c-outlet conserve intégralement le contrat particulaire x9b et modifie
uniquement le support géométrique de phase sur les cellules appartenant à une
sortie Neumann segmentée :

`alpha_boundary_ext = max(alpha_boundary, alpha_one_cell_inward)`.

Le même prolongement est appliqué :

1. au champ physique x6c avant x6f/capillarité ;
2. au champ CIC cinétique x10 après filtrage.

Il ne modifie pas les particules, les masses/occupations par espèce, le
`liquidMassCIC` x14v, les comptes EOS du gaz ni la suppression physique du
liquide sortant.

Le package lui-même choisit explicitement le nom `0493x9c-outlet` et le gate
`MPCD_Q6_PHASE_OUTLET_GHOST_CONTINUATION_0493X9C_OUTLET` pour éviter la
collision avec le x9c capillaire historique.

## Résultats applicatifs x9c-outlet

Deux runs locaux sont conservés.

### 200×400, 1800 pas

L'environnement enregistré confirme simultanément x9b strict-outflow et
`MPCD_Q6_PHASE_OUTLET_GHOST_CONTINUATION_0493X9C_OUTLET=1`.

À 1800 pas :

- `N_liq = 14951`;
- `meanLiquidVx = 0.15875`;
- `downstreamWidth80 = 0.03332`;
- `detachedComponents = 2`.

À géométrie et durée identiques, x9b donne 7 composants détachés. Cet indicateur
est favorable mais n'est pas, à lui seul, un critère physique.

### 400×400, 3000 pas

Le run long confirme le gate x9c-outlet et atteint 3000 pas. L'analyseur x14av
reste explicitement `DEMONSTRATION_DIAGNOSTIC_ONLY`; ses composantes connexes
ne séparent pas proprement fragmentation physique, atomisation et artefact
strictement frontal. La qualification finale reste donc visuelle et ciblée :
le prolongement est jugé convaincant, quelques petits morceaux résiduels sont
visibles à basse résolution, tandis qu'ils ne sont plus évidents sur 400×400.

Ce résultat suffit pour retenir x9c-outlet comme **candidat physics-first de
travail** à la sortie multiphasique, mais pas comme BC Neumann universellement
qualifiée.

## Performance

Toutes les branches x8w→x9c-outlet conservent volontairement plusieurs
mécanismes non optimisés (synchronisation du nombre de candidats GPU→CPU,
collecte/scans du pool inactif, passes dédiées). Les packages les décrivent
explicitement comme `physics-first`.

Une optimisation a été demandée après l'acceptation qualitative de x9c-outlet,
mais aucun artefact primaire complet et vérifiable de cette optimisation n'est
inclus dans le présent corpus. **V4.22 s'arrête donc à x9c-outlet** et ne crée
aucun jalon d'optimisation par anticipation.

## Statut de curation

V4.22 ajoute neuf identités canoniques :

`x8r-neumann-species`, `x8v`, `x8w`, `x8x`, `x8y`, `x8z`,
`x9a-neumann`, `x9b-neumann`, `x9c-outlet`.

Aucun candidat Git historique existant `x8r`, `x9a`, `x9b` ou `x9c` n'est
retargeté : ces candidats sont déjà liés à des jalons plus anciens et
sémantiquement différents. Les nouvelles branches proviennent de patches de
travail et de runs locaux postérieurs au snapshot Git de référence.

Le ZIP de provenance V4.22 contient les packages originaux ainsi qu'une sélection
de sorties runtime textuelles, les deux compact archives x9c-outlet et les deux
vidéos finales. Les octets de chaque entrée sont conservés et contrôlés par
`MANIFEST_SHA256.tsv`.

Comme pour V4.21, le patch de curation livré doit rester strictement source-only :
aucun `Info/db/src_reference_dump.sql`, aucune base SQLite et aucun
`Info/generated/*` n'est inclus. Ces produits sont reconstruits localement par
`build_src_reference.py`.

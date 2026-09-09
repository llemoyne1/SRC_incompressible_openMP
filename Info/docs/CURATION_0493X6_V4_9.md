# Curation V4.9 — 0493x6a à 0493x6g : géométrie d’interface et pression gazeuse

## Objet

Cette curation consolide la séquence qui transforme le premier `free_surface_masked`
de x5 en une architecture de pression réellement attachée à l’interface physique. Les
jalons x6a..x6g existaient déjà dans le référentiel consolidé sous forme rétrospective ;
after audit des README/runners, leurs définitions sont remplacées par les rôles historiques
attestés. Le correctif `0493x6f2`, absent du canon initial, est ajouté comme jalon autonome.

## Séquence retenue

- **x6a — DIAGNOSTIC** : construit et audite une pression gazeuse EOS et son potentiel
  Q6, mais ne l’injecte pas encore dans le solveur.
- **x6b — DIAGNOSTIC** : reconstruit à cadence sparse la géométrie de phase afin de
  comparer le carrier Q6 à l’isovaleur physique `alpha=0.5`.
- **x6c — INFRA** : matérialise `rawFill` et `alpha` sur GPU à chaque solve ; à ce stade
  la projection ne lit pas encore ces champs.
- **x6d — CODE expérimental** : applique pour la première fois une distance cut-face
  `theta` mais seulement sur le bord active/inactive du carrier.
- **x6e — DIAGNOSTIC** : scanne toutes les traversées `alpha=0.5`, y compris
  active-active et inactive-inactive, et démontre que le bord du carrier ne peut pas
  représenter l’interface physique.
- **x6f — CODE** : sépare `pressureMask` et `carrierMask` et prépare les coefficients de
  face de l’interface physique une fois par solve Q6.
- **x6f2 — FIX** : borne la source géométrique avant filtrage, `geom0=clamp(rawFill,0,1)`,
  tout en conservant l’occupation brute non bornée comme diagnostic.
- **x6g — CODE** : impose enfin `p_l|Gamma=p_g` sur le stencil x6f et conserve cette face
  comme point d’insertion futur de `p_g + sigma*kappa`.

## Décisions de classification

`x6c` est classé **INFRA** plutôt que CODE au sens fonctionnel : son patch initial construit
les deux champs résidents mais précise que la projection ne les consomme pas encore. Il
s’agit de l’infrastructure permanente sur laquelle x6d/x6f/x6g sont construits.

`x6d` reste **CODE**, mais son statut indique explicitement qu’il s’agit d’une expérience
historique non retenue. `x6e` est le diagnostic qui invalide son hypothèse architecturale.

`x6f2` est ajouté comme **FIX** canonique. La correction est conceptuellement importante :
`rawFill` est une occupation normalisée et peut dépasser 1. La filtrer directement comme
une fraction géométrique pouvait faire passer une cellule vide au-dessus de `alpha=0.5`.
Le correctif borne uniquement la source géométrique, sans champ résident, passe CUDA,
flag ou paramètre utilisateur supplémentaire.

## Effet sur le référentiel

Le nombre de jalons passe de **196 à 197**. Les sept entrées x6a..x6g existantes sont
consolidées ; `x6f2` est la seule nouvelle entrée canonique.

La grammaire X de V4.8 reconnaît déjà les suffixes `lettres+chiffres`, donc `x6f2` peut être
relié automatiquement à la provenance Git lorsqu’elle est présente.

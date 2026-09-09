# Curation V4.17 — 0493x9i → 0493x9z

## Portée

V4.17 ferme en un bloc accéléré le reste du cycle `x9` sans comprimer les identités historiques. Elle part de V4.16 (`221` jalons) et :

- retire les deux agrégats devenus redondants `x9a-x9c` et `x9i-x9l` ;
- individualise `x9i`, `x9j`, `x9k`, `x9l` ;
- consolide `x9m` comme fermeture statique de mouillage préférée ;
- ajoute les qualifications `x9n`, `x9o`, `x9p` ;
- ajoute le benchmark exploratoire `x9q` ;
- requalifie `x9r` comme correctif actif de résolution capillaire ;
- consolide `x9s` comme benchmark impact/splash ;
- individualise `x9t` à `x9z` comme pont cinétique vers x10.

Cardinalité attendue : `221 - 2 + 15 = 234` jalons, soit `18` curations appliquées.

## Mouillage x9i–x9p

`x9i` est la première condition de Young active : la normale p3 est remplacée localement pour satisfaire `nAB·nWall=-cos(theta)`. L'angle local est correct, mais la rupture de normale pollue `div(n)`. `x9j` déplace donc la condition dans les ghost samples du champ de courbure ; `x9k` généralise cette continuation par miroir cisaillé à plusieurs profondeurs ; `x9l` essaie une reconstruction directement au mur-face. Ces trois améliorations restent insuffisantes sur toute la plage angulaire et sont historiquement supplantées.

`x9m` change de construction : normale de Young au mur + première normale p3 hors support pariétal (`j=4`, centre `4.5h`) + corde jusqu'au crossing physique. La courbure est estimée par `2 sin(ΔΦ/2)/L` sans écraser `alpha` ni le champ normal p3. C'est la meilleure fermeture **statique** du cycle, mais pas une loi dynamique universelle de ligne de contact.

`x9n` teste plan, scaling `1/R` et ellipses ; `x9o` mesure la sensibilité à la phase sous-maille tangentielle ; `x9p` teste les évolutions sessiles 90→60/120 et les cas hold. Le sens de mouillage/démouillage est correct, mais les équilibres restent comprimés vers 90° et la courbure de ligne triple devient bruitée loin de 90°.

## Dripping, cutoff et splash x9q–x9s

`x9q` est explicitement un test de potentialité : jet injecté, col/pincement, chute et impact, sans calibration quantitative du breakup. Il révèle le défaut de petite échelle traité par `x9r`.

`x9r` ajoute `surfaceTensionMinRadiusCells`. Zéro restaure exactement le chemin antérieur. Pour `N_R>0`, seule la courbure utilisée dans `sigma*kappa` est bornée après interpolation au crossing physique. Le champ p3 brut, LiveVis, `alpha` et la position de l'interface restent inchangés. La valeur historique `3` est un choix de développement, pas une constante universelle ; des campagnes ultérieures utilisent aussi `4`.

`x9s` paramètre l'impact d'une goutte sur paroi sèche ou flaque. Il reste un benchmark qualitatif de changements de topologie/splash, pas une mesure convergée d'un Weber critique.

## Pont cinétique x9t–x9z

Les labels `x9t` à `x9z` sont attestés séparément par leurs runners/analyseurs et par les commentaires du backend courant. Ils appartiennent encore historiquement à x9, mais leur domaine fonctionnel est `FREE_SURFACE_KINETICS`.

- `x9t` : première réflexion interne liquide-vide conservative, avec fraction de réflexion et voie de transmission/évaporation.
- `x9u` : couverture des sorties de support et recherche d'un bain de recul jusqu'à deux cellules.
- `x9v` : diagnostic passif des voies de fuite de x9u.
- `x9w` : correction imposant que le bain soit du bulk physique `alpha>=0.5`.
- `x9x` : détection du crossing physique prédit et correction au temps de crossing.
- `x9y` : côté initial évalué pointwise et crossing localisé par quatre bissections bornées.
- `x9z` : réflexion individuelle, une normale par donneur, puis compensation affine P/E du bain.

Le patch `x10a` ultérieur indique explicitement qu'il conserve la loi spéculaire individuelle x9z : cette série constitue donc la passerelle historique immédiate vers x10 et ne doit pas être fusionnée avec le seul benchmark x9s.

## Git et confiance

Les candidats `x9i…x9z` sont des candidats X de confiance B dans l'audit multi-ref historique lorsqu'aucun sujet de commit ne nomme explicitement le jalon. V4.17 les relie aux identités canoniques sans transformer artificiellement leurs ancres génériques en `introduced_commit`. Les décisions de sémantique sont fondées prioritairement sur les README/diffs historiques et les runners/analyseurs archivés.

## Provenance

Les originaux utilisés sont archivés byte-for-byte dans :

- `Info/inputs/historical/0493x9i_x9z_original_sources.zip`
- `Info/inputs/historical/0493x9i_x9z_original_sources.sha256`

Les sources lisibles individuelles sont également conservées dans `Info/inputs/historical/`. Les fichiers x9s–x9z proviennent du snapshot de dépôt audité ; les documents x9i–x9r proviennent des bundles historiques conservés.

## Validation attendue sur le dépôt réel

- `milestones=234`
- `curations_applied=18`
- `git_commits=533`
- `git_refs=49`
- `git_candidates=1185`
- `git_candidates_reconciled=51`
- `published_milestones=234`
- `published_params=314`
- `published_flags=625`
- `quick_check=ok`
- aucune violation FK ni orphelin de publication.

Les candidats `x9i` à `x9z` doivent être `LINKED` lorsqu'ils existent ; aucune identité agrégée `x9a-x9c` ou `x9i-x9l` ne doit subsister dans les jalons publiés.

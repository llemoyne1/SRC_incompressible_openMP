# Curation V4.46 — x20c à x21e : caractérisation article

Cette curation reprend la frontière déjà versionnée par :

- `0043_0493x19d_hotpath_diagnostic_cleanup.sql` (V4.43),
- `0044_0493x20a_article_fluid_campaign.sql` (V4.44),
- `0045_0493x20b_article_tg_requalification.sql` (V4.45),

puis ajoute la campagne article menée depuis x20c.

## Portée

La curation est strictement documentaire. Elle n'applique aucun patch solver et ne
recompile rien.

Elle ajoute treize jalons canoniques :

`x20c`, `x20d`, `x20e`, `x20f`, `x20g`, `x20h`, `x20i`, `x20j`,
`x21a`, `x21b`, `x21c`, `x21d`, `x21e`.

Elle met aussi à jour les statuts de `x20a` et `x20b`, désormais exécutés.

## Résultat transport retenu

Le jeu article final assemble :
- TG long x20b pour le coeur du balayage,
- MSD x20a,
- extension alpha x20c,
- TG 256x256 x20d à 165/175 deg.

La base conserve les statuts point par point et ne transforme pas les REVIEW/INVALID
en valeurs qualifiées.

## Résultat longitudinal retenu

La conclusion canonique est :
- SRC : propagation longitudinale faible-compressible, vitesse proche de l'échelle
  thermique ;
- src-q6-g-f : suppression du mode longitudinal cohérent, sans vitesse acoustique
  robuste assignable sous ce protocole ;
- x20f : seules les branches non-angle sont retenues ;
- x20g/x20h : les chemins historiques/frais sont bien sensibles à l'angle ;
- x20i : rerun angle propre ;
- x20j : alpha175 SRC résolu au moyen du fit amorti long-wave, fermeture non résolue.

## Résultat capillaire retenu à cette frontière

x21a-x21d construisent le protocole de la Section 3.4.
Le principe retenu pour x21e est :
1. laisser relaxer une goutte active ;
2. sélectionner un plateau géométrique ;
3. lancer des shadows courts sigma/sigma0 depuis exactement le même checkpoint ;
4. mesurer l'incrément de pression ;
5. reconstruire offline la même courbure de face que celle injectée :
   `x6c -> p3/Scharr -> alpha=0.5 -> x9r`.

La campagne x21e est **en cours** : cette curation ne prétend pas encore fournir
les valeurs finales de `sigma_eff`, la figure 07 ou les tables 03/S3.

## Point de reprise pour un nouveau chat

Le prochain travail scientifique n'est pas de modifier le solveur. Il faut laisser
terminer/reprendre `scripts/run_0493x21e_article_capillary_radius_campaign.sh`
avec le fix2 de parsing checkpoint, puis analyser le package
`article_capillary_outputs.zip`.

Aucune nouvelle instrumentation CUDA n'est requise.

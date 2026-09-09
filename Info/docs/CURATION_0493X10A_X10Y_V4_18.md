# Curation 0493x10a–x10y — V4.18

Cette curation ferme le cycle **x10 de cinétique de surface libre** en remplaçant les agrégats historiques par les identités effectivement attestées et en distinguant le chemin de production des ablations. Aucun C++/CUDA, runner solver ou `livevis_control.kv` n’est modifié.

## Découpage canonique

- **x10a–x10e** : géométrie de crossing, hard retention, barrière finale, réaction analytique locale, miroir tangent. Ces essais sont historiques; x10h retire ensuite la barrière universelle pour rendre l’interface mobile.
- **x10f–x10g** : ablation de réservoir global mono-composant puis optimisation hiérarchique strictement performance-only. Les définitions restent dans le code mais sans call-site actif courant.
- **x10h–x10i** : sémantique relative compatible avec une interface mobile, puis réaction mésoscopique décalée. x10i reste le fallback hard-r1 legacy hors chemins continus.
- **x10j/x10k** : ablations spéculaires rejetées; **x10l** est observation-only.
- **x10m/x10n** : primitives de paroi mobile locale puis polyligne marching-squares continue; modes autonomes OFF mais infrastructure réutilisée.
- **x10o** : socle actif Q6-hydrodynamique + enveloppe thermique.
- **x10cic + x10biq(Q2) + x10p/q + x10u/v** : chaîne géométrique/cinétique qualifiée de production; le CIC cinétique reste distinct de x6c.
- **x10r/s/t** : ablations cinématiques OFF.
- **x10w** : limiter thermique local implémenté mais OFF, exclusif avec x12a dans le snapshot audité.
- **x10x/x10y** : campagnes/analyses de qualification, pas de nouveau mode C++.

## Chaîne x12 auditée

Le snapshot 26/08 verrouille `x10o + CIC + Q2 + x10p/q + x10u + x10v + x12a`, avec x10r/s/t OFF, x10w OFF, x10j/k/m/n OFF et x10l éventuellement activé comme diagnostic. Le tag qualifié `7655b81b...` atteste explicitement `x10o+CIC+Q2+x10p/q+x10u+x10v`.

## Provenance

Les patchers historiques x10a–i, x10m–q et x10u/v, les reviews Q2/x10w, les scripts de qualification et l’audit du snapshot sont conservés dans `Info/inputs/historical/`. Les octets sources exacts sont regroupés dans `0493x10a_x10y_original_sources.zip` avec manifeste SHA-256.

# 0493x21h — finalisation article de la caractérisation capillaire

Jalon de post-traitement uniquement. Il ne compile ni n'exécute le solveur et ne modifie aucun fichier C++/CUDA.

Entrées gelées attendues :

- `runs/0493x21e_article_capillary_radius_s10000/article_capillary_review_fix3/data/capillary_review_radius_means.csv`
- `runs/0493x21e_article_capillary_radius_s10000/article_capillary_review_fix3/data/capillary_review_realizations.csv`
- `runs/0493x21g_article_capillary_wave_n234_ensemble_seed4932501_4933501_4934501/analysis/capillary_calibration_0493x12cal.csv`
- `.../capillary_calibration_modes_0493x12cal.csv`
- `.../capillary_calibration_cases_0493x12cal.csv`
- `.../traces/mode_n3_ensemble_trace.csv`

Le script refuse de produire les éléments article si le gate dynamique n'est pas PASS ou si les critères gelés ne sont plus satisfaits.

Sortie :

`runs/0493x21h_article_capillary_outputs_v2/article_capillary_outputs_v2.zip`

La Figure 5 finale contient uniquement :

1. courbure reconstruite vs `1/R_eff` ;
2. trace capillaire d'ensemble `n=3` et fit amorti ;
3. dispersion `omega_meas^2` vs prédiction déclarée avec pente globale `G_sigma`.

L'ancien diagnostic de pression absolue, `x9e` et la vitesse RMS interfaciale thermique sont exclus de la figure et du tableau principaux.

# 0493x21g — completion de la calibration capillaire dynamique pour l'article JCP

## Objet

`0493x21g` est un jalon d'orchestration article uniquement. Il ne modifie ni le solveur C++/CUDA,
ni le binaire, ni le calibrateur x12cal. Il complète le mode `n=3` qualifié en x21f par les modes
`n=2` et `n=4`, avec les trois mêmes graines, puis relance l'analyse x12cal sur la matrice globale
`3 modes x 3 seeds`.

## Référence n=3 déjà qualifiée

- modes : `n=3`
- seeds : `4932501`, `4933501`, `4934501`
- gate x21f : `PASS`
- `omegaFit/omegaTheory = 0.975033333333`
- `fitR2 = 0.999741321261`
- `windowGainStd = 0.0253083386722`
- `G_sigma,n=3 = 0.950690001111`

La valeur `sigmaEffRaw_mode=9506.90001111` reste une estimation par mode et ne qualifie pas la
propriete globale tant que `n=2,3,4` n'ont pas ete analyses ensemble.

## Parametres physiques figes

- grille : `256 x 128`
- `Lx=1.0`, `Ly=0.5`, `h=1/256`
- `gamma=8`
- `dt=0.0063471328149122585`
- `kBT=0.125`
- masse liquide : `1.0`
- `rho_L = 524288`
- angle SRC : `120 deg`
- `sigma_declared=10000`
- profondeur moyenne : `H=0.25`
- amplitude initiale : `a=2h`
- `surfaceTensionMinRadiusCells=4`
- viscosite article : `nu_eff=0.00051019788`
- fermeture cinetique : chaine qualifiee x13h (`x10o + CIC + Q2 + x10p/q + x10u + x10v + x12a`)
- `projectionMomentumCorrection=false`
- `q6ForceProjectionMode=prestream_single_fused`

## Modes nouveaux

Les six nouvelles realisations sont :

- `n=2`, seeds `4932501`, `4933501`, `4934501`;
- `n=4`, seeds `4932501`, `4933501`, `4934501`.

Avec la loi de dispersion declaree :

- `n=2`: `omega_theory = 6.14071322736`, `T = 1.02320122672`, environ `323` steps pour `2T`, `128` cellules/longueur d'onde, `a/lambda=0.015625`;
- `n=3`: `omega_theory = 11.3013852168`, `T = 0.555965944583`, `176` steps, `85.3333` cellules/longueur d'onde, `a/lambda=0.0234375`;
- `n=4`: `omega_theory = 17.4009643069`, `T = 0.361082592687`, environ `114` steps, `64` cellules/longueur d'onde, `a/lambda=0.03125`.

Les runs sont donc courts et sur petite grille. Le recorder de masse reste actif comme en x21f ;
la fenetre LiveVis n'est pas ouverte afin de conserver le protocole strictement identique au mode
n=3. Aucun dump restart periodique n'est ajoute pour ces cas de 114--323 steps.

## Qualification globale

L'analyseur historique qualifie chaque mode avec les seuils x12cal inchanges. Le statut global est :

- `PASS` si les trois modes sont `PASS`, `mean fit R2 >= 0.98` et la dispersion relative des gains
  entre modes est `<= 5 %`;
- `REVIEW` selon le second niveau x12cal (`<=10 %`, `mean R2 >= 0.90`, modes utilisables);
- sinon `INVALID`.

Aucun seuil ne doit etre assoupli pour obtenir PASS.

## Sortie de decision

Le runner produit :

`runs/0493x21g_article_capillary_wave_n234_ensemble_seed4932501_4933501_4934501/analysis/global_gate_0493x21g_n234_3seeds.txt`

Si le gate est `PASS`, l'etape suivante est la generation des CSV article-ready, de la nouvelle
Figure 5 a trois panneaux et du Tableau 3, sans nouveau run. Si le gate n'est pas `PASS`, seule
l'origine du mode defaillant doit etre diagnostiquee ; la physique et les seuils restent figes.

## Base /Info

Cette note documente le plan de campagne. La curation SQL du resultat ne doit etre creee qu'apres
obtention du verdict x21g afin de ne pas enregistrer comme jalon un resultat non encore produit.

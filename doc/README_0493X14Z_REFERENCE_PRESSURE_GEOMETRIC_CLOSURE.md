# 0493x14z — fermeture géométrique légère du terme de pression de référence x14v

## Objet

Correction ciblée du défaut de quantité de mouvement observé sur la goutte oscillante
liquide/gaz x14x.  La loi x14v reste

    J_excess = J_refl - J_thermo

mais la partie uniforme `p_ref` de `J_thermo` est projetée sur une résultante globale
exactement nulle.  La partie variable `delta p = p_G-p_ref` reste strictement inchangée.

Pour chaque segment x10n de longueur `L_s`, on forme le défaut géométrique global de la
même géométrie mi-pas utilisée par x14v :

    eps = sum_s (-dy_s, +dx_s)
    P   = sum_s L_s

puis la contribution uniforme est corrigée par

    p_ref dt [a_s - (L_s/P) eps]

avec `a_s=(-dy_s,+dx_s)`. Ainsi la somme de la partie `p_ref` est nulle à l'arrondi
d'accumulation GPU près, sans annuler une résultante physique provenant de `delta p`.

## Contrat de coût

Le patch privilégie explicitement le coût plutôt qu'une mesure exacte de l'impulsion x6g :

- **0 nouveau kernel CUDA** ;
- **0 nouveau `cudaMemset`** : les 24 octets de scratch sont remis à zéro dans le kernel
  x10cic déjà obligatoire ;
- **0 nouvelle passe O(Ncell)** ;
- **0 nouvelle passe O(Np)** ;
- **24 octets** de stockage résident, alloués paresseusement seulement si le gate est actif ;
- pendant le build x10n déjà existant : **1 sqrt + 3 atomicAdd(double) par segment
  d'interface valide uniquement** ; les endpoints sont encore en registres, donc aucune relecture
  des tableaux de segments n'est ajoutée ;
- dans le kernel x14v existant : quelques multiplications/soustractions par segment.

Le surcoût est donc O(N_Gamma) et non O(Ncell) ou O(Np). Sur une goutte R/h=40 il n'y a
que quelques centaines de segments, contre 3.2 millions de particules.

## Gate

    MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE

Le **défaut source est 0** tant que x14z n'est pas requalifié. Le runner x14x fourni dans ce
ZIP conserve lui aussi le défaut 0. Le test x14z doit explicitement passer `=1`.

La fermeture est automatiquement inactive si l'ablation x14y
`MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=0` est demandée.

## Préimage

Le script s'applique sur l'état courant contenant x14y. Il refuse une préimage ne contenant
pas le marqueur x14y afin d'éviter d'appliquer silencieusement le patch sur un source obsolète.
Aucune loi liquide x10u/x10v/x12a ni x6g n'est modifiée.

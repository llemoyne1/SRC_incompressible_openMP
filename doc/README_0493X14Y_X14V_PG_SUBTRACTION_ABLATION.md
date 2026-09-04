# 0493x14y — ablation de la soustraction p_G dans x14v

Objectif : tester si la dérive barycentrique observée avec x14v provient de la
soustraction discrète de la traction thermodynamique x6g reconstruite dans
x14v.

Production inchangée par défaut :

    MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1

Ablation :

    MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=0

Avec 0, x6g reste ACTIF dans Q6, x14l reste ACTIF et x14v reste ACTIF, mais
x14v transfère l'impulsion brute des réflexions gazeuses J_raw au lieu de
J_raw - J_x6g. Cette variante double donc volontairement la composante
thermodynamique déjà portée par x6g ; elle est uniquement diagnostique et ne
doit pas devenir un profil de production.

Implémentation : un booléen lu côté host et passé au kernel cellulaire x14v
existant. Aucun buffer permanent, aucune passe particulaire supplémentaire,
aucune modification de x10u/x10v/x12a ou de x6g.

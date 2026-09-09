# Curation V4.13 — x7d-v2 à x7q : restauration signée, symétrie et fermeture de moment

## Périmètre

Cette curation reprend exactement à la frontière laissée par V4.12 : `x7n` a isolé le
problème de confusion entre compression cohérente et bruit d'occupation dans la
restauration de densité x7d. V4.13 reconstruit la séquence de réparation qui mène à la
chaîne Q6-g-f qualifiée `x7q`.

Chaîne canonique retenue :

```text
x7n
  -> x7d-v2
  -> x7d-v2-fix2
  -> x7d-v2-signed1
  -> x7o
  -> x7p
  -> x7q
```

Les changements `x7d-v2` à `x7p` sont regroupés par le commit Git du 11 août 2026
`1d6eae3b0e6c8c698557207435a7893043f21042` (`q6 symetry restored Poiseuille low Mach
validated q6-g-f`). `x7q` possède ensuite son commit explicite du 12 août
`9c76fbb64232065dfe082d0332310b7c9c070a9d`, suivi du commit de qualification physique
`887181b9fd42e972f7f7281fabcf6e91c15739d6`.

## Jalons ajoutés

### x7d-v2 — gate cohérent de compression

Le x7d historique impose une cible proportionnelle à `rawFill-1`. Le diagnostic x7n
montre qu'une partie de ce signal est du bruit d'occupation MPCD. x7d-v2 introduit donc
un classificateur spatial pour la branche positive : le défaut central et au moins un
voisin de face doivent dépasser le même seuil. Après admission, le défaut complet est
utilisé ; le seuil ne forme pas une dead-band soustraite.

Le comportement historique reste disponible exactement lorsque le gate est désactivé.
Le profil final documenté active le gate avec un seuil de `3/gamma`.

### x7d-v2-fix2 — première fermeture périodique de moment

Pendant cette campagne, le chemin B1 `fullDomain` montre un changement parasite du mode
uniforme `k=0` dans les directions périodiques. Un gradient de pression interne ne doit
pas changer le moment total de l'espèce projetée dans une telle direction.

`x7d-v2-fix2` accumule donc une estimation massique centrée cellule de la correction et
la retranche lors de l'application B1. Cette fermeture est physiquement substantielle,
mais elle est encore approchée : `x7q` montrera que l'interpolation RT0 réellement
échantillonnée aux positions particulaires possède un résidu supplémentaire.

### x7d-v2-signed1 — restauration signée cohérente

Le patch `signed1` exige explicitement un état `x7d-v2/fix2a` déjà qualifié. Il conserve
la branche positive de x7d-v2 et réintroduit une correction des déficits négatifs sous
forme d'une branche distincte de traction/déplétion. La cellule et au moins un voisin de
face doivent franchir le seuil négatif ; le défaut complet est ensuite multiplié par
`q6DensityRelaxationTractionGain`. `gain=0` est un no-op exact.

Profil final documenté : seuil positif `3/gamma`, seuil négatif `6/gamma`,
`tractionGain=1.0`, `tau_rho=0.25`.

## Jalons existants consolidés

### x7o — symétrie du Q6 independent_masked/fullDomain

L'ancien raccourci `fullDomain` interprétait implicitement les valeurs centrées cellule
comme faces est/nord, ce qui produisait une différence orientée non équivariante par
réflexion. x7o remplace cette convention par les vitesses de face FV centrées et
reconstruit la correction cellule à partir des deux faces opposées. Les domaines
partiels conservent leurs sémantiques de masque/interface x6f.

### x7p — symétrie du Q6 commun

x7p applique la même convention au Q6 commun : moyenne arithmétique des cellules
adjacentes sur une face intérieure, correction construite d'abord sur les faces puis
reconstruction cellule pour l'application particulaire.

### x7q — fermeture exacte du moment B1/RT0

La fermeture `x7d-v2-fix2` neutralise l'estimation centrée cellule, mais B1 applique
réellement une reconstruction affine aux positions particulaires. Le terme affine ne
s'annule exactement que si le barycentre massique instantané des particules coïncide
avec le centre de cellule, ce qui n'est pas garanti pour un échantillon MPCD fini.

x7q spécialise donc uniquement le chemin `B1 + fullDomain + direction périodique` :
le premier passage mesure le moment RT0 effectivement appliqué, une réduction GPU en
calcule le résidu, puis un second passage résident retire exactement le mode uniforme.
Les domaines partiels, notamment le dam-break avec interface libre, gardent le chemin
B1 historique et ne paient pas ce second passage.

## Sous-correctifs conservés mais non canonisés

Deux suffixes sont volontairement conservés comme preuves sans créer de nouveaux
jalons :

- `x7d-v2-fix1` : le script dit explicitement qu'il complète les call-sites qu'un
  premier patcher x7d-v2 avait laissés non écrits après avortement. Il répare
  l'application du patch, pas le modèle physique ;
- `x7d-v2-fix2a` : enlève uniquement la dépendance erronée du gate fix2 à
  `projectionMomentumCorrectionEnable`. Il rend automatique la fermeture déjà définie
  par fix2 sans introduire une nouvelle loi.

## Qualification finale

Le runner `scripts/run_0493x7i_q6_g_f_physical_qualification_x7q.sh` porte le profil de
production final et couvre Taylor-Green, Poiseuille, bend-pipe et same-face IO. Le
commit `887181b9...` atteste explicitement le passage de cette qualification multi-cas.

## Effet sur le canon

V4.12 contenait 202 jalons. V4.13 ajoute trois étapes historiques absentes du référentiel
initial (`x7d-v2`, `x7d-v2-fix2`, `x7d-v2-signed1`) et consolide `x7o`, `x7p`, `x7q`
sans en créer de doublons : le total attendu devient **205 jalons**.

La curation ne modifie aucun C++/CUDA, runner solver ou `livevis_control.kv` : seules les
sources de provenance et la base documentaire sous `Info/` sont modifiées.

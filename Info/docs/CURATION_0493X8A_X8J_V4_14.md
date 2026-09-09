# Curation V4.14 — x8a à x8j : diagnostic, qualification et premier von Kármán ouvert

## Frontière retenue

V4.14 reprend après la fermeture Q6-g-f `x7q`. Elle s'arrête avant `x8k`, qui
introduit la première correction sémantique dédiée de l'inlet segmenté
Poiseuille et ouvre le sous-cycle suivant des conditions limites ouvertes.

La séquence reconstruite est :

```text
x7q
 -> x8a  diagnostic exact de l'impulsion Darcy
 -> x8b  attribution temporelle Darcy / résidu non-Darcy
 -> x8c  localisation temporaire par étapes
 -> x8d  qualification analytique Q6-g-f Poiseuille/Brinkman
 -> x8e  recalibration TG + carte de raideur Darcy
 -> x8f  premier candidat VK à inlet/outlet ouverts
    |-> x8g  qualification vraie full-face / bilan de masse
    `-> x8h  restart hydrodynamique des longs runs
          -> x8i  analyse du sillage établi (POD + sondes)
             -> x8j  nondimensionnalisation et comparaison bibliographique
```

`x8k`, `x8m`, `x8n` et la fermeture `x8q-x8t` sont volontairement laissés à la
curation suivante.

## Décisions principales

### x8a — DIAGNOSTIC

L'instrumentation mesure l'impulsion réellement appliquée par le kick Darcy
`forcingMode=mean`, à partir du même `lambda` float que le kernel. Elle permet le
bilan exact `DeltaP = I_body + I_Darcy + I_nonDarcyResidual`. Le gate est OFF par
défaut et n'introduit pas de paramètre physique.

### x8b — ANALYZER

Analyse exclusivement hors ligne des runs x8a. Elle compare GF-Q6 puis Q6-SRC et
conserve explicitement le terme restant sous le nom `non-Darcy residual` tant
qu'il n'est pas localisé.

### x8c — DIAGNOSTIC temporaire mais canonique

x8c est explicitement `disposable`: huit états du pas sont sondés pendant une
campagne courte, puis l'installer est retiré et la source restaurée. Le commit
`423b1c2dc4e0...` (`0493x8c stage_momentum removed`) atteste cette suppression.
La disparition du code d'instrumentation ne supprime pas l'étape historique.

### x8d — QUALIFICATION

Le chantier quitte la comparaison SRC/Q6 pour qualifier Q6-g-f contre des
solutions analytiques : Poiseuille avec parois physiques et Brinkman avec slab
`chi` périodique. Le cas Brinkman utilise volontairement `ell_B=4a` afin que la
couche de pénétration soit résolue.

### x8e — CALIBRATOR

Le microfluide x8d est recalibré en Q6-g-f par Taylor-Green sur quatre seeds via
le calibrateur x7n. La viscosité fraîche dimensionne ensuite un sweep
`ell_B/a=4,2,1,0.5`; `alpha=4000` est conservé comme endpoint de pénalisation
raide sous-résolu et non comme couche Brinkman résolue.

### x8f — BENCHMARK

Premier candidat von Kármán du cycle ouvert. Le solveur n'est pas modifié : le
runner gèle le microfluide x8e et combine inlet contrôlé, outlet Neumann passif,
parois no-slip, cylindre Brinkman, absence de force volumique et enregistrement
du sillage. Le README initial dimensionne un domaine 10D; le runner a ensuite été
édité localement pour des domaines plus longs.

### x8g — QUALIFICATION

Variante `io_fullface` vraie avec `balanced_flux`, utilisée pour isoler le bilan
de masse de la famille pleine-face sans introduire de nouvelle physique.

### x8h — INFRA

Restart hydrodynamique strictement validé contre params/chi/grille/dt et dérivé
du runner x8f courant. Il conserve l'origine globale des pas mais ne prétend pas
à une continuité RNG bitwise.

### x8i / x8j — séparation corrigée

Le référentiel initial attribuait à x8j « POD + sondes ». Les sources montrent
que cette fonction est celle de **x8i** : paire POD, phase, sondes, longueur
d'onde, convection et champs moyennés en phase sur les runs continués x8h.

**x8j** est l'analyseur suivant : nondimensionnalisation et comparaison dans les
conventions propres à Zovatto--Pedrizzetti et Sahin--Owens. Des révisions plus
tardives savent aussi consommer les diagnostics de flux x8n; cette extension
postérieure n'est pas utilisée pour déplacer l'introduction de x8j après x8n.

## Git

Les candidats `x8a`, `x8b`, `x8c` apparaissent dans le paquet du 14 août
`3bd07c80352e...`; `x8d` à `x8j` apparaissent dans le paquet du 15 août
`d0f4856e03d8...`. Ces commits sont des introductions groupées par chemins, pas
des preuves qu'un unique jalon composite devrait remplacer les labels séparés.

`x8c` possède en plus le sujet explicite de retrait `423b1c2dc4e0...`. La
curation lie les candidats X individuels à leurs jalons sans modifier le compteur
de réconciliation des candidats numériques.

## Effet attendu

V4.13 contient 205 jalons. V4.14 ajoute neuf jalons absents (`x8a` à `x8i`) et
corrige `x8j` sans le dupliquer : **214 jalons** attendus, **15 curations**.

La curation ne modifie aucun C++/CUDA ni runner du solveur. Le patch de transition
ne contient volontairement ni `Info/db/src_reference_dump.sql` ni
`Info/generated/*`; ces produits sont reconstruits localement par le builder.

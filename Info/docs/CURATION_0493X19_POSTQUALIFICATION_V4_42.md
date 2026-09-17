# V4.42 — fermeture de qualification x19 : transfert tangentiel, Couette courbe et rotor libre

Date : **17 septembre 2026**.

Cette curation ne modifie aucune physique runtime. Elle enregistre les résultats locaux finaux de la chaîne `x19a -> x19b -> x19c` et ferme le cycle de validation rotationnelle des solides mobiles lagrangiens.

## x19a — transfert tangentiel plan

Le cas Couette plan à paroi lagrangienne prescrite sépare le mode historique `specular` du nouveau mode `bounceback` dans le repère local de la paroi. Sur la fenêtre tardive `5000..15000` (11 dumps) :

- `specular` : erreur relative de profil `0.598073` ;
- `bounceback` : erreur relative `0.0379074` ;
- `bounceback` : `R2_shape = 0.984009`.

Le transfert tangentiel plan est donc qualifié. Cette étape n'est pas utilisée seule pour revendiquer une précision de couple sur géométrie courbe.

## x19b — cylindre prescrit et audit angulaire complet

Le diagnostic `x19b-fix3` mesure le même état fluide à 17 frontières d'opérateurs du pas de temps. Le bilan télescopique ferme à `1.804e-16` en relRMS et le changement de moment angulaire associé à x17 reproduit le compteur direct de paroi à `4.022e-14` en relRMS. Aucun canal non instrumenté n'est nécessaire pour expliquer la variation de moment angulaire du pas mesuré.

La viscosité de référence est obtenue indépendamment par quatre Taylor--Green appariés au fluide x19b (`src-q6`, `gamma=12`, `dt=0.006`, `kBT=0.05`, `alpha=pi/2`, `h=1/256`) :

| seed | nu | R2 | status |
|---|---:|---:|---|
| 4931911 | 2.4662014440e-4 | 0.99810082 | PASS |
| 5931911 | 2.2094221772e-4 | 0.99818492 | PASS |
| 6931911 | 2.3385957718e-4 | 0.99817356 | PASS |
| 7931911 | 2.3110358678e-4 | 0.99808664 | PASS |

Agrégat : `nu = 2.3313138152e-4`, `std = 1.0569841665e-5`, `SEM = 5.2849208326e-6`, `CV = 0.045339`.

Le run haute SNR `x19b-fix4`, `Omega=0.20`, donne :

- rayons effectifs `Ri=0.199976991`, `Ro=0.349989344` ;
- `rho2D=786521.317` ;
- couple tangentiel antisymétrique `T_C=29.9952367 +/- 0.752329` (block SEM) ;
- référence TG `|T|=27.3626194` ;
- biais relatif de couple `+9.62122%` ;
- demi-somme tangentielle commune `-3.20952218 +/- 1.82092` ;
- profil `relRMSE=0.0325029`, `R2=0.985311`, gain `0.976747` ;
- vitesse radiale normalisée `0.0180787`.

x19b est qualifié comme benchmark de paroi matérielle courbe imposée. Le biais de couple d'environ 10 % est conservé explicitement comme précision documentée de cette discrétisation, et non masqué par la curation.

## x19c — rotor libre, validation FSI end-to-end

Le rotor libre repart du champ établi de x19b-fix4. Le couple extérieur est fixé *a priori* à partir du couple hydrodynamique intérieur du run prescrit indépendant. Sur les steps `500..5000` (4501 lignes), avec `I=1976.51919` :

- fermeture mécanique : `relRMS=8.007e-15`, `maxAbs=2.753e-14` ;
- cross-check couple utilisé par le solide / compteur x17 : `relRMS=0` ;
- `Omega_mean=0.192093421 +/- 0.000948921` contre cible `0.2 +/- 0.0164399`, erreur relative `-3.95329%`, `z=-0.48014` ;
- couple hydro `-23.5995409 +/- 0.528601` contre référence x19b `-23.3998141 +/- 1.92345`, écart `-0.85354%`, `z=-0.100125` ;
- couple extérieur `+23.3998141` ; couple net `-0.199726735 +/- 0.528601`, compatible avec zéro ;
- première/dernière moitié : `Omega 0.193184329 -> 0.191002027`, couple net `-0.511574863 -> +0.112259993` ;
- pente `Omega/step=-8.889e-07` ;
- profil tardif `relRMSE=0.036046`, `R2=0.981934`, gain `0.956627`, `radial/Ui=0.0182496` ;
- gates `mechanics`, `omega`, `hydro`, `stationary`, `profile` : **PASS**.

La chaîne bidirectionnelle rotationnelle est donc qualifiée de bout en bout :

`impact cinétique -> impulsion de réaction -> couple généralisé -> intégration rigide -> Omega -> vitesse matérielle de paroi -> fluide`.

## Périmètre de la revendication

La validation analytique/quantitative couvre le **degré de liberté rotationnel d'un solide rigide lagrangien avec couplage FSI bidirectionnel**. Elle ne constitue pas encore une qualification analytique indépendante de la translation libre, des contacts/collisions entre solides ou du cas multi-solides.

Le biais de couple x19b `+9.62122%` et les erreurs de profil de l'ordre de `3--4%` restent documentés comme précision de la méthode sur ce benchmark.

## Reconstruction de la base

Après ajout de `0042_0493x19_postqualification.sql` :

```bash
python3 Info/scripts/build_src_reference.py --mainline-ref origin/surf
python3 Info/scripts/query_src_reference.py doctor
python3 Info/scripts/query_src_reference.py stats
python3 Info/scripts/query_src_reference.py milestone x19a
python3 Info/scripts/query_src_reference.py milestone x19b
python3 Info/scripts/query_src_reference.py milestone x19b-fix4
python3 Info/scripts/query_src_reference.py milestone x19c
```

La base SQLite est reconstructible et n'est pas à versionner ; `Info/db/src_reference_dump.sql` et `Info/generated/*` sont régénérés et versionnés selon la convention du dépôt.

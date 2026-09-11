# V4.30 — curation 0493x14aw → x14bc : benchmark Basilisk, diagnostics d'interface, pulse et liquide froid

## Objet

Cette curation applique la politique **evidence-driven** de l'annexe B du rapport de référence.
Elle documente exclusivement les objets explicitement attestés par les runners, patches, logs et
captures de la campagne du 11 septembre 2026.

Les jalons ajoutés sont exactement :

- `x14aw` — benchmark 2-D Basilisk ReL=500/WeG=200 à entrée moyenne;
- `x14ax` — recorder de la fraction liquide physique `alpha_x6c`;
- `x14ay` — ablation de raffinement particulaire gamma 12/16;
- `x14az` — affichage LiveVis direct de `alpha_x6c`;
- `x14ba` — oscillation sinusoïdale globale de vitesse d'entrée;
- `x14bc` — benchmark froid pulsé courant.

Aucun jalon `x14bb` ni `x14bb2` n'est créé. Le libellé `0493x14bb2` n'a servi qu'au répertoire de
calibration TG du liquide froid et ne constitue pas une identité documentaire autonome.

## Décisions scientifiques conservées

### Interface et gamma

Le diagnostic `alpha_x6c` a montré que la dentelure visible n'était pas seulement un artefact de
sous-échantillonnage LiveVis. Le passage de gamma=8 à gamma=12, avec masse et kBT redimensionnés
pour préserver `kBT/m`, n'a apporté qu'une amélioration faible face au surcoût particulaire. Cette
branche reste documentée comme ablation `x14ay`, mais n'est pas retenue comme fluide courant.

Le levier décisif est la réduction directe de l'agitation thermique liquide à gamma=8. Les smokes
`kBT_L=0.015625` puis `kBT_L=0.0078125` montrent qualitativement une régularisation progressive;
le second point est retenu.

### Calibration liquide froide

Le log exact archivé correspond à :

- path `src-q6-g-f`;
- gamma=8;
- alpha=90 deg;
- kBT=0.0078125;
- masse=1;
- h=1/256;
- dt=0.00635;
- TG 128x128, mode (2,2), amplitude 0.05, T=4.0;
- 8 graines.

Résultat :

```text
status=PASS
viscosity=PASS
nu=0.0002122268985
std=4.705e-06
CV=0.022
```

Le gaz garde la référence existante `nu_G=0.0003536191886`. Le ratio `nu_G/nu_L≈1.67` est accepté
comme même ordre de grandeur pour le régime exploratoire; aucune égalité stricte n'est revendiquée.

### Pulse x14ba

La loi globale est

```text
Fosc(t) = 1 + A sin(2*pi*(t + offset - start)/T + phase)
```

et multiplie le facteur de ramp préexistant. Elle est appliquée de façon cohérente aux injections
particulaires et aux flux Q6 host/CUDA. Les six clés canoniques sont :

```text
inletVelocityOscillationEnable
inletVelocityOscillationAmplitude
inletVelocityOscillationPeriod
inletVelocityOscillationPhase
inletVelocityOscillationStartTime
inletVelocityOscillationTimeOffset
```

Les alias courts `inletOscillation*` sont acceptés. Le chemin désactivé est strictement neutre.
`timeOffset` maintient la phase sur restart.

### Runner x14bc

Le cas courant fixe par défaut :

```text
Re_L=500
We_G=200
rho_L/rho_G=27.84
D/h=96
domain=18D x 18D
gamma=8
kBT_L=0.0078125
nu_L=0.0002122268985
kBT_G=0.00575
nu_G=0.0003536191886
St=5/3
A/U=0.05
```

D'où environ `U=0.282969198`, `sigma=2.827354642`, `Re_G≈300`, période `≈0.79514`, soit
`≈125.2` pas. Le smoke pulsé 300 pas est attesté comme smoke d'intégration/visualisation, pas comme
qualification statistique de breakup.

Le run long prévu est 4758 pas avec dumps restart tous les 1000 pas et `ALLOW_LARGE_DUMPS=1`.
Pour résoudre la phase du pulse, la campagne retient un recording tous les 25 pas. Son coût local est
de l'ordre de deux heures : la stratégie devient un **seed long de référence** et une analyse temporelle
repliée sur la phase, sans prétendre remplacer une incertitude inter-seed.

## Inventaires V4.30

Le snapshot paramètres actif devient :

`Info/inputs/snapshots/src_mpcd_params_inventory_snapshot_110926_x14bc.csv`

Il reprend V4.29, étend les valeurs LiveVis/recorder avec `alpha_x6c` et ajoute les six clés solveur
x14ba.

Le snapshot ENV actif devient :

`Info/inputs/snapshots/src_mpcd_env_flags_inventory_snapshot_110926_x14bc.csv`

Il reprend V4.29 et ajoute les contrôles documentés de similarité, pulsation, géométrie, références de
transport, gros dumps/restarts, design-only et recording utilisés par x14aw/x14ay/x14bc.

## Provenance

Source narrative :

`Info/inputs/historical/README_0493X14AW_X14BC_BASILISK_COLD_20260911.md`

Archive binaire :

`Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip`

SHA-256 :

`7e06184d9ba1130147579d92d2bf6bf6d5bca2f6718c361e378632734759376b`

L'archive contient les packages exacts x14ax/x14ay/x14az/x14ba/x14bc, le runner x14aw, le log TG128,
les captures qualitatives sélectionnées et un manifest SHA-256 interne.

## Validation attendue

Conformément à l'annexe B, le patch de curation est **source-only**. Il ne doit contenir ni
`Info/generated/*`, ni `Info/db/src_reference_dump.sql`, ni code C++/CUDA, ni runner racine, ni
`livevis_control.kv`.

Après application sur le checkout réel :

```bash
python3 -m py_compile \
  Info/scripts/build_src_reference.py \
  Info/scripts/publish_src_reference.py \
  Info/scripts/query_src_reference.py

git diff --check
python3 Info/scripts/build_src_reference.py --mainline-ref origin/surf
python3 Info/scripts/query_src_reference.py doctor
python3 Info/scripts/query_src_reference.py stats

python3 Info/scripts/query_src_reference.py milestone x14aw
python3 Info/scripts/query_src_reference.py milestone x14ax
python3 Info/scripts/query_src_reference.py milestone x14ay
python3 Info/scripts/query_src_reference.py milestone x14az
python3 Info/scripts/query_src_reference.py milestone x14ba
python3 Info/scripts/query_src_reference.py milestone x14bc
python3 Info/scripts/query_src_reference.py param inletVelocityOscillationEnable
python3 Info/scripts/query_src_reference.py param inletVelocityOscillationTimeOffset
python3 Info/scripts/query_src_reference.py search "alpha_x6c"
```

Une reconstruction isolée sur la préimage V4.29 a validé les compteurs structurels suivants :

```text
reference_version=V4.30
milestones=298
raw_params_inventory=860
raw_env_inventory=580
curations_applied=29
published_milestones=298
published_params=320
published_flags=679
quick_check=ok
foreign_key_violations=0
publication_missing_docs=0
```

Par rapport à V4.29, les deltas attendus sur ces compteurs sont donc `+6` jalons, `+6` lignes
paramètres, `+31` lignes ENV, `+1` curation, `+6` paramètres publiés et `+29` flags publiés.
Les compteurs Git, artefacts, relations et preuves doivent en revanche être relus sur le checkout réel :
ils dépendent du contenu Git et de la présence effective des nouveaux runners/patches dans l'arbre.

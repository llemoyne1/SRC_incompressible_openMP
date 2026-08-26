# 0491h-fix1 — qualification approfondie Q6 multi-espèces

Base gardée : `a30faac` (`Q6 species sensitive`).

Cette étape ne modifie pas la dynamique Q6. Elle durcit exclusivement la
qualification logicielle et numérique de l'objectif 0491h.

## Motivation

L'audit externe de la campagne 0491h a confirmé la correction barycentrique,
la convergence Q6 et les deux runs longs. Il a aussi mis en évidence plusieurs
angles morts :

1. la matrice précédente activait le resampling générique, mais pas les options
   0490p de resampling multi-espèces résident dans les chemins
   `SRC+resampling` et `SRC+resampling+Q6` ;
2. l'équivalence directe entre Q6 historique et `speciesQ6Mode=common` n'était
   pas comparée sur l'état particulaire final ;
3. le run long combiné était ouvert et ne permettait pas de conclure seul sur
   la conservation globale des masses par espèce ;
4. l'interface n'était suivie qu'avec des masses globales ;
5. l'espèce trace avait une fraction trop élevée et un coefficient Q6 nul ;
6. les nombres exacts de lignes/pas et les performances common/weighted
   n'étaient pas contrôlés sur des cas strictement appariés.

## Nouveaux fichiers

- `scripts/generate_0491h_fix1_state.py`
- `scripts/run_0491h_fix1_deep_qualification.sh`
- `scripts/summarize_0491h_fix1_deep_qualification.py`

## Campagne `full`

### Matrice des quatre chemins

Trois graines et 1000 pas pour chacun des chemins :

- `SRC` ;
- `SRC+resampling` ;
- `SRC+Q6` ;
- `SRC+resampling+Q6`.

Les deux chemins avec resampling activent explicitement :

- fermeture massique multi-espèces 0490i ;
- garde de population multi-espèces 0490j ;
- plan de transfert typé 0490k ;
- fast path résident 0490m ;
- dépôts et pool résidents 0490n ;
- politique cellulaire GPU 0490p ;
- maintenance stricte sans portée CPU résiduelle ;
- refill vide activé uniquement dans les chemins avec resampling, condition
  nécessaire au refill de composition multi-espèces 0490f.

L'état initial alterne des cellules pauvres et riches afin que les opérations
de split/merge/transfert soient réellement exercées.

### Équivalence Q6 historique / common

Deux runs partent du même état, avec la même graine :

- `speciesQ6Enable=false` ;
- `speciesQ6Enable=true`, `speciesQ6Mode=common`.

Les dumps finaux sont comparés composante par composante : positions,
vitesses, masses, types et rôles. Le SHA-256 exact est également rapporté.

### Performance appariée common / weighted

Un troisième run utilise exactement le même état et la même graine avec
`speciesQ6Mode=weighted`. Le surcoût est calculé après exclusion du warm-up et
est borné par défaut à 25 %.

### Interface spatiale

Une interface verticale liquide/gaz est soumise à un écoulement tangentiel et
suivie avec `speciesCellDiagnosticsEnable=true`. Le résumeur calcule :

- contraste liquide gauche/droite initial et final ;
- rétention du contraste ;
- pureté cellulaire moyenne ;
- bornes de `alphaBar` et des poids reconstruits ;
- nombre de cellules utilisant le fallback common.

### Espèce trace réelle

Une troisième espèce est introduite à une fraction massique globale
`1e-7` par défaut, avec un coefficient Q6 non nul (`4.0`). Le test vérifie :

- fraction massique <= `1e-6` ;
- conservation de masse sur tous les échantillons ;
- maintien de l'unique particule trace ;
- poids Q6 reconstruit fini et supérieur à un ;
- résidu barycentrique sous tolérance.

### Run long fermé combiné

Un run périodique fermé de 10000 pas utilise
`SRC+resampling+Q6 weighted` avec toute la chaîne 0490p. Il vérifie :

- 10000 lignes Q6 exactement ;
- convergence à chaque pas ;
- conservation des masses par espèce sur tous les échantillons ;
- politique cellulaire résidente ;
- opérations de resampling effectivement non nulles ;
- absence de fallback CPU ou téléchargement complet déclaré.

## Profils

- `VALIDATION_PROFILE=software` : smoke court ;
- `VALIDATION_PROFILE=full` : qualification complète décrite ci-dessus.

## Commande recommandée

```bash
LIVE_PROGRESS=1 \
BIN=build/src_mpcd_base_cuda_q6_resident_livevis_0486 \
VALIDATION_PROFILE=full \
RUN_ROOT=runs/0491h_fix1_deep_qualification \
bash scripts/run_0491h_fix1_deep_qualification.sh \
2>&1 | tee run_0491h_fix1_deep_qualification.log
```

## Critère de clôture

Le résumeur renvoie `PASS` uniquement si tous les contrôles sont validés. Les
résultats consolidés sont écrits dans :

- `species_q6_deep_qualification_0491h_fix1.csv` ;
- `species_q6_deep_qualification_0491h_fix1.md`.

Les transferts répétés des métadonnées d'espèces et le précalcul de `alphaBar`
restent volontairement hors périmètre : ils relèvent de l'étape de performance
0491i, pas de 0491h-fix1.

## 0491h-fix1b — incompatibilité 0296 / fermeture multi-espèces

La qualification approfondie a exposé une incompatibilité antérieure à Q6 :
le reconditionnement générique 0296 homogénéise les masses de toutes les
particules d'une cellule sans distinguer leur `type`. Après les split/merge
dirigés par espèce de 0490j, il peut donc conserver la masse cellulaire totale
tout en transférant artificiellement de la masse entre espèces.

Le correctif applique deux protections complémentaires :

1. les chemins multi-espèces stricts du runner fixent explicitement
   `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0` ;
2. le code supprime automatiquement 0296 lorsque la fermeture massique
   multi-espèces 0490d/0490i est activée, et écrit une fois le marqueur :

   ```text
   [0491h-fix1b] suppressed cuda_resampling_mass_recondition_0296: incompatible with species-aware mass closure (0490d/0490i)
   ```

La campagne ajoute aussi `mass_recondition_compatibility_guard`, un cas qui
force volontairement 0296 avec la chaîne 0490p. Le résumeur exige alors :

- demande 0296 effectivement active dans l'environnement ;
- marqueur de suppression présent ;
- aucune ligne de diagnostic 0296 produite ;
- conservation de chaque masse d'espèce sur tous les échantillons ;
- politique cellulaire GPU stricte ;
- opérations de resampling non nulles.

0296 reste disponible et inchangé pour les chemins mono-espèce ou génériques
qui n'activent pas la fermeture massique multi-espèces.

## 0491h-fix1c: scale-aware barycentric guard and bounded long runs

The original CUDA guard compared the dimensional recomposition residual
`|sum_s M_cs w_cs du_c - M_c du_c|` directly with a fixed absolute tolerance.
That is appropriate while corrections are O(1), but it becomes a false strict
failure when an intentionally extreme weighted composition creates very large
corrections: cancellation remains at machine precision while the absolute
round-off grows with `M_c |du_c|`.

0491h-fix1c retains the absolute diagnostic and adds the mixed absolute/relative
quantity

```text
r_scaled = |r| / max(1, |M_c du_c| + sum_s |M_cs w_cs du_c|).
```

`speciesQ6ComparisonTolerance` is applied to `r_scaled`. Therefore the legacy
absolute requirement is unchanged below unit scale, while large corrections are
judged by their relative recomposition error. The species-Q6 CSV records both
`barycentricResidualMaxAbs` and `barycentricResidualMaxScaled`.

The deep campaign now enables the resident cell-relative thermostat by default
(`THERMOSTAT_ENABLE=true`). This is not an algorithmic damping patch: an
eta=1, alpha_gas=0 mixture can deliberately apply all of the barycentric Q6
correction to a small liquid mass fraction, injecting species-relative kinetic
energy if it is repeated without thermal control. Long 1000/10000-step
qualification therefore validates the intended resident Q6+thermostat path and
checks the thermostat error at every recorded step. Set
`THERMOSTAT_ENABLE=false` only for short diagnostic probes.
## 0491h-fix1d — resident Q6 thermostat diagnostics

The resident Q6 thermostat now mirrors the eligibility rule used by the generic CUDA thermostat when constructing diagnostics. A cell contributes when `count >= thermostatMinParticles` and `cellKinetic > thermostatEpsilon`, even when its computed scale is exactly `1.0`.

Previously, the resident path inferred eligibility from `scale != 1.0`. This excluded already-on-target eligible cells from `dofTotal` while the CUDA reduction still included their target energy, inflating `thermostatKBTAfter` by the ratio between all eligible cells and only non-unit-scale cells. The fix downloads the compact per-cell kinetic array for diagnostics and removes that ambiguity; particle updates and thermostat physics are unchanged.



## 0491h-fix1e — long-horizon legacy/common equivalence

The historical Q6 and `speciesQ6Mode=common` paths are required to keep the
particle count, type, role and mass arrays exactly identical. Position and
velocity comparisons remain strict but use a horizon-aware absolute tolerance:

- `software` (20 steps): `1e-13`;
- `full` (1000 steps): `1e-9`.

This distinction avoids treating accumulated floating-point roundoff as an
algorithmic divergence after 1000 nonlinear collision/streaming iterations.
The full-profile threshold is still much tighter than the observed physical
velocity scale and the report exposes the position/velocity error divided by
the accepted tolerance. SHA identity is reported but is not a qualification
requirement.

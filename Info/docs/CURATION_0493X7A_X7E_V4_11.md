# Curation V4.11 — x7a à x7e : restauration de densité Q6-g-f

## Correction du canon rétrospectif

Le référentiel initial regroupait `x7a/x7b` sous une seule entrée d'ablation et omettait `x7c`. Les patches historiques montrent au contraire une séquence à cinq étapes. V4.11 supprime donc uniquement l'objet canonique agrégé `reference:x7a/x7b` (la ligne brute du snapshot reste conservée), crée `x7a`, `x7b` et `x7c`, puis consolide `x7d` et `x7e`.

Le nombre de jalons passe de 197 à 199 : `-1` agrégat, `+3` jalons réels.

## Chaîne causale

- **x7a — kick viriel CUDA résident** : première restauration explicite de densité après la projection, dans le bulk liquide, avec correction optionnelle du moment net.
- **x7b — sémantique continue du viriel** : patch explicitement sémantique/diagnostique; `kVirial` devient une raideur continue en unités de vitesse au carré, indépendante du maillage à domaine physique fixé, et la calibration K32 est documentée.
- **x7c — relaxation intégrée au RHS** : le mécanisme retenu quitte le kick post-projection et impose directement `div(u_proj)=beta*(rawFill-1)/dt` dans le bulk. Le kick viriel et le RHS densité sont mutuellement exclusifs.
- **x7d — constante de temps physique** : l'opérateur x7c est inchangé mais `tau_rho` devient l'entrée physique préférée, avec `betaPerStep=dt/tau_rho`; la campagne coarse/fine conserve `tau_rho=0.25` à temps physique égal.
- **x7e — qualification x6g+x7d** : aucune modification CUDA; pression gaz interfaciale et restauration de densité bulk sont assemblées additivement dans le même RHS et le même solve CG, puis qualifiées ensemble.

```text
x6h-B1 -> x7a -> x7b -> x7c -> x7d
                         |       |
                         |       +----+
                         |            v
x6g ---------------------+----------> x7e
```

`x7a/x7b` restent importants comme ablation historique, mais la stratégie Q6-g-f retenue est le RHS x7c/x7d. `x7e` qualifie sa composition avec la pression gaz x6g.

## Provenance

Les cinq patches historiques sont conservés sous `Info/inputs/historical/`. Les copies `.patch` sont normalisées uniquement sur les espaces horizontaux de fin de ligne; les octets d'origine sont préservés dans `0493x7a_x7e_original_patches.zip` avec manifeste SHA-256.

Aucun SHA Git n'est forcé par cette curation : les candidats X sont liés s'ils existent réellement dans les sujets/chemins Git, sinon les patches historiques restent une preuve primaire de confiance A.

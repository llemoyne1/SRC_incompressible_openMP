# Curation V4.10 — 0493x6h-A / B0 / B1

V4.10 consolide les trois jalons déjà présents dans le référentiel rétrospectif sous une chaîne causale documentée par leurs patches historiques. Aucun jalon supplémentaire n'est créé.

## Chaîne causale

- **x6h-A — correctif des faces physiques basses** : le stockage FV conserve les corrections des faces est/nord dans leur cellule propriétaire. Sur les frontières physiques ouest/sud non périodiques, aucune cellule propriétaire voisine n'existe. A reconstruit ces corrections par la même convention `target-before` que les faces hautes, uniquement lorsque le `pressureMask` est actif.
- **x6h-B0 — diagnostic post-application** : après application de la correction aux particules et redépôt, un audit sparse classe la divergence dans six régions (`bulk`, `interface`, `wall`, `wall_interface`, `corner`, `corner_interface`). Il est strictement observationnel et OFF dans la production.
- **x6h-B1 — reconstruction RT0/MAC face-vers-particule** : l'incrément cellulaire constant est remplacé par une interpolation affine entre les corrections des deux faces opposées. La reconstruction possède la même divergence discrète que le champ FV projeté. Dans le premier chemin qualifié, une seule espèce liquide est projetée et les buffers de faces existants sont consommés directement, sans nouvelle passe particulaire.

La chaîne retenue est donc :

```text
x6g -> x6h-A -> x6h-B0 -> x6h-B1
          \__________________/
             faces cohérentes
```

B0 reste un diagnostic, non une étape de production. B1 est le mécanisme retenu dans le profil Q6-g-f; les jalons x7 ultérieurs étendront et fermeront quantitativement ce mécanisme, notamment en domaine périodique.

## Provenance

Les trois patches d'origine sont copiés sous `Info/inputs/historical/` afin que la justification des jalons soit reconstructible depuis la base documentaire elle-même :

- `0493x6h_patchA_low_wall_face_reconstruction.patch`
- `0493x6h_b0_postapply_region_diagnostic.patch`
- `0493x6h_b1_rt0_face_to_particle.patch`

Ils sont enregistrés comme preuves `HISTORICAL_PATCH` de confiance A.

Les fichiers `.patch` lisibles sont normalisés uniquement par suppression des espaces horizontaux de fin de ligne afin de préserver `git diff --check`. Les octets originaux sont conservés sans transformation dans `0493x6h_original_patches.zip`; `0493x6h_original_patches.sha256` donne leurs SHA-256 avant normalisation.

# Curation V4.15 — 0493x8k à 0493x8t

## Frontière retenue

V4.15 reconstruit la seconde moitié du cycle 0493x8, depuis la correction sémantique de l'inlet segmenté `x8k` jusqu'à la fermeture passive Neumann complète `x8t`.

La chaîne n'est pas une suite alphabétique exhaustive. Les identités autonomes attestées sont :

```text
x8k -> x8l -> x8m -> x8n
        |
        +-> x8q -> x8r -> x8s -> x8t
```

Aucune preuve autonome n'a été trouvée pour `x8o` ou `x8p`; ces labels ne sont donc pas inventés.

`x8u` est volontairement hors de cette curation : son updater aligne le runner restartable `x8m` sur les BC déjà validées `x8q-x8t`. Il appartient à l'étape suivante de réintégration/production, pas à la construction de la fermeture elle-même.

## Décisions canoniques

### x8k — CODE

`x8k` définit la coordonnée locale d'un segment

```text
eta = (s-sMin)/(sMax-sMin)
```

et le profil `u_n=4 Umax eta(1-eta)` de manière cohérente entre injection particulaire et cible Q6-g-f. Le runner de qualification utilise un inlet partiel afin que la localité au segment soit observable. Son `UOUT` n'est qu'un pont temporaire de bilan de flux.

### x8l — CODE, nouveau jalon

`x8l` introduit la première sémantique passive de l'outlet segmenté Q6-g-f : la vitesse de face prédicteur copie la vitesse de la cellule de bord, donc `du/dn=0` au niveau de la vitesse de base. Cette étape est réelle et indépendante même si sa condition elliptique est ensuite corrigée par `x8r`.

### x8m — BENCHMARK, nouveau jalon

`x8m` matérialise le cas de production Zovatto-Pedrizzetti à `Re_H=280`, avec profil de Poiseuille pleine hauteur, cylindre confiné, enregistrement de champs et restart. Le label couvre la lignée du domaine réduit de développement puis du domaine bibliographique complet. Son outlet historique initial est `x8l`; l'alignement ultérieur sur `x8t` est `x8u`.

### x8n — ANALYZER, nouveau jalon

`x8n` est un diagnostic hors ligne du benchmark `x8m`. Il reconstruit par section `Ub`, `Qv`, `rhoBar`, `Mrho`, `Jrho` et `Urho` afin de séparer accommodation de l'inlet, variation de densité et dérive de flux. Aucun état n'est modifié.

### x8q — CODE

La première version de `x8q` complète la sortie Neumann au niveau particulaire. Les sous-révisions successives testent plusieurs reconstructions. La forme retenue `x8q-fix4` n'est plus une copie particule-à-particule auto-excitante : elle construit un bain maxwellien local à partir des moments pré-stream des deux couches intérieures et échantillonne le demi-espace entrant avec pondération de flux normal.

Les suffixes `x8q-fix1...fix4` restent des sous-révisions du même jalon physique et ne gonflent pas le canon.

### x8r — CODE

`x8r` identifie le défaut de `x8l` : réutiliser `u*_cell` comme cible de projection au pas suivant crée un ratchet de vitesse. Il conserve l'extrapolation de vitesse `u*_out=u*_cell`, mais impose `phi_out=0` à la face de sortie. L'outlet devient ainsi une vraie référence de pression passive.

### x8s — PERF

Le problème mixte créé par `x8r` est mal conditionné dans les canaux longs. `x8s` résout exactement les trois modes longitudinaux les plus lents avant le CG et démarre sur un résidu orthogonal. L'équation, la tolérance et la physique de sortie ne changent pas.

### x8t — CODE

Avec une vraie sortie de pression, le mode constant du RHS devient solvable. Le gate signé de relaxation de densité peut alors injecter une petite moyenne non nulle. `x8t` soustrait uniquement cette moyenne lorsque `fullDomain + x8r + density relaxation` sont actifs, en conservant la redistribution locale signée.

## Candidat Git agrégé x8q-x8t

L'audit Git contient un candidat A `x8q-x8t` porté par des sujets de commit de consolidation. Il n'est pas promu comme jalon composite : les patchers primaires établissent quatre identités fonctionnelles distinctes `x8q`, `x8r`, `x8s`, `x8t`. Le candidat agrégé reste donc une preuve de consolidation, comme `x7k-x7l` dans V4.12.

## Cardinalité attendue

V4.14 contient 214 jalons. V4.15 ajoute seulement :

- `x8l`;
- `x8m`;
- `x8n`.

`x8k`, `x8q`, `x8r`, `x8s`, `x8t` existaient déjà et sont consolidés.

Résultat attendu : **217 jalons**, **16 curations**.

## Conservation des sources

Les copies lisibles sont placées sous `Info/inputs/historical/`. Les octets originaux sont conservés dans `0493x8k_x8t_original_sources.zip` et vérifiés par `0493x8k_x8t_original_sources.sha256`.

Le patch V4.15 est source-only : il ne contient ni `Info/db/src_reference_dump.sql` ni `Info/generated/*`. Ces produits sont reconstruits localement par `build_src_reference.py` sur le dépôt Git réel.

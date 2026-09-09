# Curation V4.16 — 0493x8u puis 0493x9a à 0493x9h

## Frontière

V4.16 adopte volontairement une granularité plus large afin d'accélérer la fin de la reconstruction. Elle ne fusionne toutefois aucun jalon : elle ferme x8 avec `x8u`, puis traite en un seul paquet documentaire le premier bloc physiquement cohérent du cycle capillaire x9.

La frontière aval est `x9h`. `x9i` et les étapes suivantes introduisent les prototypes de mouillage/angle de contact et constituent un changement de problème suffisamment net pour la curation suivante.

## Clôture x8 : x8u

`x8u` ne change pas C++/CUDA. Son updater modifie le runner restartable x8m afin de remplacer les métadonnées/contrats `passive_x8l` par la fermeture `kinetic_pressure_x8t`, rendre le mode de run surchargeable et activer un bruit thermique d'inlet paramétrable (défaut 1.0). Il est donc canonisé comme `INFRA`, pas comme nouvelle physique d'outlet.

## Géométrie passive x9a-x9c

- **x9a — DIAGNOSTIC** : premier champ résident normal/courbure à partir de l'alpha physique x6c; aucun sigma ni changement de `phiGamma`.
- **x9b — DIAGNOSTIC** : champ de courbure auxiliaire obtenu par une passe binomiale 3x3 puis Scharr; l'interface physique reste alpha_x6c=0.5. Le Hessien direct testé n'est pas retenu. `x9b-audit2` reste une sous-révision diagnostique.
- **x9c — QUALIFICATION** : sweep p1/p2/p3 à opérateur Scharr fixe; la chaîne de production retient trois passes binomiales (p3) pour la courbure utilisée ensuite par x9d.

Ces trois identités existaient comme candidats Git B mais manquaient du canon. Elles sont ajoutées et reliées sans prétendre que le commit groupé `7c073214...` est leur commit d'introduction individuel.

## Capillarité active et diagnostics x9d-x9f

- **x9d — CODE** : premier `surfaceTensionSigma`; ajoute à la valeur interfaciale Q6 le terme `dt/rho_ref * sigma*kappa_p3`. `sigma=0` reste un no-op exact. Il n'y a ni force CSF volumique ni kick particulaire.
- **x9e — DIAGNOSTIC** : mesure Reff, pression Q6/jauge x6g, saut de pression, résultante capillaire et vitesses parasites, sans modifier la physique x9d.
- **x9f — DIAGNOSTIC** : remplace la bande diagnostique alpha 0.1-0.9 par la vraie bande de crossings alpha=0.5 et ajoute COM particulaire, tenseur de moments, axes/ellipticité et rayons d'interface. L'ancienne description « quadrupole signé » était trop restrictive et est corrigée.

## Abstraction A/B et paroi x9g-x9h

- **x9g — CODE** : généralise la chaîne historique Liquid/Gas en sélection A/B. A est alpha-high/projeté; B est extérieur. Les formes `family:*`, `type:N` et `vacuum` sont opérationnelles selon leurs gardes. La qualification vérifie l'équivalence du cas legacy. Commit explicite : `240c2e6e...`.
- **x9h — CODE** : active `B=wall` comme provider géométrique seulement, en combinant parois du domaine et chi opt-in wallVP (`S=1-chi`). Il n'impose encore ni angle de contact, ni saut de Laplace liquide/solide, ni nouvelle BC Q6 de paroi. Commit explicite : `3c78e280...`.

## Cardinalité

V4.15 contient 217 jalons. V4.16 ajoute seulement :

- x8u;
- x9a;
- x9b;
- x9c.

Les x9d-x9h existants sont consolidés. Total attendu : **221 jalons**, **17 curations**.

## Packaging

Le patch est source-only : pas de `Info/db/src_reference_dump.sql`, pas de `Info/generated/*`. Les neuf preuves historiques lisibles sont versionnées sous `Info/inputs/historical/`; leurs octets exacts sont également regroupés dans `0493x8u_x9a_x9h_original_sources.zip` avec manifeste SHA-256.

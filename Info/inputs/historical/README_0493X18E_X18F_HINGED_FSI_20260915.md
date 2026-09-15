# Sources historiques 0493x18e / 0493x18f — 15 septembre 2026

Cette archive conserve les deux packages exacts utilisés pour la fermeture du chantier du volet articulé ainsi qu'un relevé de validation opérateur.

Contenu principal :

- `0493x18e_hinged_fsi_subcycling_150926.zip` — sous-cyclage FSI local du volet et gardes anti-hang ;
- `0493x18f_hinged_open_boundaries_final_150926.zip` — runners x18a/x18b à frontières ouvertes, intégration permanente de l'initialisation x18a-fix2 et extension outlet-only Neumann sur le chemin Q6 résident ;
- `OPERATOR_VALIDATION_0493x18e_x18f_150926.txt` — compilation/runs locaux et mesures de bilan de population du double-Neumann ;
- `MANIFEST_SHA256.txt` — empreintes internes.

SHA-256 de l'archive historique :

`3dc97a4cb7a5a6114c2fe756c7c05b4fc72d7861a76a6a215682d06b90d9eeb5`

Le package `0493x18f-fix1` de verrouillage global de population n'est volontairement pas inclus dans les sources canoniques : il n'a pas été appliqué et la stratégie n'est pas retenue comme sémantique générale des frontières ouvertes. Une CL ouverte peut physiquement produire un bilan de masse non nul ; un éventuel contrôleur global doit rester explicite et optionnel.

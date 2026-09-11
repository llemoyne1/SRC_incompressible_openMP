# Publication V4 — vues humaines de la base SRC_GPU-SURF

La V4 ajoute une couche de publication automatique sous `Info/generated/`.
Ces fichiers ne constituent **jamais** des sources de vérité indépendantes : ils sont
régénérés depuis `Info/db/src_reference.sqlite` à chaque reconstruction normale.

## Politique de publication

- `milestones` est la seule source des jalons canoniques publiés dans `jalons.md`.
- `git_milestone_candidates` reste un backlog d'audit ; il est publié séparément dans
  `audit_candidats_git.md` et n'est jamais promu implicitement.
- les paramètres sont publiés à partir de `symbols(namespace='PARAM')`, donc une même
  notion n'est pas dupliquée parce qu'elle possède un champ C++, une clé `.kv` et des alias ;
- les variables d'environnement / aliases runners sont publiés séparément depuis
  `symbols(namespace='ENV')` ;
- les CSV de `Info/generated/csv/` sont des exports générés pour tri/inspection, pas des
  tables à modifier manuellement.

## Documents générés

```text
Info/generated/
├── README.md
├── lexique_jalons.md
├── jalons.md
├── jalons_par_nature.md
├── parametres.md
├── flags.md
├── cles_controle_sorties.md
├── artefacts.md
├── audit_candidats_git.md
└── csv/
    ├── lexique_jalons.csv
    ├── jalons.csv
    ├── parametres.csv
    ├── flags.csv
    ├── artefacts.csv
    └── candidats_git.csv
```


## Lexique de consultation rapide

`lexique_jalons.md` est une vue compacte, exhaustive et triée naturellement des jalons
canoniques. Elle est destinée à répondre rapidement à des questions comme « que signifie
`x10e` ? » sans ouvrir la fiche détaillée de `jalons.md`.

Colonnes publiées :

- **Jalon** — identifiant humain ;
- **Famille** — groupe court (`0490`, `x10`, `x14`, etc.) ;
- **Type / support** — forme concrète déduite des artefacts et de la source primaire
  (`modification code`, `runner`, `analyseur`, `calibrateur`, `générateur`, etc.) ;
- **Nature** — classification canonique (`CODE`, `FIX`, `ABLATION`, `QUALIFICATION`, etc.) ;
- **Fonction** — résumé fonctionnel canonique ;
- **Statut** — portée actuelle/historique/qualifiée/supplantée.

Le tri utilise une clé naturelle : `x9z < x10a`, `x7d-fix2 < x7d-fix10`. Le CSV
`csv/lexique_jalons.csv` conserve en plus la clé unique, l'ID canonique, le domaine et le nom long.

Le glossaire manuel `Info/docs/GLOSSAIRE_SIGLES.md` est volontairement séparé des vues
générées : les développements d'acronymes et conventions scientifiques demandent une curation
humaine et ne doivent pas être inférés automatiquement depuis les noms de symboles.

## Reconstruction

La commande normale :

```bash
python3 Info/scripts/build_src_reference.py --mainline-ref origin/surf
```

reconstruit maintenant dans une même opération :

1. la base SQLite temporaire ;
2. le dump SQL temporaire ;
3. toutes les vues de publication dans un répertoire temporaire ;
4. les contrôles d'intégrité ;
5. puis le remplacement groupé et rollback-capable des trois produits.

Une erreur de publication n'installe donc ni nouvelle base ni documents partiellement
mis à jour.

Pour un audit exceptionnel de la base sans modifier les vues :

```bash
python3 Info/scripts/build_src_reference.py --mainline-ref origin/surf --no-publish
```

Pour republier seulement à partir d'une base déjà valide :

```bash
python3 Info/scripts/publish_src_reference.py
```

## Nettoyage du bruit Git

Le référentiel consultable et le backlog Git sont séparés volontairement. Les candidats
A/B/C peuvent être nombreux et contiennent encore de la matière historique à curer.
Le Markdown d'audit développe seulement :

- les candidats déjà reliés au canon ;
- les candidats A non curés ;
- les candidats B à signal fort (plusieurs preuves ou commit unique hors mainline).

Le CSV `candidats_git.csv` conserve l'inventaire complet.

## Extension V4.1 — promotion historique contrôlée

La curation `0002_0490_multispecies_resampling.sql` illustre le flux de promotion : le
jalon est créé explicitement dans `milestones`, puis Git ne sert qu'à compléter sa
provenance. Un candidat numérique n'est relié automatiquement que si son label est unique
des deux côtés. Cette règle permet de faire disparaître les 0490 curés du backlog non
résolu sans réintroduire la collision historique des labels comme `0414`.

## V4.27 — réintégration après cherry-pick

La restauration des curations Neumann V4.22/V4.23 et l'ajout de la lignée x9e sont des
modifications des sources documentaires, pas des fichiers publiés. Une reconstruction
normale régénère `jalons.md`, `jalons_par_nature.md`, `lexique_jalons.md`, les CSV,
l'audit Git et les inventaires à partir du nouveau `surf`. Le lexique attendu contient
292 lignes de jalons canoniques.

## V4.29 — inventaires courants et ordre naturel

Le snapshot paramètres actif est rafraîchi au 10 septembre 2026. Il est byte-identique au
snapshot x14ai du 4 septembre, ce qui matérialise l'audit concluant à **zéro nouvelle clé `.kv`**
dans la lignée Neumann. Le snapshot ENV x9e-fix3 reste actif avec 549 entrées brutes.

Les publications de paramètres et de flags sont triées par clé naturelle sur le nom canonique.
L'index `jalons_par_nature.md` trie désormais les identifiants naturellement dans chaque nature,
ce qui évite par exemple de placer `x14*` avant `x10*` pour des raisons d'ordre de curation.
Les nombres attendus restent 292 jalons, 314 paramètres canoniques et 650 flags.

## V4.30 — benchmark x14aw→x14bc et inventaires associés

V4.30 est une curation scientifique/documentaire réelle : six jalons explicitement attestés sont
ajoutés et les inventaires actifs sont rafraîchis. Le snapshot paramètres ajoute les six clés
`inletVelocityOscillation*` de x14ba et étend les valeurs documentées de `field`/`recordFields`
avec `alpha_x6c`. Le snapshot ENV ajoute les contrôles propres aux runners Basilisk, à la pulsation,
aux gros dumps/restarts et au recording de campagne.

Les publications `Info/generated/*` et le dump SQL ne font pas partie du patch source-only; ils
doivent être régénérés par `build_src_reference.py` sur le checkout réel après application.

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
├── jalons.md
├── jalons_par_nature.md
├── parametres.md
├── flags.md
├── cles_controle_sorties.md
├── artefacts.md
├── audit_candidats_git.md
└── csv/
    ├── jalons.csv
    ├── parametres.csv
    ├── flags.csv
    ├── artefacts.csv
    └── candidats_git.csv
```

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

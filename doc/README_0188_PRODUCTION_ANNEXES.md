# 0188 — Sélection des annexes de production

Objectif : simplifier la branche `clean/openmp-production-stripped` en conservant uniquement les annexes utiles à l'exploitation des cinq cas de base et aux opérations générales de post-traitement.

Cas de production couverts :

- Taylor–Green périodique ;
- Poiseuille canal ;
- backward step / marche ;
- piston / compression active ;
- Von Kármán / cylindre fixe en inlet-outlet.

Principes de tri :

1. Conserver les scripts MATLAB génériques de lecture, écriture, inspection, visualisation et animation des dumps `.smpcd`.
2. Conserver les générateurs d'états initiaux utiles aux cinq cas de production.
3. Conserver quelques analyses ou rapports MATLAB directement exploitables pour Poiseuille, backward step et cylindre.
4. Conserver les exemples `.kv` minimaux ou représentatifs ; retirer les sweeps, smokes, variantes de validation et cas redondants.
5. Conserver les documentations générales et les notes nécessaires à la prise en main ; retirer les jalons intermédiaires de validation/développement.

Résumé du tri proposé :

| Racine | Conservés | Retirés |
|---|---:|---:|
| `dev_history/` | 0 | 182 |
| `doc/` | 5 | 4 |
| `docs/` | 22 | 49 |
| `examples/` | 23 | 77 |
| `matlab/` | 29 | 70 |

Le fichier `doc/production_annexes_selection_0188.csv` contient la décision fichier par fichier.

Procédure recommandée :

```bash
# Depuis la racine du dépôt
unzip -o /mnt/c/Users/llemoyne/Downloads/openmp_production_annexes_cleanup_0188_files_only.zip

# Aperçu sans suppression
DRY_RUN=1 bash cleanup_production_annexes_0188.sh

# Application avec sauvegarde tar.gz des fichiers supprimés
DRY_RUN=0 BACKUP=1 bash cleanup_production_annexes_0188.sh

# Ne pas conserver le script de nettoyage dans la branche production
rm cleanup_production_annexes_0188.sh

git status --short
git add doc/README_0188_PRODUCTION_ANNEXES.md doc/production_annexes_selection_0188.csv
git commit -m "0188: prune production annexes"
```

Le nettoyage ne touche pas au noyau C++ ni aux scripts de lancement des exemples. Il ne supprime que des fichiers explicitement listés dans le manifeste de sélection.

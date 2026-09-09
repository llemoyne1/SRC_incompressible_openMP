# Référentiel généré SRC_GPU-SURF

> **Généré automatiquement depuis `Info/db/src_reference.sqlite`. Ne pas éditer ces fichiers à la main.**

Les documents de ce répertoire sont des **vues de publication** de la base relationnelle. Les inventaires bruts, curations et données Git restent les sources de provenance.

**Mainline Git auditée :** `origin/surf`

## Contenu

- [`lexique_jalons.md`](lexique_jalons.md) — décodage rapide des jalons, tri naturel, fonction/statut/support.
- [`jalons.md`](jalons.md) — référentiel canonique détaillé des jalons/phases.
- [`jalons_par_nature.md`](jalons_par_nature.md) — index des jalons par nature.
- [`parametres.md`](parametres.md) — paramètres canoniques, clés `.kv`, champs C++ et alias.
- [`flags.md`](flags.md) — variables d’environnement / alias de runners et paramètres ciblés.
- [`cles_controle_sorties.md`](cles_controle_sorties.md) — clés de contrôle externes et métadonnées de sortie.
- [`artefacts.md`](artefacts.md) — runners, analyseurs, générateurs et autres artefacts utiles.
- [`audit_candidats_git.md`](audit_candidats_git.md) — backlog de candidats historiques à curer.
- [`csv/`](csv/) — exports plats générés pour tri/inspection externe.

## Volumétrie publiée

| Objet | Nombre |
|---|---:|
| Jalons canoniques | 277 |
| Paramètres canoniques | 314 |
| Flags / variables runner | 625 |
| Artefacts indexés | 1677 |
| Candidats Git | 1185 |

## Règle de publication

Les **jalons canoniques** viennent exclusivement de la table `milestones` et des curations validées. Les `git_milestone_candidates` ne sont jamais promus implicitement dans les listes de jalons : ils restent dans le rapport d’audit jusqu’à curation.

Les paramètres et flags sont publiés à partir des **symboles normalisés**, pas à partir des lignes brutes des CSV. Ainsi un champ C++, sa clé `.kv` et ses alias runner restent reliés à un même concept sans être comptés comme plusieurs paramètres physiques.

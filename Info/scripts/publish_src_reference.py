#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import os
import re
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path


def _text(v) -> str:
    if v is None:
        return ''
    return re.sub(r'\s+', ' ', str(v)).strip()


def _dedupe_pipe(v) -> str:
    parts = []
    for part in str(v or '').split(' | '):
        part = _text(part)
        if part and part not in parts:
            parts.append(part)
    return ' | '.join(parts)


def _md(v) -> str:
    return _text(v).replace('\\', '\\\\').replace('|', '\\|')


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + '\n', encoding='utf-8', newline='\n')


def _write_csv(path: Path, headers: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(headers)
        w.writerows(rows)


def _aliases(db: sqlite3.Connection, oid: str) -> dict[str, list[str]]:
    out: dict[str, list[str]] = defaultdict(list)
    for r in db.execute(
        '''SELECT name,name_kind FROM symbol_names WHERE symbol_object_id=?
           ORDER BY is_canonical DESC,name_kind,name''', (oid,)
    ):
        if r['name'] not in out[r['name_kind']]:
            out[r['name_kind']].append(r['name'])
    return out


def _artifact_links(db: sqlite3.Connection, oid: str, incoming: bool = False) -> list[tuple[str, str]]:
    if incoming:
        rows = db.execute(
            '''SELECT r.relation_type,a.path FROM relations r
               JOIN artifacts a ON a.object_id=r.source_object_id
               WHERE r.target_object_id=? ORDER BY r.relation_type,a.path''', (oid,)
        )
    else:
        rows = db.execute(
            '''SELECT r.relation_type,a.path FROM relations r
               JOIN artifacts a ON a.object_id=r.target_object_id
               WHERE r.source_object_id=? ORDER BY r.relation_type,a.path''', (oid,)
        )
    return [(r[0], r[1]) for r in rows]


def _milestone_links(db: sqlite3.Connection, oid: str) -> list[tuple[str, str, str]]:
    rows = db.execute(
        '''SELECT r.relation_type,m.milestone_id,m.name FROM relations r
           JOIN milestones m ON m.object_id=r.target_object_id
           WHERE r.source_object_id=? ORDER BY r.relation_type,m.milestone_id''', (oid,)
    )
    return [(r[0], r[1], r[2]) for r in rows]


def _target_params(db: sqlite3.Connection, oid: str) -> list[str]:
    return [r[0] for r in db.execute(
        '''SELECT s.canonical_name FROM relations r JOIN symbols s ON s.object_id=r.target_object_id
           WHERE r.source_object_id=? AND r.relation_type='SETS_PARAMETER' AND s.namespace='PARAM'
           ORDER BY s.canonical_name''', (oid,)
    )]


def _runner_aliases_for_param(db: sqlite3.Connection, oid: str) -> list[str]:
    return [r[0] for r in db.execute(
        '''SELECT s.canonical_name FROM relations r JOIN symbols s ON s.object_id=r.source_object_id
           WHERE r.target_object_id=? AND r.relation_type='SETS_PARAMETER' AND s.namespace='ENV'
           ORDER BY s.canonical_name''', (oid,)
    )]




def _natural_key(v: str):
    """Case-insensitive natural sort: x9 < x10 and fix2 < fix10."""
    text = _text(v).lower()
    return tuple(int(part) if part.isdigit() else part for part in re.split(r'(\d+)', text))


def _milestone_family(milestone_id: str, group_name: str = '') -> str:
    mid = _text(milestone_id)
    m = re.match(r'(?i)^x(\d+)', mid)
    if m:
        return f"x{int(m.group(1))}"
    m = re.match(r'^(0\d{3})', mid)
    if m:
        return m.group(1)
    if re.fullmatch(r'\d+', mid):
        return mid
    g = _text(group_name)
    if g.lower().startswith('socle') or mid.lower() in {
        'src/mpcd', 'q6', 'resampling', 'q6 multi-espèces', 'q6-g', 'q6-g-f'
    }:
        return 'socle'
    return g or 'autres'


def _milestone_artifacts(db: sqlite3.Connection, oid: str) -> list[tuple[str, str, str]]:
    rows = db.execute(
        '''SELECT r.relation_type,a.path,a.kind FROM relations r
           JOIN artifacts a ON a.object_id=r.target_object_id
           WHERE r.source_object_id=?
           UNION ALL
           SELECT r.relation_type,a.path,a.kind FROM relations r
           JOIN artifacts a ON a.object_id=r.source_object_id
           WHERE r.target_object_id=?
           ORDER BY 1,2''', (oid, oid)
    ).fetchall()
    seen = set()
    out = []
    for rel, path, kind in rows:
        key = (rel, path, kind)
        if key not in seen:
            seen.add(key)
            out.append(key)
    return out


def _milestone_support_type(db: sqlite3.Connection, r: sqlite3.Row) -> str:
    """Human-facing implementation/support type, distinct from milestone nature."""
    source = _text(r['source_file'])
    base = Path(source).name.lower()
    nature = _text(r['nature']).upper()
    labels: list[str] = []

    def add(label: str) -> None:
        if label and label not in labels:
            labels.append(label)

    # The primary source is the strongest signal for scripts-only milestones.
    if re.match(r'^(analy[sz]e|analyse)_', base):
        add('analyseur')
    elif base.startswith(('calibrate_', 'calibrator_', 'calibrateur_')) or 'calibrat' in base:
        add('calibrateur')
    elif base.startswith(('run_', 'run-ok_', 'run_ok_', 'src_mpcd_run_')):
        add('runner')
    elif base.startswith(('check_', 'validate_', 'validation_')):
        add('vérificateur')
    elif base.startswith(('generate_', 'generator_')):
        add('générateur')
    elif base.startswith(('patch_', 'apply_', 'install_')) or base.endswith(('.patch', '.diff')):
        add('modification code')
    elif base.endswith(('.cu', '.cuh', '.cpp', '.cc', '.c', '.h', '.hpp')):
        add('modification code')

    kind_labels = {
        'SOURCE': 'modification code',
        'RUNNER': 'runner',
        'ANALYZER': 'analyseur',
        'GENERATOR': 'générateur',
        'CHECKER': 'vérificateur',
        'MATLAB_TOOL': 'outil MATLAB',
        'VISUALIZER': 'visualisation',
        'BUILD': 'build',
    }
    linked = _milestone_artifacts(db, r['object_id'])
    kinds = {kind for _, _, kind in linked}
    for kind in (
        'SOURCE', 'RUNNER', 'ANALYZER', 'GENERATOR', 'CHECKER',
        'MATLAB_TOOL', 'VISUALIZER', 'BUILD'
    ):
        if kind in kinds:
            add(kind_labels[kind])

    # Documentation is evidence, not normally the implementation/support type of a milestone.
    # When the primary evidence is only a README, the canonical nature decides the fallback.
    if nature == 'CALIBRATOR':
        add('calibrateur')
    elif nature == 'BENCHMARK' and not labels:
        add('benchmark / campagne')
    elif nature == 'DIAGNOSTIC' and not labels:
        add('diagnostic')
    elif nature == 'QUALIFICATION' and not labels:
        add('qualification')
    elif nature == 'INFRA' and not labels:
        add('infrastructure')
    elif nature in {'CODE', 'FIX', 'PERF', 'ABLATION'} and not labels:
        add('modification code')

    if nature == 'ABLATION' and 'modification code' in labels:
        labels[labels.index('modification code')] = 'modification code / ablation'

    # Keep the quick-reference column compact; Nature carries the scientific classification.
    return ' + '.join(labels[:2]) if labels else 'non déterminé'


def publish_milestone_lexicon(db: sqlite3.Connection, out: Path) -> None:
    rows = db.execute('SELECT * FROM milestones').fetchall()
    rows = sorted(rows, key=lambda r: (_natural_key(r['milestone_id']), _natural_key(r['milestone_key'])))
    lines = [
        '# Lexique rapide des jalons SRC_GPU-SURF', '',
        '> Vue générée automatiquement pour décoder rapidement un identifiant (`x10e`, `x7q`, `0490A`, etc.). '
        'Le tri est **naturel numérique puis alphabétique**. La colonne **Type / support** décrit la forme concrète du jalon '
        '(modification code, runner, analyseur, calibrateur…), tandis que **Nature** conserve la classification canonique de la base.', '',
        '| Jalon | Famille | Type / support | Nature | Fonction | Statut |',
        '|---|---|---|---|---|---|',
    ]
    csv_rows = []
    for r in rows:
        family = _milestone_family(r['milestone_id'], r['group_name'])
        support = _milestone_support_type(db, r)
        function = _text(r['summary']) or _text(r['name'])
        lines.append('| ' + ' | '.join([
            f"`{_md(r['milestone_id'])}`", _md(family), _md(support), _md(r['nature']),
            _md(function), _md(r['status'])
        ]) + ' |')
        csv_rows.append([
            _text(r['milestone_id']), family, support, _text(r['nature']), function, _text(r['status']),
            _text(r['milestone_key']), _text(r['canonical_id']), _text(r['domain']), _text(r['name'])
        ])
    _write(out / 'lexique_jalons.md', '\n'.join(lines))
    _write_csv(out / 'csv/lexique_jalons.csv', [
        'milestone_id', 'family', 'support_type', 'nature', 'function', 'status',
        'milestone_key', 'canonical_id', 'domain', 'name'
    ], csv_rows)


def publish_index(db: sqlite3.Connection, out: Path) -> None:
    counts = {
        'Jalons canoniques': db.execute('SELECT count(*) FROM milestones').fetchone()[0],
        'Paramètres canoniques': db.execute("SELECT count(*) FROM symbols WHERE namespace='PARAM'").fetchone()[0],
        'Flags / variables runner': db.execute("SELECT count(*) FROM symbols WHERE namespace='ENV'").fetchone()[0],
        'Artefacts indexés': db.execute('SELECT count(*) FROM artifacts').fetchone()[0],
        'Candidats Git': db.execute('SELECT count(*) FROM git_milestone_candidates').fetchone()[0],
    }
    mainline = db.execute("SELECT value FROM meta WHERE key='git_mainline_ref'").fetchone()
    mainline = mainline[0] if mainline else '-'
    lines = [
        '# Référentiel généré SRC_GPU-SURF', '',
        '> **Généré automatiquement depuis `Info/db/src_reference.sqlite`. Ne pas éditer ces fichiers à la main.**', '',
        'Les documents de ce répertoire sont des **vues de publication** de la base relationnelle. '
        'Les inventaires bruts, curations et données Git restent les sources de provenance.', '',
        f'**Mainline Git auditée :** `{mainline}`', '',
        '## Contenu', '',
        '- [`lexique_jalons.md`](lexique_jalons.md) — décodage rapide des jalons, tri naturel, fonction/statut/support.',
        '- [`jalons.md`](jalons.md) — référentiel canonique détaillé des jalons/phases.',
        '- [`jalons_par_nature.md`](jalons_par_nature.md) — index des jalons par nature.',
        '- [`parametres.md`](parametres.md) — paramètres canoniques, clés `.kv`, champs C++ et alias.',
        '- [`flags.md`](flags.md) — variables d’environnement / alias de runners et paramètres ciblés.',
        '- [`cles_controle_sorties.md`](cles_controle_sorties.md) — clés de contrôle externes et métadonnées de sortie.',
        '- [`artefacts.md`](artefacts.md) — runners, analyseurs, générateurs et autres artefacts utiles.',
        '- [`audit_candidats_git.md`](audit_candidats_git.md) — backlog de candidats historiques à curer.',
        '- [`csv/`](csv/) — exports plats générés pour tri/inspection externe.', '',
        '## Volumétrie publiée', '',
        '| Objet | Nombre |', '|---|---:|',
    ]
    lines += [f'| {_md(k)} | {v} |' for k, v in counts.items()]
    lines += ['',
        '## Règle de publication', '',
        'Les **jalons canoniques** viennent exclusivement de la table `milestones` et des curations validées. '
        'Les `git_milestone_candidates` ne sont jamais promus implicitement dans les listes de jalons : ils restent dans le rapport d’audit jusqu’à curation.', '',
        'Les paramètres et flags sont publiés à partir des **symboles normalisés**, pas à partir des lignes brutes des CSV. '
        'Ainsi un champ C++, sa clé `.kv` et ses alias runner restent reliés à un même concept sans être comptés comme plusieurs paramètres physiques.',
    ]
    _write(out / 'README.md', '\n'.join(lines))


def publish_milestones(db: sqlite3.Connection, out: Path) -> None:
    rows = db.execute(
        '''SELECT * FROM milestones ORDER BY
           CASE WHEN source_row IS NULL THEN 1 ELSE 0 END, COALESCE(source_row,999999), milestone_key'''
    ).fetchall()
    groups: dict[str, list[sqlite3.Row]] = defaultdict(list)
    order: list[str] = []
    for r in rows:
        g = _text(r['group_name']) or 'Autres / curations récentes'
        if g not in groups:
            order.append(g)
        groups[g].append(r)

    lines = ['# Jalons canoniques SRC_GPU-SURF', '',
             '> Cette liste contient uniquement les jalons **validés/canoniques** de la base. Les candidats Git non curés sont exclus.', '']
    for g in order:
        lines += [f'## {g}', '', '| ID | Nature | Domaine | Nom | Statut / portée |', '|---|---|---|---|---|']
        for r in groups[g]:
            lines.append('| ' + ' | '.join([
                f"`{_md(r['milestone_id'])}`", _md(r['nature']), _md(r['domain']),
                _md(r['name']), _md(r['status'])
            ]) + ' |')
        lines.append('')

    lines += ['## Fiches détaillées', '']
    for r in rows:
        lines += [f"### `{r['milestone_id']}` — {_text(r['name'])}", '']
        lines.append(f"- **Clé unique :** `{_text(r['milestone_key'])}`")
        if r['canonical_id']:
            lines.append(f"- **ID canonique :** `{_text(r['canonical_id'])}`")
        lines.append(f"- **Nature / domaine :** `{_text(r['nature'])}` / `{_text(r['domain'])}`")
        lines.append(f"- **Statut :** {_text(r['status']) or '-'}")
        lines.append(f"- **Confiance :** `{_text(r['confidence'])}`")
        if r['introduced_date']:
            lines.append(f"- **Date :** `{_text(r['introduced_date'])}`")
        if r['introduced_commit']:
            lines.append(f"- **Commit :** `{_text(r['introduced_commit'])}`")
        if r['tag']:
            lines.append(f"- **Tag :** `{_text(r['tag'])}`")
        if r['summary']:
            lines += ['', _text(r['summary'])]
        if r['notes']:
            lines += ['', f"**Notes.** {_text(r['notes'])}"]
        rel = _milestone_links(db, r['object_id'])
        if rel:
            lines += ['', '**Relations :**']
            for typ, mid, name in rel[:30]:
                lines.append(f"- `{typ}` → `{mid}` — {_text(name)}")
        arts = _artifact_links(db, r['object_id'], incoming=True)
        if arts:
            lines += ['', '**Artefacts associés :**']
            for typ, path in arts[:30]:
                lines.append(f"- `{typ}` — `{path}`")
        lines.append('')
    _write(out / 'jalons.md', '\n'.join(lines))

    by_nat: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for r in rows:
        by_nat[_text(r['nature']) or 'UNCLASSIFIED'].append(r)
    lines = ['# Jalons par nature', '']
    for nature in sorted(by_nat):
        lines += [f'## {nature}', '', '| ID | Nom | Domaine | Statut |', '|---|---|---|---|']
        for r in by_nat[nature]:
            lines.append(f"| `{_md(r['milestone_id'])}` | {_md(r['name'])} | {_md(r['domain'])} | {_md(r['status'])} |")
        lines.append('')
    _write(out / 'jalons_par_nature.md', '\n'.join(lines))

    csv_rows = [[_text(r[k]) for k in (
        'milestone_key','milestone_id','canonical_id','group_name','name','summary','nature','domain','status','confidence','introduced_date','introduced_commit','tag','notes'
    )] for r in rows]
    _write_csv(out / 'csv/jalons.csv', [
        'milestone_key','milestone_id','canonical_id','group_name','name','summary','nature','domain','status','confidence','introduced_date','introduced_commit','tag','notes'
    ], csv_rows)


def publish_parameters(db: sqlite3.Connection, out: Path) -> None:
    rows = db.execute("SELECT * FROM symbols WHERE namespace='PARAM' ORDER BY lower(canonical_name),canonical_name").fetchall()
    lines = ['# Paramètres canoniques SRC_GPU-SURF', '',
             '> Une fiche correspond à un **concept canonique**. Les différentes clés `.kv`, champs C++ et alias sont regroupés sous cette fiche.', '',
             '| Paramètre | Type | Défaut | Catégorie | Statut |', '|---|---|---|---|---|']
    for r in rows:
        lines.append(f"| `{_md(r['canonical_name'])}` | {_md(_dedupe_pipe(r['expected_type']))} | {_md(_dedupe_pipe(r['default_value']))} | {_md(_dedupe_pipe(r['category']))} | {_md(_dedupe_pipe(r['status']))} |")
    lines += ['', '## Fiches détaillées', '']

    csv_rows = []
    for r in rows:
        names = _aliases(db, r['object_id'])
        kv = names.get('PARAM_KEY', []) + names.get('PARAM_PATTERN', [])
        cpp = names.get('CPP_FIELD', [])
        aliases = []
        for kind in ('PARAM_ALIAS','RUNNER_ALIAS'):
            aliases += names.get(kind, [])
        runner = _runner_aliases_for_param(db, r['object_id'])
        arts = _artifact_links(db, r['object_id'])
        milestones = _milestone_links(db, r['object_id'])

        lines += [f"### `{r['canonical_name']}`", '']
        lines.append(f"- **Type :** {_dedupe_pipe(r['expected_type']) or '-'}")
        lines.append(f"- **Défaut :** `{_dedupe_pipe(r['default_value']) or '-'}`")
        lines.append(f"- **Contraintes / valeurs :** {_dedupe_pipe(r['constraints_text']) or '-'}")
        lines.append(f"- **Catégorie :** {_dedupe_pipe(r['category']) or '-'}")
        lines.append(f"- **Statut :** {_dedupe_pipe(r['status']) or '-'}")
        if kv: lines.append('- **Clé(s) `.kv` :** ' + ', '.join(f'`{x}`' for x in kv))
        if cpp: lines.append('- **Champ(s) C++ :** ' + ', '.join(f'`{x}`' for x in cpp))
        if aliases: lines.append('- **Autres alias :** ' + ', '.join(f'`{x}`' for x in aliases))
        if runner: lines.append('- **Variables runner qui écrivent ce paramètre :** ' + ', '.join(f'`{x}`' for x in runner))
        if r['effect_role']:
            lines += ['', _dedupe_pipe(r['effect_role'])]
        if r['remarks']:
            lines += ['', f"**Remarques.** {_dedupe_pipe(r['remarks'])}"]
        if arts:
            lines += ['', '**Sources / usages :**']
            for typ, path in arts[:40]:
                lines.append(f"- `{typ}` — `{path}`")
        if milestones:
            lines += ['', '**Jalons associés :**']
            for typ, mid, name in milestones[:25]:
                lines.append(f"- `{typ}` → `{mid}` — {_text(name)}")
        lines.append('')

        csv_rows.append([
            _text(r['canonical_name']), _dedupe_pipe(r['category']), _dedupe_pipe(r['status']),
            _dedupe_pipe(r['expected_type']), _dedupe_pipe(r['default_value']), _dedupe_pipe(r['constraints_text']),
            _dedupe_pipe(r['effect_role']), _dedupe_pipe(r['remarks']), ';'.join(kv), ';'.join(cpp),
            ';'.join(aliases), ';'.join(runner), ';'.join(path for _, path in arts),
            ';'.join(mid for _, mid, _ in milestones), _dedupe_pipe(r['source_inventory'])
        ])
    _write(out / 'parametres.md', '\n'.join(lines))
    _write_csv(out / 'csv/parametres.csv', [
        'canonical_name','category','status','expected_type','default_value','constraints','effect_role','remarks',
        'kv_keys','cpp_fields','aliases','runner_variables','source_paths','milestones','source_inventory'
    ], csv_rows)


def publish_flags(db: sqlite3.Connection, out: Path) -> None:
    rows = db.execute("SELECT * FROM symbols WHERE namespace='ENV' ORDER BY lower(canonical_name),canonical_name").fetchall()
    lines = ['# Flags et variables d’environnement / runners', '',
             '> Ces entrées sont séparées des paramètres `.kv`. Lorsqu’un flag écrit un paramètre canonique, la relation est indiquée explicitement.', '',
             '| Nom | Type | Défaut | Paramètre(s) ciblé(s) | Catégorie | Statut |', '|---|---|---|---|---|---|']
    csv_rows = []
    for r in rows:
        targets = _target_params(db, r['object_id'])
        lines.append(f"| `{_md(r['canonical_name'])}` | {_md(_dedupe_pipe(r['expected_type']))} | {_md(_dedupe_pipe(r['default_value']))} | {_md(', '.join(targets))} | {_md(_dedupe_pipe(r['category']))} | {_md(_dedupe_pipe(r['status']))} |")
        arts = _artifact_links(db, r['object_id'])
        milestones = _milestone_links(db, r['object_id'])
        csv_rows.append([
            _text(r['canonical_name']), _dedupe_pipe(r['category']), _dedupe_pipe(r['status']),
            _dedupe_pipe(r['expected_type']), _dedupe_pipe(r['default_value']), _dedupe_pipe(r['effect_role']),
            _dedupe_pipe(r['remarks']), ';'.join(targets), ';'.join(path for _, path in arts),
            ';'.join(mid for _, mid, _ in milestones), _dedupe_pipe(r['source_inventory'])
        ])
    lines += ['', '## Fiches détaillées', '']
    for r in rows:
        targets = _target_params(db, r['object_id'])
        names = _aliases(db, r['object_id'])
        arts = _artifact_links(db, r['object_id'])
        milestones = _milestone_links(db, r['object_id'])
        lines += [f"### `{r['canonical_name']}`", '']
        lines.append(f"- **Type :** {_dedupe_pipe(r['expected_type']) or '-'}")
        lines.append(f"- **Défaut :** `{_dedupe_pipe(r['default_value']) or '-'}`")
        lines.append(f"- **Catégorie :** {_dedupe_pipe(r['category']) or '-'}")
        lines.append(f"- **Statut :** {_dedupe_pipe(r['status']) or '-'}")
        if targets: lines.append('- **Écrit / contrôle :** ' + ', '.join(f'`{x}`' for x in targets))
        all_aliases = sorted({x for vals in names.values() for x in vals if x != r['canonical_name']})
        if all_aliases: lines.append('- **Alias :** ' + ', '.join(f'`{x}`' for x in all_aliases))
        if r['effect_role']:
            lines += ['', _dedupe_pipe(r['effect_role'])]
        if r['remarks']:
            lines += ['', f"**Remarques.** {_dedupe_pipe(r['remarks'])}"]
        if arts:
            lines += ['', '**Défini/utilisé dans :**']
            for typ, path in arts[:30]: lines.append(f"- `{typ}` — `{path}`")
        if milestones:
            lines += ['', '**Jalons associés :**']
            for typ, mid, name in milestones[:20]: lines.append(f"- `{typ}` → `{mid}` — {_text(name)}")
        lines.append('')
    _write(out / 'flags.md', '\n'.join(lines))
    _write_csv(out / 'csv/flags.csv', [
        'name','category','status','expected_type','default_value','effect_role','remarks','target_parameters','source_paths','milestones','source_inventory'
    ], csv_rows)



def publish_control_output_keys(db: sqlite3.Connection, out: Path) -> None:
    rows = db.execute(
        "SELECT * FROM symbols WHERE namespace IN ('CONTROL','OUTPUT') ORDER BY namespace,lower(canonical_name),canonical_name"
    ).fetchall()
    lines = ['# Clés de contrôle et métadonnées de sortie', '',
             '> Clés qui ne sont pas des paramètres solveur `.kv` : contrôles externes (par exemple LiveVis) et clés de métadonnées de sortie.', '']
    csv_rows = []
    for namespace in ('CONTROL','OUTPUT'):
        subset = [r for r in rows if r['namespace']==namespace]
        if not subset:
            continue
        lines += [f'## {namespace}', '', '| Nom | Type | Défaut | Rôle |', '|---|---|---|---|']
        for r in subset:
            lines.append(f"| `{_md(r['canonical_name'])}` | {_md(_dedupe_pipe(r['expected_type']))} | {_md(_dedupe_pipe(r['default_value']))} | {_md(_dedupe_pipe(r['effect_role']))} |")
            arts = _artifact_links(db, r['object_id'])
            csv_rows.append([
                namespace,_text(r['canonical_name']),_dedupe_pipe(r['category']),_dedupe_pipe(r['status']),
                _dedupe_pipe(r['expected_type']),_dedupe_pipe(r['default_value']),_dedupe_pipe(r['constraints_text']),
                _dedupe_pipe(r['effect_role']),_dedupe_pipe(r['remarks']),';'.join(path for _,path in arts),_dedupe_pipe(r['source_inventory'])
            ])
        lines.append('')
    _write(out / 'cles_controle_sorties.md', '\n'.join(lines))
    _write_csv(out / 'csv/cles_controle_sorties.csv', [
        'namespace','name','category','status','expected_type','default_value','constraints','effect_role','remarks','source_paths','source_inventory'
    ], csv_rows)


def publish_artifacts(db: sqlite3.Connection, out: Path) -> None:
    interesting = ('RUNNER','ANALYZER','GENERATOR','CHECKER','MATLAB_TOOL','VISUALIZER','BUILD','DOCUMENTATION')
    qmarks = ','.join('?' for _ in interesting)
    rows = db.execute(
        f'''SELECT * FROM artifacts WHERE kind IN ({qmarks}) ORDER BY kind,path''', interesting
    ).fetchall()
    groups: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for r in rows: groups[r['kind']].append(r)
    lines = ['# Artefacts consultables du projet', '',
             '> Vue centrée sur les runners, analyseurs, générateurs, outils MATLAB, visualisation, builds et documentation. Les sources C++/CUDA restent indexées dans SQLite mais ne sont pas déroulées ici.', '']
    csv_rows = []
    for kind in sorted(groups):
        lines += [f'## {kind}', '', '| Fichier | Jalons liés | Statut |', '|---|---|---|']
        for r in groups[kind]:
            mil = [m[1] for m in _milestone_links(db, r['object_id'])]
            # Milestone relations can also point from artifact to milestone, which _milestone_links captures.
            lines.append(f"| `{_md(r['path'])}` | {_md(', '.join(mil))} | {_md(r['status'])} |")
            csv_rows.append([_text(r['path']), _text(r['basename']), _text(r['kind']), _text(r['language']), _text(r['status']), _text(r['milestone_hint']), ';'.join(mil), _text(r['description'])])
        lines.append('')
    _write(out / 'artefacts.md', '\n'.join(lines))
    _write_csv(out / 'csv/artefacts.csv', ['path','basename','kind','language','status','milestone_hint','milestones','description'], csv_rows)


def publish_candidates(db: sqlite3.Connection, out: Path) -> None:
    rows = db.execute(
        '''SELECT c.*,g.subject AS anchor_subject,s.status AS mainline_status
           FROM git_milestone_candidates c
           LEFT JOIN git_commits g ON g.hash=c.anchor_commit
           LEFT JOIN git_commit_mainline_status s ON s.commit_hash=c.anchor_commit
           ORDER BY CASE c.max_confidence WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,
                    c.normalized_label,c.first_date,c.candidate_id'''
    ).fetchall()
    counter = Counter((r['status'], r['max_confidence']) for r in rows)
    lines = ['# Audit des candidats-jalons Git', '',
             '> **Ce document n’est pas le référentiel canonique.** Il sert de backlog de curation. Un candidat n’apparaît dans `jalons.md` qu’après promotion explicite dans la table `milestones`.', '',
             '## Résumé', '', '| Statut | Confiance | Nombre |', '|---|---|---:|']
    for (status, conf), n in sorted(counter.items()):
        lines.append(f'| {status} | {conf} | {n} |')

    linked = [r for r in rows if r['linked_milestone_object_id']]
    unresolved_a = [r for r in rows if not r['linked_milestone_object_id'] and r['max_confidence']=='A']
    unresolved_b_signal = [r for r in rows if not r['linked_milestone_object_id'] and r['max_confidence']=='B' and (r['evidence_count'] >= 2 or r['mainline_status']=='UNIQUE_OUTSIDE_MAINLINE')]
    lines += ['', '## Candidats déjà reliés à un jalon canonique', '', '| Label | Candidat | Preuves |', '|---|---|---:|']
    for r in linked:
        lines.append(f"| `{_md(r['label'])}` | `{_md(r['candidate_id'])}` | {r['evidence_count']} |")
    lines += ['', '## Priorité A — candidats non curés', '', '| Label | Date | Commit / sujet | Preuves | Mainline |', '|---|---|---|---:|---|']
    for r in unresolved_a:
        anchor = (r['anchor_commit'] or '')[:10]
        subj = _text(r['anchor_subject'])
        lines.append(f"| `{_md(r['label'])}` | {_md(r['first_date'])} | `{anchor}` {_md(subj)} | {r['evidence_count']} | {_md(r['mainline_status'])} |")
    lines += ['', '## Priorité B à signal fort', '',
              'Candidats B conservés ici uniquement s’ils disposent de plusieurs preuves ou sont ancrés sur un commit unique hors mainline.', '',
              '| Label | Date | Commit / sujet | Preuves | Mainline |', '|---|---|---|---:|---|']
    for r in unresolved_b_signal:
        anchor = (r['anchor_commit'] or '')[:10]
        lines.append(f"| `{_md(r['label'])}` | {_md(r['first_date'])} | `{anchor}` {_md(r['anchor_subject'])} | {r['evidence_count']} | {_md(r['mainline_status'])} |")
    lines += ['', f'Le CSV complet contient les **{len(rows)} candidats**, y compris les entrées B/C à faible signal qui ne sont pas développées dans cette vue Markdown.', '']
    _write(out / 'audit_candidats_git.md', '\n'.join(lines))

    csv_rows = [[
        _text(r['candidate_id']), _text(r['label']), _text(r['normalized_label']), _text(r['candidate_family']),
        _text(r['status']), _text(r['max_confidence']), str(r['evidence_count']), _text(r['anchor_commit']),
        _text(r['first_date']), _text(r['last_date']), _text(r['linked_milestone_object_id']),
        _text(r['mainline_status']), _text(r['anchor_subject']), _text(r['notes'])
    ] for r in rows]
    _write_csv(out / 'csv/candidats_git.csv', [
        'candidate_id','label','normalized_label','family','status','confidence','evidence_count','anchor_commit',
        'first_date','last_date','linked_milestone_object_id','mainline_status','anchor_subject','notes'
    ], csv_rows)


def publish_reference(db: sqlite3.Connection, output_dir: Path) -> dict[str, int]:
    db.row_factory = sqlite3.Row
    output_dir.mkdir(parents=True, exist_ok=True)
    publish_index(db, output_dir)
    publish_milestone_lexicon(db, output_dir)
    publish_milestones(db, output_dir)
    publish_parameters(db, output_dir)
    publish_flags(db, output_dir)
    publish_control_output_keys(db, output_dir)
    publish_artifacts(db, output_dir)
    publish_candidates(db, output_dir)
    return {
        'published_files': sum(1 for p in output_dir.rglob('*') if p.is_file()),
        'published_milestones': db.execute('SELECT count(*) FROM milestones').fetchone()[0],
        'published_params': db.execute("SELECT count(*) FROM symbols WHERE namespace='PARAM'").fetchone()[0],
        'published_flags': db.execute("SELECT count(*) FROM symbols WHERE namespace='ENV'").fetchone()[0],
    }


def main() -> None:
    info_root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description='Generate human-readable SRC_GPU-SURF reference views from SQLite.')
    ap.add_argument('--db', type=Path, default=info_root / 'db/src_reference.sqlite')
    ap.add_argument('--output', type=Path, default=info_root / 'generated')
    args = ap.parse_args()
    db = sqlite3.connect(args.db)
    try:
        stats = publish_reference(db, args.output)
    finally:
        db.close()
    for k, v in stats.items():
        print(f'{k}={v}')


if __name__ == '__main__':
    main()
